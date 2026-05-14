$taskName = 'OEM-Dispatcher'
$launcher = 'C:\OEM-bootstrap\boot-launcher.bat'

if (-not (Test-Path $launcher)) {
    Write-Host ('ERROR: ' + $launcher + ' not found.')
    exit 1
}

$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "' + $launcher + '"')
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -RestartCount 0 `
    -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Runs the OEM phase dispatcher at every Windows startup.' | Out-Null

Write-Host ('Registered scheduled task ' + $taskName + ' -> ' + $launcher)
exit 0
