@echo off
:: ============================================================
:: phase-code.bat
:: Re-runs when shared\.runtime\post-install.bat hash changes.
:: Always idempotent: nothing here should fail if called twice.
::
:: Steps:
::   1. Refresh project tree at C:\Projects from \\host.lan\Data,
::      excluding the orchestrator and the healthcheck flag.
::   2. Run the user's post-install.bat.
:: ============================================================

setlocal EnableDelayedExpansion

set "OEM_RUNTIME=C:\OEM-runtime"
set "SMB=\\host.lan\Data"
set "DEST=C:\Projects"

:: Ensure C:\php is on PATH for post-install. On first boot the
:: machine PATH change from phase-php isn't yet visible to this
:: cmd, so prepend explicitly.
if exist "C:\php\php.exe" set "PATH=C:\php;%PATH%"

echo ----------------------------------------
echo Phase code: starting %DATE% %TIME%
echo ----------------------------------------

if not exist "%DEST%" mkdir "%DEST%"

if exist "%SMB%\" (
    echo Mirroring %SMB% -> %DEST% (excluding orchestrator + state files)...
    robocopy "%SMB%" "%DEST%" /E /R:5 /W:5 /NFL /NDL /NJH /NJS ^
        /XD ".runtime" ".oem-state" ".logs" ^
        /XF "install.done" "install.running"
    set "RC=!ERRORLEVEL!"
    :: robocopy: 0-7 = success/info, >=8 = error.
    if !RC! GEQ 8 (
        echo ERROR: robocopy mirror failed with code !RC!.
        exit /b !RC!
    )
) else (
    echo WARNING: %SMB% not accessible. Skipping project file sync.
)

:: --- Run the user's post-install -----------------------------
if exist "%OEM_RUNTIME%\post-install.bat" (
    echo Running post-install.bat...
    call "%OEM_RUNTIME%\post-install.bat"
    if !ERRORLEVEL! NEQ 0 (
        echo ERROR: post-install.bat returned non-zero (!ERRORLEVEL!).
        exit /b !ERRORLEVEL!
    )
) else (
    echo No post-install.bat in %OEM_RUNTIME%. Skipping.
)

echo ----------------------------------------
echo Phase code: success %DATE% %TIME%
echo ----------------------------------------
exit /b 0
