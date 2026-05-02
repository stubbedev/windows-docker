$base = $env:PHP_BASE_URL
$name = $env:PHP_ZIP_NAME
$zip  = 'C:\OEM\php.zip'

if (-not $base -or -not $name) {
    Write-Host 'PHP_BASE_URL or PHP_ZIP_NAME not set; skipping verify.'
    exit 0
}

$expected = $null
foreach ($u in @("$base/$name.sha256", "$base/archives/$name.sha256")) {
    try {
        $raw = (New-Object System.Net.WebClient).DownloadString($u)
        $expected = $raw.Trim().Split()[0]
        if ($expected) { break }
    } catch {}
}

if (-not $expected) {
    Write-Host 'PHP checksum sidecar unavailable; skipping verify.'
    exit 0
}

$actual = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($actual -ieq $expected) {
    Write-Host 'PHP checksum OK.'
    exit 0
} else {
    Write-Host ('PHP checksum MISMATCH (expected ' + $expected + ', got ' + $actual + ')')
    exit 1
}
