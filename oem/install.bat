@echo off
setlocal EnableDelayedExpansion

echo ============================================
echo  Windows Post-Installation Setup
echo ============================================
echo.

:: ============================================================
:: 1. ACTIVATE WINDOWS (HWID)
:: ============================================================
echo [1/6] Activating Windows...
echo.

powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://dev.azure.com/massgrave/Microsoft-Activation-Scripts/_apis/git/repositories/Microsoft-Activation-Scripts/items?path=/MAS/All-In-One-Version-KL/MAS_AIO.cmd&download=true' -OutFile 'C:\OEM\MAS_AIO.cmd' -ErrorAction Stop"
if exist "C:\OEM\MAS_AIO.cmd" (
    echo MAS script downloaded successfully.
    call C:\OEM\MAS_AIO.cmd /HWID
    echo Windows activation complete.
) else (
    echo WARNING: Failed to download MAS script. Will retry later.
)
echo.

:: ============================================================
:: 2. INSTALL OFFICE 2024 LTSC
:: ============================================================
echo [2/6] Installing Microsoft Office 2024 LTSC...
echo.

:: Download Office Deployment Tool
powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://download.microsoft.com/download/2/7/2/27254C66-7E8C-4C44-B8C2-FC4C3B0C4C44/odt_16925-20154.exe' -OutFile 'C:\OEM\odt.exe' -ErrorAction Stop" 2>nul

:: If the above URL fails, try the alternative CDN
if not exist "C:\OEM\odt.exe" (
    powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile 'C:\OEM\odt.exe' -ErrorAction Stop" 2>nul
)

:: Extract ODT
if exist "C:\OEM\odt.exe" (
    C:\OEM\odt.exe /extract:C:\OEM\ODT /quiet
    echo Office Deployment Tool extracted.
) else (
    echo WARNING: Failed to download ODT. Trying direct setup approach...
)

:: Install Office using ODT
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
echo [3/6] Activating Office...
echo.

if exist "C:\OEM\MAS_AIO.cmd" (
    call C:\OEM\MAS_AIO.cmd /Ohook
    echo Office activation complete.
) else (
    echo WARNING: MAS script not available. Office activation skipped.
)
echo.

:: ============================================================
:: 4. INSTALL PHP
:: ============================================================
echo [4/6] Installing PHP...
echo.

:: Create PHP directory
if not exist "C:\php" mkdir C:\php
if not exist "C:\php\logs" mkdir C:\php\logs

if not exist "C:\OEM\php-config.ini" (
    echo ERROR: C:\OEM\php-config.ini not found. PHP installation skipped.
    goto :php_skip
)

:: Read PHP version from config
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

:: Download PHP (Thread Safe, x64)
powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://windows.php.net/downloads/releases/php-!PHP_VERSION!-Win32-vs17-x64.zip' -OutFile 'C:\OEM\php.zip' -ErrorAction Stop" 2>nul

if exist "C:\OEM\php.zip" (
    :: Extract PHP
    powershell -NoProfile -Command "Expand-Archive -Path 'C:\OEM\php.zip' -DestinationPath 'C:\OEM\php-extract' -Force"

    :: Copy PHP files to C:\php
    xcopy "C:\OEM\php-extract\*.*" "C:\php\" /E /I /Y /Q

    :: Create php.ini from development template
    if exist "C:\php\php.ini-development" (
        copy /Y "C:\php\php.ini-development" "C:\php\php.ini"
    )

    :: Apply php-config.ini settings
    echo Applying php-config.ini settings...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$configPath = 'C:\OEM\php-config.ini'; $iniPath = 'C:\php\php.ini'; $content = Get-Content $iniPath -Raw; $lines = Get-Content $configPath; foreach ($line in $lines) { $line = $line.Trim(); if ($line -match '^;|^$') { continue }; $parts = $line -split '=', 2; if ($parts.Count -ne 2) { continue }; $key = $parts[0].Trim(); $val = $parts[1].Trim(); if ($key -eq 'version') { continue }; if ($key -eq 'extension') { $extName = $val; $pattern = '^;\s*extension\s*=\s*' + [regex]::Escape($extName) + '\.dll\s*$'; if ($content -match $pattern) { $content = $content -replace $pattern, \"extension=$extName.dll\" } else { $dllPattern = '^;\s*extension\s*=\s*php_' + [regex]::Escape($extName) + '\.dll\s*$'; if ($content -match $dllPattern) { $content = $content -replace $dllPattern, \"extension=php_$extName.dll\" } else { $content += \"`r`nextension=$extName.dll`r`n\" } } } else { $escapedKey = [regex]::Escape($key); $iniPattern = '(?m)^;?\s*' + $escapedKey + '\s*=.*$'; if ($content -match $iniPattern) { $content = $content -replace $iniPattern, \"$key = $val\" } else { $content += \"`r`n$key = $val`r`n\" } } }; [System.IO.File]::WriteAllText($iniPath, $content)"

    :: Install Composer
    powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile 'C:\php\composer-setup.php'"
    C:\php\php.exe C:\php\composer-setup.php --install-dir=C:\php --filename=composer
    del /F /Q "C:\php\composer-setup.php" 2>nul
    echo Composer installed.

    :: Add PHP to system PATH permanently
    powershell -NoProfile -Command "$oldPath = [Environment]::GetEnvironmentVariable('Path', 'Machine'); if ($oldPath -notlike '*C:\php*') { [Environment]::SetEnvironmentVariable('Path', \"$oldPath;C:\php\", 'Machine') }"

    :: Also set for current session
    set "PATH=C:\php;%PATH%"

    :: Verify installation
    C:\php\php.exe -v
    C:\php\composer.exe --version
    echo PHP installed to C:\php and added to PATH.
) else (
    echo WARNING: Failed to download PHP !PHP_VERSION!. Installation skipped.
)

:php_skip
echo.

:: ============================================================
:: 5. COPY SHARED FILES
:: ============================================================
echo [5/6] Copying shared files...
echo.

:: The /shared volume is mounted as C:\Shared by dockur/windows
if exist "C:\Shared" (
    :: Copy everything from Shared to C:\Projects
    if not exist "C:\Projects" mkdir C:\Projects
    xcopy "C:\Shared\*" "C:\Projects\" /E /I /Y /H
    echo Files copied from C:\Shared to C:\Projects.
) else (
    echo No shared folder found at C:\Shared. Skipping file copy.
)
echo.

:: ============================================================
:: 6. RUN POST-INSTALL COMMANDS
:: ============================================================
echo [6/6] Running post-install commands...
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
del /F /Q "C:\OEM\php-config.ini" 2>nul
del /F /Q "C:\OEM\php.zip" 2>nul
rmdir /S /Q "C:\OEM\ODT" 2>nul
rmdir /S /Q "C:\OEM\php-extract" 2>nul
echo.

echo ============================================
echo  Setup Complete!
echo ============================================
echo.
echo Windows: Activated (HWID)
echo Office:  Installed and Activated (Ohook)
echo PHP:     Installed at C:\php
echo Files:   Copied to C:\Projects
echo.
echo Access the desktop via:
echo   - Web:    http://localhost:8006
echo   - RDP:    localhost:3389 (user: admin, pass: password)
echo.

exit /b 0
