@echo off
:: ============================================================
:: dispatcher.bat
:: Runs every boot via the OEM-Dispatcher scheduled task.
:: - Flips the healthcheck signal to "not ready"
:: - Runs each phase if its trigger input hash changed (or first
::   run, or previous run did not complete cleanly).
:: - Restores the healthcheck signal only if all phases pass.
:: ============================================================

setlocal EnableDelayedExpansion

set "RUNTIME=C:\OEM-runtime"
set "STATE=C:\OEM-state"
set "LOG_DIR=C:\OEM-logs"
set "SMB=\\host.lan\Data"
set "SMB_LOG_DIR=%SMB%\.logs"
set "HEALTH_FILE=%SMB%\install.done"

if not exist "%STATE%"   mkdir "%STATE%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Prefer the SMB log so the host can tail it. Fall back to local
:: if the SMB share isn't writable.
set "LOG=%LOG_DIR%\dispatcher.log"
if exist "%SMB%\" (
    if not exist "%SMB_LOG_DIR%" mkdir "%SMB_LOG_DIR%" 2>nul
    if exist "%SMB_LOG_DIR%" set "LOG=%SMB_LOG_DIR%\dispatcher.log"
)

:: Re-launch self with stdout/stderr appended to the log.
if not defined __DISPATCHER_LOGGED (
    set "__DISPATCHER_LOGGED=1"
    call "%~f0" %* >> "%LOG%" 2>&1
    exit /b !ERRORLEVEL!
)

echo.
echo ============================================
echo  Dispatcher run: %DATE% %TIME%
echo ============================================

:: Flip healthcheck to "not ready" until we finish successfully.
del /F /Q "%HEALTH_FILE%" 2>nul

set "DISPATCHER_FAILED="

:: Phase PHP: re-run when php-config.ini hash changes.
call :run_phase php "%RUNTIME%\phase-php.bat" "%RUNTIME%\php-config.ini"
if !ERRORLEVEL! NEQ 0 set "DISPATCHER_FAILED=1"

:: Phase Code: re-run when post-install.bat hash changes.
:: (Project file changes don't trigger re-run; bump the marker or
:: edit post-install.bat to force one.)
if not defined DISPATCHER_FAILED (
    call :run_phase code "%RUNTIME%\phase-code.bat" "%RUNTIME%\post-install.bat"
    if !ERRORLEVEL! NEQ 0 set "DISPATCHER_FAILED=1"
)

if defined DISPATCHER_FAILED (
    echo Dispatcher: at least one phase failed. Healthcheck remains not-ready.
    exit /b 1
)

> "%HEALTH_FILE%" echo Completed: %DATE% %TIME%
echo Dispatcher: all phases complete. Healthcheck flipped to ready.
exit /b 0

:: --------- subroutine: run_phase NAME SCRIPT HASH_INPUT ---------
:: HASH_INPUT may be empty to force the phase to run every boot.
:run_phase
set "P_NAME=%~1"
set "P_SCRIPT=%~2"
set "P_HASH_INPUT=%~3"
set "P_DONE=%STATE%\phase-%P_NAME%.done"
set "P_RUNNING=%STATE%\phase-%P_NAME%.running"
set "P_HASH=%STATE%\phase-%P_NAME%.hash"

if not exist "%P_SCRIPT%" (
    echo Phase %P_NAME%: script %P_SCRIPT% missing. Skipping.
    exit /b 0
)

set "CURR_HASH="
if defined P_HASH_INPUT (
    if exist "%P_HASH_INPUT%" (
        for /f "delims=" %%h in ('powershell -NoProfile -Command "(Get-FileHash -Path '%P_HASH_INPUT%' -Algorithm SHA256).Hash"') do set "CURR_HASH=%%h"
    )
)

set "STORED_HASH="
if exist "%P_HASH%" set /p STORED_HASH=<"%P_HASH%"

set "RUN_REASON="
if not exist "%P_DONE%"               set "RUN_REASON=first run"
if exist "%P_RUNNING%"                set "RUN_REASON=previous run was interrupted"
if not defined P_HASH_INPUT           set "RUN_REASON=always-run phase"
if defined CURR_HASH (
    if /i "!CURR_HASH!" NEQ "!STORED_HASH!" set "RUN_REASON=input hash changed"
)

if not defined RUN_REASON (
    echo Phase %P_NAME%: up to date, skipping.
    exit /b 0
)

echo.
echo Phase %P_NAME%: %RUN_REASON%. Running %P_SCRIPT%...
> "%P_RUNNING%" echo %DATE% %TIME%
call "%P_SCRIPT%"
set "P_RC=!ERRORLEVEL!"

if !P_RC! NEQ 0 (
    echo Phase %P_NAME%: FAILED [rc=!P_RC!]. Marker not advanced; .running marker left in place for next boot to retry.
    exit /b !P_RC!
)

if defined CURR_HASH (
    > "%P_HASH%" echo !CURR_HASH!
) else (
    del /F /Q "%P_HASH%" 2>nul
)
> "%P_DONE%" echo %DATE% %TIME%
del /F /Q "%P_RUNNING%" 2>nul
echo Phase %P_NAME%: SUCCESS.
exit /b 0
