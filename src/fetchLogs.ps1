if ($PSVersionTable.PSVersion.Major -le 5) {
    # Workaround for missing SkipCertificateCheck switch
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                    return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    $allProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $allProtocols
}

$ParentProcessPid = $args[0]
$LocalHTTPSPort = $args[1]

$LoggingSubFolderName = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LoggingFolderPath = Get-Location | Join-Path -ChildPath "Logs/${LoggingSubFolderName}"

New-Item -Path ${LoggingFolderPath} -Type Directory -Force

while (Get-Process -Id $ParentProcessPid -ErrorAction SilentlyContinue) {
    try {
        Start-Sleep -Seconds 15
        $LoggingTimestamp = Get-Date -UFormat "%s" -Millisecond 0
        $LogFilePath = Join-Path -Path $LoggingFolderPath -ChildPath "${LoggingTimestamp}.xml"
        if ($PSVersionTable.PSVersion.Major -le 5) {
            Invoke-WebRequest -Uri "https://localhost:${LocalHTTPSPort}/stats" -UseBasicParsing -OutFile $LogFilePath
        } else {
            Invoke-WebRequest -SkipCertificateCheck -Uri "https://localhost:$LocalHTTPSPort/stats" -UseBasicParsing -OutFile $LogFilePath
        }
    } catch {
        continue
    }
}