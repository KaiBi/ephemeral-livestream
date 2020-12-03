$ErrorActionPreference = 'Stop'

Write-Host '========== Spawn Cleanup Watchdog'

$currentProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
$watchdogProcess = Start-Process -PassThru -WindowStyle Hidden -FilePath 'powershell' -ArgumentList "-c src/watchdog.ps1 ${currentProcessId}"
Write-Host '. ok'



Write-Host '========== Read Credentials File'

$Config = Get-Content -Path .secret/credentials.json | ConvertFrom-Json

$DOApiToken = $Config.DOApiToken
$DOSSHKeyFingerprint = $Config.DOSSHKeyFingerprint
$FloatingIP = $Config.FloatingIP
$ScriptVersion = $Config.ScriptVersion
$GithubRepositoryName = $Config.GithubRepositoryName
$DomainName = $Config.DomainName
$DODropletTag = $Config.DODropletTag

Write-Host '. ok'



Write-Host '========== Check for Updates'

try {
    $CheckLatestUpdateResponse = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/${GithubUserName}/${GithubRepositoryName}/commits/master"
    $LatestCommitHash = $CheckLatestUpdateResponse.sha
    if ($ScriptVersion -eq $LatestCommitHash) {
        Write-Host 'Script is up to date.'
    } else {
        Write-Host 'New script version available. Performing update ...'
        Invoke-WebRequest -Uri "https://github.com/${GithubUserName}/${GithubRepositoryName}/archive/master.zip" -UseBasicParsing -OutFile 'master.zip'
        $watchdogProcess.Kill()
        $Config.ScriptVersion = $LatestCommitHash
        $Config | ConvertTo-Json | Out-File -FilePath '.secret/credentials.json'
        Start-Sleep -Seconds 3
        Start-Process -FilePath 'powershell' -ArgumentList "
            Start-Sleep -Seconds 1
            Get-ChildItem -Exclude .secret,master.zip . | Remove-Item -Recurse -Force
            Expand-Archive -Path master.zip -DestinationPath .
            Remove-Item -Force master.zip
            Move-Item -Force -Path '${GithubRepositoryName}-master/*' -Destination .
            Remove-Item -Force -Recurse '${GithubRepositoryName}-master'
            Start-Process -FilePath 'powershell' -ArgumentList '-c src/start.ps1'"
        Exit
    }
} catch {
    Write-Host 'Something went wrong during the update process. Continuing with the current version.'
}



Write-Host '========== Request Droplet Creation'

$DOHeaders = @{
    Authorization = "Bearer $DOApiToken"
    'Content-Type' = 'application/json'
}

$UploadArchiveFolder = Get-Location | Join-Path -ChildPath 'build/'
$UploadArchivePath = $UploadArchiveFolder | Join-Path -ChildPath 'upload.zip'
if (!(Test-Path -Path $UploadArchiveFolder -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $UploadArchiveFolder
}
Compress-Archive -Path src/upload/*,.secret/id_ed25519.pub,.secret/ssh_host_* -DestinationPath $UploadArchivePath -CompressionLevel Optimal -Force
$Base64EncodedUploadArchive = [Convert]::ToBase64String([IO.File]::ReadAllBytes($UploadArchivePath))
Remove-Item -Force $UploadArchivePath
$RandomSubdomainName = -join ((0x61..0x7A) | Get-Random -Count 10 | ForEach-Object -Process {[char]$_})
$Hostname = "${RandomSubdomainName}.${DomainName}"
$InitScript = "#!/bin/bash
cd /root
echo `"${Base64EncodedUploadArchive}`" | base64 -d > install.zip
apt-get update
apt-get install -y unzip
unzip install.zip
rm -f install.zip
chmod 0755 install.bash
/root/install.bash ${RandomSubdomainName} ${DomainName} > /root/install.log 2>&1
"

$CreateDropletRequestBody = @{
    image = 'ubuntu-18-04-x64'
    name = $Hostname
    region = 'fra1'
    size = 'c-4'
    tags = $DODropletTag
    ssh_keys = @( $DOSSHKeyFingerprint )
    user_data = $InitScript
}
$CreateDropletResponse = ConvertTo-Json $CreateDropletRequestBody | Invoke-RestMethod -Uri 'https://api.digitalocean.com/v2/droplets' -Method Post -Headers $DOHeaders
$CreateDropletActionUri = $CreateDropletResponse.links.actions[0].href
$DropletID = $CreateDropletResponse.droplet.id
Write-Host ". Droplet id is: ${DropletID}, Hostname is: ${Hostname}"



Write-Host '========== Await Droplet Availability'

do {
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 15
    $CreateDropletActionResponse = Invoke-RestMethod -Uri $CreateDropletActionUri -Method Get -Headers $DOHeaders
    $CreateDropletActionStatus = $CreateDropletActionResponse.action.status
} until ($CreateDropletActionStatus -ne 'in-progress')
Write-Host " $CreateDropletActionStatus"

if ($CreateDropletActionStatus -ne 'completed') {
    Write-Host 'Something went wrong during droplet creation. This is likely a temporary issue with the cloud provider. Please restart the script.'
    Start-Sleep -Seconds 10
    Exit
}



Write-Host '========== Assign Floating IP'

$AssignFloatingIPBody = @{
    type = 'assign'
    droplet_id = $DropletID
}
$AssignFloatingIPResponse = ConvertTo-Json $AssignFloatingIPBody | Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/floating_ips/${FloatingIP}/actions" -Method Post -Headers $DOHeaders
$AssignFloatingIPActionID = $AssignFloatingIPResponse.action.id
Write-Host " Action id is: ${AssignFloatingIPActionID}"



Write-Host '========== Await Floating IP Availability'

do {
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 15
    $AssignFloatingIPActionResponse = Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/floating_ips/${FloatingIP}/actions/${AssignFloatingIPActionID}" -Method Get -Headers $DOHeaders
    $AssignFloatingIPActionStatus = $AssignFloatingIPActionResponse.action.status
} until ($AssignFloatingIPActionStatus -ne 'in-progress')
Write-Host " ${AssignFloatingIPActionStatus}"

if ($AssignFloatingIPActionStatus -ne 'completed') {
    Write-Host 'Something went wrong during assignment of the floating IP address. This is likely a temporary issue with the cloud provider. Please restart the script.'
    Start-Sleep -Seconds 10
    Exit
}



Write-Host '========== Await Https Availability'

Write-Host 'If this takes longer than 10 minutes something went wrong and you should restart the script.'
do {
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 15
    try {
        $ServerHealthCheckResponse = Invoke-WebRequest -Uri $Hostname -Method Head -UseBasicParsing
        $ServerHealthCheckStatusCode = $ServerHealthCheckResponse.StatusCode
    } catch {
        $ServerHealthCheckStatusCode = 500
    }
} until ($ServerHealthCheckStatusCode -eq 200)
Write-Host ' ok'



Write-Host '========== Establish SSH Connection and Tunnels'

do {
    $RandomUnboundLocalPortNumber = Get-Random -Minimum 16384 -Maximum 65535
} while (Test-NetConnection -ComputerName localhost -Port $RandomUnboundLocalPortNumber -InformationLevel Quiet -ErrorAction SilentlyContinue)
Write-Host ". Local port for logging is ${RandomUnboundLocalPortNumber}"

if (!(Test-Path -Path "build/plink.exe")) {
    Write-Host '. Plink does not seem to be available. Downloading now.'
    Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe' -UseBasicParsing -OutFile 'build/plink.exe'
}

$HostKeyFingerprint = Get-Content -Path '.secret/host_fingerprint'
$SSHProcess = Start-Process -PassThru -WindowStyle Hidden -FilePath 'build/plink.exe' -ArgumentList "-ssh -noagent -batch -hostkey ${HostKeyFingerprint} -l root -N -i .secret/id_ed25519.ppk -L ${RandomUnboundLocalPortNumber}:127.0.0.1:443 -L 1935:127.0.0.1:1935 -P 22 ${Hostname}"
Start-Sleep -Seconds 2
$SSHProcessId = $SSHProcess.Id
Write-Host ". Process id is ${SSHProcessId}"
If (!(Get-Process -Id $SSHProcessId -ErrorAction SilentlyContinue)) {
    Write-Host '. Process is inactive. There seems to be an error. This is unusual. You can restart the script to try again, but it is very likely that you will have to debug.'
    Start-Sleep -Seconds 10
    Exit
}



Write-Host '========== Start fetching the rtmp logs'

$LoggingProcess = Start-Process -PassThru -WindowStyle Hidden -FilePath 'powershell' -ArgumentList "-c src/fetchLogs.ps1 $currentProcessId $RandomUnboundLocalPortNumber"
Start-Sleep -Seconds 2
$LoggingProcessId = $LoggingProcess.Id
Write-Host ". Process id is ${LoggingProcessId}"



Write-Host '========== Restart Watchdog'

Start-Process -WindowStyle Hidden -FilePath 'powershell' -ArgumentList "-c src/watchdog.ps1 $currentProcessId $SSHProcessId $LoggingProcessId"
$watchdogProcess.Kill()
Write-host '. ok'



Write-Host '========== Print User Information'

Write-Host
Write-Host 'The installation has finished and the server is ready.'
Write-Host 'You should point OBS Studio to the following address: rtmp://localhost/stream'
Write-Host 'The domain(s) under which the server is reachable are:'
Write-Host "- $Hostname"
Write-Host "- $DomainName"
Write-Host
Write-Host 'Press Ctrl-C or close this window to free up all cloud resources.'

while ($true) {
    Start-Sleep -Seconds 3600
}