$configPath = if ($env:PHP_CONFIG_PATH) { $env:PHP_CONFIG_PATH } else { 'C:\OEM-runtime\php-config.ini' }
$iniPath    = if ($env:PHP_INI_PATH)    { $env:PHP_INI_PATH }    else { 'C:\php\php.ini' }

if (-not (Test-Path $configPath)) { Write-Host ('Missing ' + $configPath); exit 1 }
if (-not (Test-Path $iniPath))    { Write-Host ('Missing ' + $iniPath);    exit 1 }

$content = Get-Content $iniPath -Raw
$lines   = Get-Content $configPath

# Windows PHP php.ini-production uses ";extension=name" — no .dll, no php_ prefix.
# That's also the canonical enabled form: "extension=name" lets PHP locate
# php_<name>.dll in extension_dir. We try that pattern first and only fall
# back to .dll/php_*.dll variants for non-standard ini layouts.

foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -match '^;|^$') { continue }
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { continue }
    $key = $parts[0].Trim()
    $val = $parts[1].Trim()
    if ($key -eq 'version') { continue }

    if ($key -eq 'extension') {
        $extName = $val
        # Skip if already enabled.
        $enabledPattern = '(?m)^\s*extension\s*=\s*(' + [regex]::Escape($extName) + '|' + [regex]::Escape($extName) + '\.dll|php_' + [regex]::Escape($extName) + '\.dll)\s*(;.*)?$'
        if ($content -match $enabledPattern) { continue }

        # Try to uncomment the canonical Windows form: ";extension=name".
        $bare = '(?m)^;\s*extension\s*=\s*' + [regex]::Escape($extName) + '\s*(;.*)?$'
        if ($content -match $bare) {
            $content = $content -replace $bare, ('extension=' + $extName)
            continue
        }

        # Fallbacks for non-standard ini files.
        $dll = '(?m)^;\s*extension\s*=\s*' + [regex]::Escape($extName) + '\.dll\s*(;.*)?$'
        if ($content -match $dll) {
            $content = $content -replace $dll, ('extension=' + $extName + '.dll')
            continue
        }
        $phpDll = '(?m)^;\s*extension\s*=\s*php_' + [regex]::Escape($extName) + '\.dll\s*(;.*)?$'
        if ($content -match $phpDll) {
            $content = $content -replace $phpDll, ('extension=php_' + $extName + '.dll')
            continue
        }

        # Not found anywhere; append the canonical form.
        $content += "`r`nextension=$extName`r`n"
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
Write-Host ('php.ini updated at ' + $iniPath)
