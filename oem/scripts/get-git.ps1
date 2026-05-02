$ProgressPreference = 'SilentlyContinue'
$out = 'C:\OEM\git-installer.exe'

try {
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'oem-install' } -ErrorAction Stop
    $asset = $rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
    if (-not $asset) {
        Write-Host 'No matching Git asset in latest release.'
        exit 1
    }
    Write-Host ('Downloading ' + $asset.name)
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $out -ErrorAction Stop
    exit 0
} catch {
    Write-Host ('Git release lookup failed: ' + $_)
    exit 1
}
