if ($parentProcess = Get-Process -Id $args[0] -ErrorAction SilentlyContinue) {
    $parentProcess.WaitForExit()
}

if ($SSHProcess = Get-Process -Id $args[1] -ErrorAction SilentlyContinue) {
    $SSHProcess.Kill()
}

if ($LoggingProcess = Get-Process -Id $args[2] -ErrorAction SilentlyContinue) {
    $LoggingProcess.Kill()
}

$Config = Get-Content '.secret/credentials.json' | ConvertFrom-Json
$DOApiToken = $Config.DOApiToken
$DODropletTag = $Config.DODropletTag
$DOHeaders = @{
    Authorization = "Bearer $DOApiToken"
    'Content-Type' = 'application/json'
}

Invoke-WebRequest -Uri "https://api.digitalocean.com/v2/droplets?tag_name=${DODropletTag}" -Method Delete -Headers $DOHeaders -UseBasicParsing