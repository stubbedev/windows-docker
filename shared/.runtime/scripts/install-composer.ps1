$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$target = if ($env:COMPOSER_TARGET) { $env:COMPOSER_TARGET } else { 'C:\php' }
$setup  = Join-Path $target 'composer-setup.php'

if (-not (Test-Path $target)) {
    Write-Host ('Target directory ' + $target + ' does not exist.')
    exit 1
}

Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile $setup -ErrorAction Stop

$expected = (New-Object System.Net.WebClient).DownloadString('https://composer.github.io/installer.sig').Trim()
$actual   = (Get-FileHash $setup -Algorithm SHA384).Hash

if ($actual -ine $expected) {
    Remove-Item $setup -Force
    Write-Host ('Composer installer signature mismatch (expected ' + $expected + ', got ' + $actual + ')')
    exit 1
}

Write-Host ('Composer installer downloaded to ' + $setup + ' (signature OK).')
exit 0
