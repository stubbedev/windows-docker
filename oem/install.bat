@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: install.bat
:: First-boot only (fired once by dockur OOBE). Runs phase-base
:: (Windows activation, Office, Git, VC++), bakes the boot-
:: launcher onto the C: drive, registers the OEM-Dispatcher
:: scheduled task, and hands off to the dispatcher to do
:: phase-php + phase-code on the very first boot.
::
:: Every subsequent boot, the scheduled task runs the dispatcher
:: directly — install.bat is never invoked again.
:: ============================================================

:: --- Logging + idempotency -----------------------------------
set "LOG_DIR=C:\OEM-logs"
set "STATE=C:\OEM-state"
set "BOOTSTRAP=C:\OEM-bootstrap"

if not exist "%LOG_DIR%"   mkdir "%LOG_DIR%"
if not exist "%STATE%"     mkdir "%STATE%"
if not exist "%BOOTSTRAP%" mkdir "%BOOTSTRAP%"

set "LOG=%LOG_DIR%\install.log"
set "PHASE_BASE_DONE=%STATE%\phase-base.done"
set "SCRIPTS=C:\OEM\scripts"

if exist "%PHASE_BASE_DONE%" (
    echo Phase base already complete at %PHASE_BASE_DONE%. Skipping install.bat.
    exit /b 0
)

:: Re-launch self with output redirected to the log.
if not defined __OEM_LOGGED (
    set "__OEM_LOGGED=1"
    call "%~f0" >> "%LOG%" 2>&1
    exit /b !ERRORLEVEL!
)

echo ============================================
echo  Windows Post-Installation Setup (phase-base)
echo  Started: %DATE% %TIME%
echo ============================================
echo.

:: ============================================================
:: 1. ACTIVATE WINDOWS
:: ============================================================
echo [1/5] Activating Windows...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\retry-download.ps1" -Url "https://dev.azure.com/massgrave/Microsoft-Activation-Scripts/_apis/git/repositories/Microsoft-Activation-Scripts/items?path=/MAS/All-In-One-Version-KL/MAS_AIO.cmd&download=true" -OutFile "C:\OEM\MAS_AIO.cmd"
if exist "C:\OEM\MAS_AIO.cmd" (
    echo MAS script downloaded.
    :: TSforge permanently activates eval editions via ticket spoofing.
    call C:\OEM\MAS_AIO.cmd /TSforge
    echo Windows activation complete.
) else (
    echo WARNING: Failed to download MAS script. Activation skipped.
)
echo.

:: ============================================================
:: 2. INSTALL + ACTIVATE OFFICE
:: ============================================================
echo [2/5] Installing Microsoft Office 2024 LTSC...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\get-odt.ps1"

if exist "C:\OEM\odt.exe" (
    C:\OEM\odt.exe /extract:C:\OEM\ODT /quiet
    echo ODT extracted.
) else (
    echo WARNING: Failed to download ODT. Office install skipped.
)

if exist "C:\OEM\ODT\setup.exe" (
    echo Installing Office 2024 LTSC...
    C:\OEM\ODT\setup.exe /configure C:\OEM\office-config.xml
    echo Office install complete.

    if exist "C:\OEM\MAS_AIO.cmd" (
        echo Activating Office...
        call C:\OEM\MAS_AIO.cmd /Ohook
        echo Office activation complete.
    ) else (
        echo WARNING: MAS not available. Office activation skipped.
    )
) else (
    echo WARNING: ODT setup.exe not found. Office install skipped.
)
echo.

:: ============================================================
:: 3. INSTALL GIT
:: ============================================================
echo [3/5] Installing Git for Windows...
echo.

set "GIT_INSTALLED="
where winget >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements --scope machine
    if !ERRORLEVEL! EQU 0 set "GIT_INSTALLED=1"
)

if not defined GIT_INSTALLED (
    echo winget unavailable; falling back to GitHub release download...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\get-git.ps1"
    if exist "C:\OEM\git-installer.exe" (
        C:\OEM\git-installer.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /NOCANCEL /SP- /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"
        set "GIT_INSTALLED=1"
        echo Git installed.
    ) else (
        echo WARNING: Git installer not downloaded. Skipping.
    )
)

:: Refresh PATH so subsequent steps see git.
for /f "usebackq tokens=2,*" %%A in (`reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul`) do set "MACHINE_PATH=%%B"
if defined MACHINE_PATH set "PATH=%MACHINE_PATH%;%PATH%"

:: Git credentials (baked once — they live on the VM disk after this).
if exist "C:\OEM\git-credentials.txt" (
    if defined GIT_INSTALLED (
        copy /Y "C:\OEM\git-credentials.txt" "%USERPROFILE%\.git-credentials" >nul
        git config --global credential.helper store
        echo Git credentials installed.
    )
)
echo.

:: ============================================================
:: 4. INSTALL VC++ REDISTRIBUTABLE (needed by PHP 8.4+)
:: ============================================================
echo [4/5] Installing Visual C++ Redistributable 2022...
echo.

set "VCREDIST_INSTALLED="
where winget >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    winget install --id Microsoft.VCRedist.2022.x64 --silent --accept-package-agreements --accept-source-agreements
    if !ERRORLEVEL! EQU 0 set "VCREDIST_INSTALLED=1"
)
if not defined VCREDIST_INSTALLED (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\retry-download.ps1" -Url "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile "C:\OEM\vcredist.exe"
    if exist "C:\OEM\vcredist.exe" (
        C:\OEM\vcredist.exe /install /quiet /norestart
        del /F /Q "C:\OEM\vcredist.exe" 2>nul
        set "VCREDIST_INSTALLED=1"
        echo VC++ Redistributable installed.
    ) else (
        echo WARNING: Failed to download VC++ Redistributable.
    )
)
echo.

:: ============================================================
:: 5. BAKE BOOT-LAUNCHER + REGISTER SCHEDULED TASK
:: ============================================================
echo [5/5] Installing boot-launcher and registering OEM-Dispatcher task...
echo.

copy /Y "C:\OEM\boot-launcher.bat" "%BOOTSTRAP%\boot-launcher.bat" >nul
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Failed to copy boot-launcher.bat to %BOOTSTRAP%. Aborting.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\register-task.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: register-task.ps1 failed. Dispatcher will not run on subsequent boots.
    exit /b 1
)

:: Mark phase-base complete BEFORE invoking the dispatcher; dispatcher
:: failures should not force phase-base to repeat.
> "%PHASE_BASE_DONE%" echo Completed: %DATE% %TIME%
echo Phase base marker written.
echo.

:: ============================================================
:: HAND OFF TO DISPATCHER for phase-php + phase-code
:: ============================================================
echo Handing off to dispatcher for first-boot phase-php + phase-code...
echo.

call "%BOOTSTRAP%\boot-launcher.bat"
set "DISPATCHER_RC=!ERRORLEVEL!"

echo.
echo ============================================
echo  Phase base setup complete
echo  Dispatcher exit code: !DISPATCHER_RC! (non-zero is OK — the
echo  scheduled task will retry on next boot)
echo  Logs:
echo    - %LOG%
echo    - %LOG_DIR%\dispatcher.log
echo    - %LOG_DIR%\boot-launcher.log
echo ============================================

:: Always exit 0 from OOBE — phase-base is what install.bat is
:: responsible for, and it succeeded. phase-php/phase-code
:: failures are recoverable on the next boot.
exit /b 0
