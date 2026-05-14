$target  = 'C:\php'
$current = [Environment]::GetEnvironmentVariable('Path', 'Machine')

if ($current -notlike "*$target*") {
    [Environment]::SetEnvironmentVariable('Path', ($current + ';' + $target), 'Machine')
    Write-Host "Added $target to machine PATH."
} else {
    Write-Host "$target already on machine PATH."
}

# A registry write to the Path env var is invisible to processes that
# inherit env from explorer.exe (or any other already-running parent)
# until WM_SETTINGCHANGE is broadcast. Without this, a user RDPing
# in and opening cmd/powershell sees a stale PATH and "php" / "composer"
# look uninstalled. Broadcast so new shells pick the change up.
$sig = @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@

if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
    Add-Type -TypeDefinition $sig -ErrorAction Stop
}

$HWND_BROADCAST   = [IntPtr]0xffff
$WM_SETTINGCHANGE = 0x1A
$SMTO_ABORTIFHUNG = 0x0002
$result           = [UIntPtr]::Zero

[void][NativeMethods]::SendMessageTimeout(
    $HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment',
    $SMTO_ABORTIFHUNG, 5000, [ref]$result)

Write-Host 'Broadcast WM_SETTINGCHANGE to refresh PATH in running shells.'
