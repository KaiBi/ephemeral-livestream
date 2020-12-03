$ErrorActionPreference = 'Stop'

if (!(Get-Command 'docker')) {
    throw 'The current user needs to be able to run docker.'
}

Write-Host 'Generating SSH keys with docker ...'
docker run --rm -v ${PWD}:/data -w /data ubuntu:18.04 "bash" "-c" "cd src; ./setup.bash"

Write-Host ''
Write-Host ''
Write-Host 'Please enter your DigitalOcean API Token. You can create access tokens here:'
Write-Host 'https://cloud.digitalocean.com/account/api/tokens'
Write-Host 'Make sure that the token has write access.'
while ($True) {
    $DOApiToken = (Read-Host 'Please enter your token (or press Ctrl-C to exit): ').ToLower()
    if (!($DOApiToken -match '^[a-f0-9]{64}$')) {
        Write-Host 'Token does not seem valid. Tokens consist of 64 hexadecimal characters.'
        continue
    }
    $DOHeaders = @{
        Authorization = "Bearer ${DOApiToken}";
        'Content-Type' = 'application/json'
    }
    try {
        $GetUserInformationResponse = Invoke-RestMethod -Uri 'https://api.digitalocean.com/v2/account' -Method Get -Headers $DOHeaders
    } catch {}
    if ($GetUserInformationResponse.account.status -eq 'active') {
        break
    }
    Write-Host 'Token is invalid or user is not active.'
}

Write-Host ''
Write-Host ''
Write-Host 'Please enter the domain name under which your livestream will be available.'
Write-Host 'You need to have your DNS A-record set to a floating IP registered on your DO account.'
Write-Host 'You also need to set a wildcard subdomain with the same A-record (to the same floating IP).'
Write-Host 'So, if your domain is "live.example.com" and points to 1.2.3.4, then "*.live.example.com"'
Write-Host 'must also be set and point to this ip address.'
while ($True) {
    $Domain = Read-Host 'Please enter the domain name (or press Ctrl-C to exit): '
    try {
        $DomainIP = (Resolve-DnsName -Name $Domain -DnsOnly).IPAddress
    } catch {}
    if ($DomainIP -eq '') {
        Write-Host 'Could not resolve this domain'
        continue
    }
    $RandomSubdomain = (-join ((0x61..0x7A) | Get-Random -Count 10 | ForEach-Object -Process {[char]$_})) + '.' + $Domain
    try {
        $SubdomainIP = (Resolve-DnsName -Name $RandomSubdomain -DnsOnly).IPAddress
    } catch {}
    if ($DomainIP -ne $SubdomainIP) {
        Write-Host 'The IP address of a random subdomain did not match the IP of the domain.'
        Write-Host 'Please make sure that the wildcard DNS is set up correctly.'
        continue
    }
    try {
        $GetFloatingIPResponse = Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/floating_ips/${DomainIP}" -Method Get -Headers $DOHeaders
        if ($GetFloatingIPResponse.floating_ip.locked -ne $False) {
            throw
        }
    } catch {
        Write-Host "The DNS setup seems correct, but the IP ${DomainIP} does not seem to be registered as floating IP on DigitalOcean or is locked."
        continue
    }
    break
}

Write-Host ''
Write-Host ''
Write-Host 'Please choose a tag for the droplets that will be created.'
Write-Host 'The script will delete all droplets with this tag on close. So make sure it is not used for anything else.'
while ($True) {
    $DropletTag = Read-Host 'Enter tag (or press Ctrl-C to exit): '
    if ($DropletTag -match '^[a-z][a-z0-9]{0,19}$') {
        break
    }
    Write-Host "Let's be reasonable and use at most 20 alphanumeric characters, starting with a letter."
}

Write-Host ''
Write-Host ''
Write-Host 'The script has an auto-update functionality where it compares and fetches the newest version from github.'
Write-Host 'You may configure the github user and repository name to use that functionality.'
Write-Host 'Leaving them blank will cause the script to throw an error during auto-update, but it will continue nonetheless.'
while ($True) {
    $GithubUser = Read-Host 'Please enter the github user (or leave blank or press Ctrl-C to exit): '
    if ($GithubUser -eq '') {
        $GithubRepo = ''
        break
    }
    $GithubRepo = Read-Host 'Please enter the github repository (or press Ctrl-C to exit): '
    try {
        Invoke-RestMethod -Uri "https://api.github.com/repos/${GithubUser}/${GithubRepo}/commits/master" -Method Get
    } catch {
        Write-Host 'Could not query the commits on that repository.'
        Write-Host 'Either it does not exist or we have hit the api rate limit and need to try again later.'
        continue
    }
    break
}

Write-Host ''
Write-Host ''
Write-Host 'If you want to access the created droplet via an existing SSH key'
Write-Host 'that is already registered with DigitalOcean you can specify the key fingerprint here.'
while ($True) {
    $SSHKeyFingerprint = Read-Host 'Please enter the ssh key fingerprint (or press Ctrl-C to exit): '
    if ($SSHKeyFingerprint -eq '') {
        break
    }
    if (!($SSHKeyFingerprint -match '^([a-f0-9]{2}:){15}[a-f0-9]{2}$')) {
        Write-Host 'The format does not seem right. Search for something like "3b:16:bf:e4:8b:00:8b:b8:59:8c:a9:d3:f0:19:45:fa"'
        continue
    }
    try {
        Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/account/keys/${SSHKeyFingerprint}" -Method Get -Headers @DOHeaders
    } catch {
        Write-Host 'A key with this fingerprint does not seem to exist on DigitalOcean.'
        continue
    }
    break
}

$Config = @{
    DOApiToken = $DOApiToken;
    DomainName = $Domain;
    FloatingIP = $DomainIP;
    ScriptVersion = '';
    DODropletTag = $DropletTag;
    GithubUserName = $GithubUser;
    GithubRepositoryName = $GithubRepo;
    DOSSHKeyFingerprint = $SSHKeyFingerprint;
}
$Config | ConvertTo-Json | Out-File -FilePath '.secret/credentials.json'

Write-Host 'All configuration files have been written to the .secret folder. The setup has been finished.'
Read-Host ''