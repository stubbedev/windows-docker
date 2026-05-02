@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: Logging + idempotency
:: ============================================================
if not exist "C:\OEM-logs" mkdir "C:\OEM-logs"
set "LOG=C:\OEM-logs\install.log"
set "DONE_MARKER=C:\OEM-logs\install.done"
set "SCRIPTS=C:\OEM\scripts"

if exist "%DONE_MARKER%" (
    echo Install already completed at %DONE_MARKER%. Skipping.
    exit /b 0
)

:: Re-launch self with output redirected to the log (cmd-only, no PS tee).
if not defined __OEM_LOGGED (
    set "__OEM_LOGGED=1"
    call "%~f0" >> "%LOG%" 2>&1
    exit /b !ERRORLEVEL!
)

echo ============================================
echo  Windows Post-Installation Setup
echo  Started: %DATE% %TIME%
echo ============================================
echo.

:: ============================================================
:: 1. ACTIVATE WINDOWS (HWID, then TSforge for eval editions)
:: ============================================================
echo [1/7] Activating Windows...
echo.

powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://dev.azure.com/massgrave/Microsoft-Activation-Scripts/_apis/git/repositories/Microsoft-Activation-Scripts/items?path=/MAS/All-In-One-Version-KL/MAS_AIO.cmd&download=true' -OutFile 'C:\OEM\MAS_AIO.cmd' -ErrorAction Stop"
if exist "C:\OEM\MAS_AIO.cmd" (
    echo MAS script downloaded successfully.
    :: TSforge permanently activates eval editions via ticket spoofing.
    :: HWID is skipped — it cannot activate eval SKUs and only wastes time.
    call C:\OEM\MAS_AIO.cmd /TSforge
    echo Windows activation complete.
) else (
    echo WARNING: Failed to download MAS script. Activation skipped.
)
echo.

:: ============================================================
:: 2. INSTALL OFFICE 2024 LTSC
:: ============================================================
echo [2/7] Installing Microsoft Office 2024 LTSC...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\get-odt.ps1"

if exist "C:\OEM\odt.exe" (
    C:\OEM\odt.exe /extract:C:\OEM\ODT /quiet
    echo Office Deployment Tool extracted.
) else (
    echo WARNING: Failed to download ODT. Office installation skipped.
)

if exist "C:\OEM\ODT\setup.exe" (
    echo Installing Office 2024 LTSC...
    C:\OEM\ODT\setup.exe /configure C:\OEM\office-config.xml
    echo Office installation complete.
) else (
    echo WARNING: ODT setup.exe not found. Office installation skipped.
)
echo.

:: ============================================================
:: 3. ACTIVATE OFFICE (Ohook)
:: ============================================================
echo [3/7] Activating Office...
echo.

if exist "C:\OEM\MAS_AIO.cmd" (
    call C:\OEM\MAS_AIO.cmd /Ohook
    echo Office activation complete.
) else (
    echo WARNING: MAS script not available. Office activation skipped.
)
echo.

:: ============================================================
:: 4. INSTALL GIT (winget primary, GitHub release fallback)
:: ============================================================
echo [4/7] Installing Git for Windows...
echo.

set "GIT_INSTALLED="
where winget >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements --scope machine
    if !ERRORLEVEL! EQU 0 set "GIT_INSTALLED=1"
)

if not defined GIT_INSTALLED (
    echo winget unavailable or failed; falling back to GitHub release download...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\get-git.ps1"
    if exist "C:\OEM\git-installer.exe" (
        C:\OEM\git-installer.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /NOCANCEL /SP- /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"
        set "GIT_INSTALLED=1"
        echo Git installed.
    ) else (
        echo WARNING: Git installer not downloaded. Skipping.
    )
)

:: Refresh PATH so subsequent steps see git
for /f "usebackq tokens=2,*" %%A in (`reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul`) do set "MACHINE_PATH=%%B"
if defined MACHINE_PATH set "PATH=%MACHINE_PATH%;%PATH%"
echo.

:: ============================================================
:: 5. INSTALL VC++ REDISTRIBUTABLE + PHP
:: ============================================================
echo [5/7] Installing PHP...
echo.

:: PHP 8.4 requires VCRUNTIME140.dll >= 14.43. Install VC++ Redist 2022 first
:: so PHP doesn't emit DLL-version warnings on every invocation.
echo Installing Visual C++ Redistributable 2022...
set "VCREDIST_INSTALLED="
where winget >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    winget install --id Microsoft.VCRedist.2022.x64 --silent --accept-package-agreements --accept-source-agreements
    if !ERRORLEVEL! EQU 0 set "VCREDIST_INSTALLED=1"
)
if not defined VCREDIST_INSTALLED (
    powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile 'C:\OEM\vcredist.exe' -ErrorAction Stop"
    if exist "C:\OEM\vcredist.exe" (
        C:\OEM\vcredist.exe /install /quiet /norestart
        del /F /Q "C:\OEM\vcredist.exe" 2>nul
        set "VCREDIST_INSTALLED=1"
        echo VC++ Redistributable installed.
    ) else (
        echo WARNING: Failed to download VC++ Redistributable. PHP may show DLL warnings.
    )
)
echo.

if not exist "C:\php" mkdir C:\php
if not exist "C:\php\logs" mkdir C:\php\logs

if not exist "C:\OEM\php-config.ini" (
    echo ERROR: C:\OEM\php-config.ini not found. PHP installation skipped.
    goto :php_skip
)

set "PHP_VERSION="
for /f "usebackq tokens=1,* delims==" %%A in ("C:\OEM\php-config.ini") do (
    set "line_key=%%A"
    set "line_val=%%B"
    set "line_key=!line_key: =!"
    set "line_val=!line_val: =!"
    if /i "!line_key!"=="version" set "PHP_VERSION=!line_val!"
)

if not defined PHP_VERSION (
    echo ERROR: No version specified in php-config.ini. PHP installation skipped.
    goto :php_skip
)

echo PHP version: !PHP_VERSION!

:: Determine VS toolset by minor version: 8.4+ -> vs17, otherwise vs16
for /f "tokens=1,2 delims=." %%a in ("!PHP_VERSION!") do (
    set "PHP_MAJOR=%%a"
    set "PHP_MINOR=%%b"
)
set "PHP_VS=vs16"
if !PHP_MAJOR! GEQ 9 set "PHP_VS=vs17"
if !PHP_MAJOR! EQU 8 if !PHP_MINOR! GEQ 4 set "PHP_VS=vs17"
echo PHP toolset: !PHP_VS!

set "PHP_ZIP_NAME=php-!PHP_VERSION!-Win32-!PHP_VS!-x64.zip"
set "PHP_BASE_URL=https://windows.php.net/downloads/releases"

:: Download PHP zip (current release, then archive).
:: Force TLS 1.2 — PS 5.1 on Win 10 LTSC defaults to TLS 1.0 which windows.php.net rejects.
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!PHP_BASE_URL!/!PHP_ZIP_NAME!' -OutFile 'C:\OEM\php.zip' -ErrorAction Stop"
if not exist "C:\OEM\php.zip" (
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!PHP_BASE_URL!/archives/!PHP_ZIP_NAME!' -OutFile 'C:\OEM\php.zip' -ErrorAction Stop"
)

if not exist "C:\OEM\php.zip" (
    echo WARNING: Failed to download PHP !PHP_VERSION! ^(!PHP_VS!^). Installation skipped.
    goto :php_skip
)

:: Verify PHP zip SHA-256 against the sidecar published by windows.php.net
echo Verifying PHP archive checksum...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-php.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: PHP archive failed checksum verification. Aborting PHP install.
    del /F /Q "C:\OEM\php.zip" 2>nul
    goto :php_skip
)

:: Extract PHP
powershell -NoProfile -Command "Expand-Archive -Path 'C:\OEM\php.zip' -DestinationPath 'C:\OEM\php-extract' -Force"
xcopy "C:\OEM\php-extract\*.*" "C:\php\" /E /I /Y /Q

:: Create php.ini from production template
if exist "C:\php\php.ini-production" (
    copy /Y "C:\php\php.ini-production" "C:\php\php.ini"
) else if exist "C:\php\php.ini-development" (
    copy /Y "C:\php\php.ini-development" "C:\php\php.ini"
)

:: Always enable openssl and curl — required for Composer and HTTPS.
:: apply-ini.ps1 may also set these; this guarantees them even if that step fails.
powershell -NoProfile -Command "(Get-Content C:\php\php.ini) -replace '^;extension=openssl$','extension=openssl' -replace '^;extension=curl$','extension=curl' | Set-Content C:\php\php.ini"

:: Apply php-config.ini settings
echo Applying php-config.ini settings...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\apply-ini.ps1"

:: Install Composer (verify SHA-384 from composer.github.io/installer.sig)
echo Installing Composer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\install-composer.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Composer installer verification failed. Skipping Composer install.
) else (
    C:\php\php.exe C:\php\composer-setup.php --install-dir=C:\php --filename=composer.phar
    del /F /Q "C:\php\composer-setup.php" 2>nul

    > "C:\php\composer.bat" echo @echo off
    >>"C:\php\composer.bat" echo "%%~dp0php.exe" "%%~dp0composer.phar" %%*

    echo Composer installed.
)

:: Add PHP to system PATH permanently
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\set-php-path.ps1"
set "PATH=C:\php;%PATH%"

C:\php\php.exe -v
if exist "C:\php\composer.phar" C:\php\php.exe C:\php\composer.phar --version
echo PHP installed to C:\php and added to PATH.

:php_skip
echo.

:: ============================================================
:: 6. CONFIGURE GIT CREDENTIALS (optional)
:: ============================================================
echo [6/7] Configuring Git credentials...
echo.

if exist "C:\OEM\git-credentials.txt" (
    if defined GIT_INSTALLED (
        copy /Y "C:\OEM\git-credentials.txt" "%USERPROFILE%\.git-credentials" >nul
        git config --global credential.helper store
        echo Git credentials installed to %USERPROFILE%\.git-credentials.
    ) else (
        echo WARNING: git-credentials.txt present but Git not installed. Skipping.
    )
) else (
    echo No oem\git-credentials.txt found. Skipping git credential setup.
)
echo.

:: ============================================================
:: 7. COPY SHARED FILES + RUN POST-INSTALL
:: ============================================================
echo [7/7] Copying shared files and running post-install...
echo.

set "SHARED_UNC=\\host.lan\Data"
if exist "%SHARED_UNC%\" (
    if not exist "C:\Projects" mkdir C:\Projects
    xcopy "%SHARED_UNC%\*" "C:\Projects\" /E /I /Y /H
    echo Files copied from %SHARED_UNC% to C:\Projects.
) else (
    echo No shared folder found at %SHARED_UNC%. Skipping file copy.
)
echo.

if exist "C:\OEM\post-install.bat" (
    call C:\OEM\post-install.bat
) else (
    echo No post-install.bat found. Skipping.
)
echo.

:: ============================================================
:: CLEANUP
:: ============================================================
echo Cleaning up temporary files...
del /F /Q "C:\OEM\post-install.bat" 2>nul
del /F /Q "C:\OEM\MAS_AIO.cmd" 2>nul
del /F /Q "C:\OEM\odt.exe" 2>nul
del /F /Q "C:\OEM\git-installer.exe" 2>nul
del /F /Q "C:\OEM\git-credentials.txt" 2>nul
del /F /Q "C:\OEM\php-config.ini" 2>nul
del /F /Q "C:\OEM\php.zip" 2>nul
rmdir /S /Q "C:\OEM\ODT" 2>nul
rmdir /S /Q "C:\OEM\php-extract" 2>nul
rmdir /S /Q "C:\OEM\scripts" 2>nul
echo.

> "%DONE_MARKER%" echo Completed: %DATE% %TIME%

echo ============================================
echo  Setup Complete!
echo ============================================
echo Log: %LOG%
echo.

exit /b 0
