$ProgressPreference = 'SilentlyContinue'
$out = 'C:\OEM\odt.exe'
$urls = @()

try {
    $r = Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -UseBasicParsing -ErrorAction Stop
    $urls += [regex]::Matches($r.Content, 'https://download\.microsoft\.com/download/[^''\s]+officedeploymenttool[^''\s]+\.exe') | ForEach-Object { $_.Value }
} catch {
    Write-Host ('ODT page scrape failed: ' + $_)
}

$urls += 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18827-20140.exe'

foreach ($u in $urls) {
    try {
        Write-Host ('Trying ' + $u)
        Invoke-WebRequest -Uri $u -OutFile $out -ErrorAction Stop
        if ((Get-Item $out).Length -gt 1MB) {
            Write-Host ('Downloaded ODT from ' + $u)
            exit 0
        }
    } catch {
        Remove-Item $out -ErrorAction SilentlyContinue
    }
}

Write-Host 'All ODT download attempts failed.'
exit 1
