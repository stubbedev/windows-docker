param(
    [Parameter(Mandatory=$true)][string]$IniPath,
    [Parameter(Mandatory=$true)][string]$ExtDir
)

if (-not (Test-Path $IniPath)) {
    Write-Host ('Missing ' + $IniPath)
    exit 1
}

$content = Get-Content $IniPath -Raw
$line    = 'extension_dir = "' + $ExtDir + '"'

if ($content -match '(?m)^\s*;?\s*extension_dir\s*=') {
    $content = $content -replace '(?m)^\s*;?\s*extension_dir\s*=.*$', $line
} else {
    $content += "`r`n$line`r`n"
}

[System.IO.File]::WriteAllText($IniPath, $content)
Write-Host ('extension_dir set to ' + $ExtDir + ' in ' + $IniPath)
