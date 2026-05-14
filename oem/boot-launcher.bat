@echo off
:: ============================================================
:: boot-launcher.bat
:: Baked into C:\OEM-bootstrap during phase-base.
:: The OEM-Dispatcher scheduled task invokes this at every boot.
:: It refreshes C:\OEM-runtime from the SMB share, then runs
:: the dispatcher from the local copy.
:: ============================================================

setlocal EnableDelayedExpansion
set "SMB=\\host.lan\Data\.runtime"
set "LOCAL=C:\OEM-runtime"
set "LOG_DIR=C:\OEM-logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Wait briefly for the SMB share to come up (host.lan is dockur's gateway).
set "ATTEMPTS=0"
:wait_smb
if exist "%SMB%\dispatcher.bat" goto smb_ready
set /a ATTEMPTS+=1
if !ATTEMPTS! GEQ 30 (
    echo [boot-launcher] SMB share %SMB% unreachable after 60s, aborting. >> "%LOG_DIR%\boot-launcher.log"
    exit /b 1
)
timeout /t 2 /nobreak >nul
goto wait_smb

:smb_ready
if not exist "%LOCAL%" mkdir "%LOCAL%"
robocopy "%SMB%" "%LOCAL%" /MIR /R:5 /W:5 /NFL /NDL /NJH /NJS >> "%LOG_DIR%\boot-launcher.log" 2>&1
set "RC=%ERRORLEVEL%"
:: robocopy returns 0-7 for success/info, >=8 for errors.
if %RC% GEQ 8 (
    echo [boot-launcher] robocopy failed with code %RC%, aborting. >> "%LOG_DIR%\boot-launcher.log"
    exit /b %RC%
)

call "%LOCAL%\dispatcher.bat"
exit /b %ERRORLEVEL%
