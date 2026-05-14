@echo off
:: ============================================================
:: phase-php.bat
:: Re-runs when shared\.runtime\php-config.ini hash changes.
::
:: Strategy:
::   1. Run post-install-stop.bat (if present) to release locks on C:\php.
::   2. Build a complete PHP+Composer install in C:\php.new.
::   3. Verify with `php -v`.
::   4. Atomic swap: C:\php -> C:\php.old, C:\php.new -> C:\php.
::   5. On failure: roll back C:\php.old -> C:\php.
:: ============================================================

setlocal EnableDelayedExpansion

set "OEM_RUNTIME=C:\OEM-runtime"
set "SCRIPTS=%OEM_RUNTIME%\scripts"
set "PHP_CONFIG=%OEM_RUNTIME%\php-config.ini"
set "STAGING=C:\php.new"
set "OLD=C:\php.old"
set "FINAL=C:\php"

echo ----------------------------------------
echo Phase PHP: starting %DATE% %TIME%
echo ----------------------------------------

if not exist "%PHP_CONFIG%" (
    echo ERROR: %PHP_CONFIG% missing.
    exit /b 1
)

:: Let the user stop their workers before we touch C:\php.
if exist "%OEM_RUNTIME%\post-install-stop.bat" (
    echo Calling post-install-stop.bat to release locks on C:\php...
    call "%OEM_RUNTIME%\post-install-stop.bat"
)

:: --- Read version from php-config.ini --------------------------
set "PHP_VERSION="
for /f "usebackq tokens=1,* delims==" %%A in ("%PHP_CONFIG%") do (
    set "line_key=%%A"
    set "line_val=%%B"
    set "line_key=!line_key: =!"
    set "line_val=!line_val: =!"
    if /i "!line_key!"=="version" set "PHP_VERSION=!line_val!"
)

if not defined PHP_VERSION (
    echo ERROR: No version specified in php-config.ini.
    exit /b 1
)

echo PHP version: !PHP_VERSION!

:: --- Determine VS toolset --------------------------------------
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

:: --- Prepare staging dir ---------------------------------------
:: If a previous run left C:\php.new behind, preserve it as
:: C:\php.failed for inspection rather than silently wiping.
if exist "%STAGING%" (
    if exist "C:\php.failed" rmdir /S /Q "C:\php.failed"
    ren "%STAGING%" "php.failed"
)
mkdir "%STAGING%"
mkdir "%STAGING%\logs"

set "PHP_ZIP_PATH=%STAGING%\php.zip"

:: --- Download (current, then archives) -------------------------
echo Downloading PHP archive...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\retry-download.ps1" -Url "%PHP_BASE_URL%/%PHP_ZIP_NAME%" -OutFile "%PHP_ZIP_PATH%"
if !ERRORLEVEL! NEQ 0 (
    echo Trying archives URL...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\retry-download.ps1" -Url "%PHP_BASE_URL%/archives/%PHP_ZIP_NAME%" -OutFile "%PHP_ZIP_PATH%"
)

if not exist "%PHP_ZIP_PATH%" (
    echo ERROR: Failed to download PHP !PHP_VERSION! [!PHP_VS!].
    rmdir /S /Q "%STAGING%" 2>nul
    exit /b 1
)

:: --- Verify SHA-256 --------------------------------------------
echo Verifying checksum...
set "PHP_ZIP_PATH=%PHP_ZIP_PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\verify-php.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: PHP checksum mismatch.
    rmdir /S /Q "%STAGING%" 2>nul
    exit /b 1
)

:: --- Extract ----------------------------------------------------
echo Extracting PHP into staging...
powershell -NoProfile -Command "Expand-Archive -Path '%PHP_ZIP_PATH%' -DestinationPath '%STAGING%\extract' -Force"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Expand-Archive failed.
    rmdir /S /Q "%STAGING%" 2>nul
    exit /b 1
)
xcopy "%STAGING%\extract\*.*" "%STAGING%\" /E /I /Y /Q >nul
rmdir /S /Q "%STAGING%\extract"
del /F /Q "%PHP_ZIP_PATH%"

:: --- php.ini from production template --------------------------
if exist "%STAGING%\php.ini-production" (
    copy /Y "%STAGING%\php.ini-production" "%STAGING%\php.ini" >nul
) else if exist "%STAGING%\php.ini-development" (
    copy /Y "%STAGING%\php.ini-development" "%STAGING%\php.ini" >nul
)

:: openssl + curl are always on (required for Composer/HTTPS).
powershell -NoProfile -Command "(Get-Content '%STAGING%\php.ini') -replace '^;extension=openssl$','extension=openssl' -replace '^;extension=curl$','extension=curl' | Set-Content '%STAGING%\php.ini'"

:: --- Apply php-config.ini directives ---------------------------
echo Applying php-config.ini directives...
set "PHP_CONFIG_PATH=%PHP_CONFIG%"
set "PHP_INI_PATH=%STAGING%\php.ini"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\apply-ini.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: apply-ini.ps1 failed.
    echo Leaving %STAGING% in place for inspection.
    exit /b 1
)

:: --- Smoke-test PHP BEFORE composer --------------------------
echo Smoke-testing PHP in staging...
"%STAGING%\php.exe" -v
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: php.exe -v failed in staging.
    echo Leaving %STAGING% in place for inspection.
    exit /b 1
)
echo Loaded extensions:
"%STAGING%\php.exe" -m
echo.

:: --- Composer in staging ---------------------------------------
echo Installing Composer into staging...
set "COMPOSER_TARGET=%STAGING%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\install-composer.ps1"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Composer installer verification failed.
    echo Leaving %STAGING% in place for inspection.
    exit /b 1
)
"%STAGING%\php.exe" -d display_errors=1 -d display_startup_errors=1 "%STAGING%\composer-setup.php" --install-dir="%STAGING%" --filename=composer.phar
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Composer setup failed.
    echo Leaving %STAGING% in place for inspection.
    echo Re-running with verbose for log capture:
    "%STAGING%\php.exe" -d display_errors=1 -d display_startup_errors=1 "%STAGING%\composer-setup.php" --install-dir="%STAGING%" --filename=composer.phar --verbose
    exit /b 1
)
del /F /Q "%STAGING%\composer-setup.php" 2>nul

> "%STAGING%\composer.bat" echo @echo off
>>"%STAGING%\composer.bat" echo "%%~dp0php.exe" "%%~dp0composer.phar" %%*

:: --- Atomic swap -----------------------------------------------
echo Promoting %STAGING% -> %FINAL%...

if exist "%OLD%" rmdir /S /Q "%OLD%"

if exist "%FINAL%" (
    ren "%FINAL%" "php.old"
    if !ERRORLEVEL! NEQ 0 (
        echo Could not rename %FINAL% to %OLD%; trying to kill php processes first...
        taskkill /F /IM php-cgi.exe /T 2>nul
        taskkill /F /IM php.exe /T 2>nul
        timeout /t 2 /nobreak >nul
        ren "%FINAL%" "php.old"
        if !ERRORLEVEL! NEQ 0 (
            echo ERROR: Could not move %FINAL% out of the way. Aborting and keeping current install.
            rmdir /S /Q "%STAGING%" 2>nul
            exit /b 1
        )
    )
)

ren "%STAGING%" "php"
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Failed to promote %STAGING% to %FINAL%. Restoring backup...
    if exist "%OLD%" ren "%OLD%" "php"
    exit /b 1
)

:: --- Verify final ----------------------------------------------
"%FINAL%\php.exe" -v
if !ERRORLEVEL! NEQ 0 (
    echo ERROR: Final php.exe smoke test failed. Rolling back...
    rmdir /S /Q "%FINAL%"
    if exist "%OLD%" ren "%OLD%" "php"
    exit /b 1
)

:: --- Ensure C:\php on machine PATH -----------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTS%\set-php-path.ps1"

:: --- Cleanup backup --------------------------------------------
if exist "%OLD%" rmdir /S /Q "%OLD%"

echo ----------------------------------------
echo Phase PHP: success %DATE% %TIME%
echo ----------------------------------------
exit /b 0
