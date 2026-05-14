param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$MaxAttempts = 3,
    [int]$InitialDelaySec = 5
)

$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$attempt = 0
$delay   = $InitialDelaySec

while ($attempt -lt $MaxAttempts) {
    $attempt++
    try {
        Write-Host ('Attempt ' + $attempt + '/' + $MaxAttempts + ': ' + $Url)
        if (Test-Path $OutFile) { Remove-Item -Force $OutFile }
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        if ((Get-Item $OutFile).Length -gt 0) {
            Write-Host ('Downloaded to ' + $OutFile)
            exit 0
        }
        Write-Host 'Downloaded file is empty.'
    } catch {
        Write-Host ('Attempt ' + $attempt + ' failed: ' + $_.Exception.Message)
    }
    if ($attempt -lt $MaxAttempts) {
        Write-Host ('Sleeping ' + $delay + 's before retry...')
        Start-Sleep -Seconds $delay
        $delay = $delay * 2
    }
}

Write-Host ('All ' + $MaxAttempts + ' download attempts failed for ' + $Url)
exit 1
