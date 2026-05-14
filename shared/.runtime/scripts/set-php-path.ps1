$old = [Environment]::GetEnvironmentVariable('Path','Machine')
if ($old -notlike '*C:\php*') {
    [Environment]::SetEnvironmentVariable('Path', ($old + ';C:\php'), 'Machine')
    Write-Host 'Added C:\php to machine PATH.'
} else {
    Write-Host 'C:\php already on machine PATH.'
}
