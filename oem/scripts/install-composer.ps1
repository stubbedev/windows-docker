$ProgressPreference = 'SilentlyContinue'
$setup = 'C:\php\composer-setup.php'

Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile $setup -ErrorAction Stop

$expected = (New-Object System.Net.WebClient).DownloadString('https://composer.github.io/installer.sig').Trim()
$actual   = (Get-FileHash $setup -Algorithm SHA384).Hash

if ($actual -ine $expected) {
    Remove-Item $setup -Force
    Write-Host ('Composer installer signature mismatch (expected ' + $expected + ', got ' + $actual + ')')
    exit 1
}

Write-Host 'Composer installer signature OK.'
exit 0
