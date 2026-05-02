$configPath = if ($env:PHP_CONFIG_PATH) { $env:PHP_CONFIG_PATH } else { 'C:\OEM\php-config.ini' }
$iniPath    = 'C:\php\php.ini'

if (-not (Test-Path $configPath)) { Write-Host ('Missing ' + $configPath); exit 1 }
if (-not (Test-Path $iniPath))    { Write-Host ('Missing ' + $iniPath);    exit 1 }

$content = Get-Content $iniPath -Raw
$lines   = Get-Content $configPath

foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -match '^;|^$') { continue }
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { continue }
    $key = $parts[0].Trim()
    $val = $parts[1].Trim()
    if ($key -eq 'version') { continue }

    if ($key -eq 'extension') {
        $extName    = $val
        $pattern    = '^;\s*extension\s*=\s*' + [regex]::Escape($extName) + '\.dll\s*$'
        $dllPattern = '^;\s*extension\s*=\s*php_' + [regex]::Escape($extName) + '\.dll\s*$'

        if ($content -match $pattern) {
            $content = $content -replace $pattern, ('extension=' + $extName + '.dll')
        } elseif ($content -match $dllPattern) {
            $content = $content -replace $dllPattern, ('extension=php_' + $extName + '.dll')
        } else {
            $content += "`r`nextension=$extName.dll`r`n"
        }
    } else {
        $iniPattern = '(?m)^;?\s*' + [regex]::Escape($key) + '\s*=.*$'
        if ($content -match $iniPattern) {
            $content = $content -replace $iniPattern, ($key + ' = ' + $val)
        } else {
            $content += "`r`n$key = $val`r`n"
        }
    }
}

[System.IO.File]::WriteAllText($iniPath, $content)
Write-Host 'php.ini updated.'
