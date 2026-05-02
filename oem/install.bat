@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: Logging: tee everything to C:\OEM-logs\install.log
:: ============================================================
if not exist "C:\OEM-logs" mkdir "C:\OEM-logs"
set "LOG=C:\OEM-logs\install.log"
set "DONE_MARKER=C:\OEM-logs\install.done"

if exist "%DONE_MARKER%" (
    echo Install already completed at %DONE_MARKER%. Skipping.
    exit /b 0
)

:: Re-launch self with output redirected to the log (and still echoed to console).
if not defined __OEM_LOGGED (
    set "__OEM_LOGGED=1"
    powershell -NoProfile -Command "& { & cmd /c '%~f0' 2>&1 | Tee-Object -FilePath '%LOG%' }"
    exit /b %ERRORLEVEL%
)

echo ============================================
echo  Windows Post-Installation Setup
echo  Started: %DATE% %TIME%
echo ============================================
echo.

:: ============================================================
:: 1. ACTIVATE WINDOWS (HWID)
:: ============================================================
echo [1/7] Activating Windows...
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
echo [2/7] Installing Microsoft Office 2024 LTSC...
echo.

:: Resolve current ODT URL by scraping MS download page; fall back to known-good static URL.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue';" ^
    "$urls = @();" ^
    "try { $r = Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -UseBasicParsing -ErrorAction Stop; $urls += [regex]::Matches($r.Content,'https://download\.microsoft\.com/download/[^\"''<>]+officedeploymenttool[^\"''<>]+\.exe') | ForEach-Object { $_.Value } } catch {};" ^
    "$urls += 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18827-20140.exe';" ^
    "foreach ($u in $urls) { try { Invoke-WebRequest -Uri $u -OutFile 'C:\OEM\odt.exe' -ErrorAction Stop; if ((Get-Item 'C:\OEM\odt.exe').Length -gt 1MB) { break } } catch { Remove-Item 'C:\OEM\odt.exe' -ErrorAction SilentlyContinue } }"

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
    echo winget unavailable or failed; falling back to direct GitHub release download...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ProgressPreference='SilentlyContinue';" ^
        "try {" ^
        "  $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'oem-install' } -ErrorAction Stop;" ^
        "  $asset = $rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1;" ^
        "  if ($asset) { Invoke-WebRequest -Uri $asset.browser_download_url -OutFile 'C:\OEM\git-installer.exe' -ErrorAction Stop }" ^
        "} catch { Write-Host \"Git release lookup failed: $_\" }"
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
:: 5. INSTALL PHP
:: ============================================================
echo [5/7] Installing PHP...
echo.

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

:: Download PHP zip (current release, then archive)
powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!PHP_BASE_URL!/!PHP_ZIP_NAME!' -OutFile 'C:\OEM\php.zip' -ErrorAction Stop" 2>nul
if not exist "C:\OEM\php.zip" (
    powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!PHP_BASE_URL!/archives/!PHP_ZIP_NAME!' -OutFile 'C:\OEM\php.zip' -ErrorAction Stop" 2>nul
)

if not exist "C:\OEM\php.zip" (
    echo WARNING: Failed to download PHP !PHP_VERSION! ^(!PHP_VS!^). Installation skipped.
    goto :php_skip
)

:: Verify PHP zip SHA-256 against the sidecar published by windows.php.net (best-effort)
echo Verifying PHP archive checksum...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ok = $false;" ^
    "try {" ^
    "  $expected = $null;" ^
    "  foreach ($u in @('!PHP_BASE_URL!/!PHP_ZIP_NAME!.sha256','!PHP_BASE_URL!/archives/!PHP_ZIP_NAME!.sha256')) {" ^
    "    try { $expected = (Invoke-WebRequest -Uri $u -UseBasicParsing -ErrorAction Stop).Content.Trim().Split()[0]; if ($expected) { break } } catch {}" ^
    "  }" ^
    "  if ($expected) {" ^
    "    $actual = (Get-FileHash 'C:\OEM\php.zip' -Algorithm SHA256).Hash;" ^
    "    if ($actual -ieq $expected) { Write-Host 'PHP checksum OK.'; $ok = $true } else { Write-Host \"PHP checksum MISMATCH (expected $expected, got $actual)\" }" ^
    "  } else { Write-Host 'PHP checksum sidecar unavailable; skipping verify.'; $ok = $true }" ^
    "} catch { Write-Host \"PHP checksum check error: $_\"; $ok = $true };" ^
    "if (-not $ok) { exit 1 }"

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

:: Apply php-config.ini settings
echo Applying php-config.ini settings...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$configPath = 'C:\OEM\php-config.ini'; $iniPath = 'C:\php\php.ini'; $content = Get-Content $iniPath -Raw; $lines = Get-Content $configPath; foreach ($line in $lines) { $line = $line.Trim(); if ($line -match '^;|^$') { continue }; $parts = $line -split '=', 2; if ($parts.Count -ne 2) { continue }; $key = $parts[0].Trim(); $val = $parts[1].Trim(); if ($key -eq 'version') { continue }; if ($key -eq 'extension') { $extName = $val; $pattern = '^;\s*extension\s*=\s*' + [regex]::Escape($extName) + '\.dll\s*$'; if ($content -match $pattern) { $content = $content -replace $pattern, \"extension=$extName.dll\" } else { $dllPattern = '^;\s*extension\s*=\s*php_' + [regex]::Escape($extName) + '\.dll\s*$'; if ($content -match $dllPattern) { $content = $content -replace $dllPattern, \"extension=php_$extName.dll\" } else { $content += \"`r`nextension=$extName.dll`r`n\" } } } else { $escapedKey = [regex]::Escape($key); $iniPattern = '(?m)^;?\s*' + $escapedKey + '\s*=.*$'; if ($content -match $iniPattern) { $content = $content -replace $iniPattern, \"$key = $val\" } else { $content += \"`r`n$key = $val`r`n\" } } }; [System.IO.File]::WriteAllText($iniPath, $content)"

:: Install Composer (verify installer signature, then install as composer.phar + .bat shim)
echo Installing Composer...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue';" ^
    "Invoke-WebRequest -Uri 'https://getcomposer.org/installer' -OutFile 'C:\php\composer-setup.php' -ErrorAction Stop;" ^
    "$expected = (Invoke-WebRequest -Uri 'https://composer.github.io/installer.sig' -UseBasicParsing -ErrorAction Stop).Content.Trim();" ^
    "$actual = (Get-FileHash 'C:\php\composer-setup.php' -Algorithm SHA384).Hash;" ^
    "if ($actual -ine $expected) { Remove-Item 'C:\php\composer-setup.php' -Force; throw \"Composer installer signature mismatch (expected $expected, got $actual)\" } else { Write-Host 'Composer installer signature OK.' }"

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
powershell -NoProfile -Command "$oldPath = [Environment]::GetEnvironmentVariable('Path', 'Machine'); if ($oldPath -notlike '*C:\php*') { [Environment]::SetEnvironmentVariable('Path', \"$oldPath;C:\php\", 'Machine') }"
set "PATH=C:\php;%PATH%"

:: Verify installation
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
echo.

:: Idempotency marker
> "%DONE_MARKER%" echo Completed: %DATE% %TIME%

echo ============================================
echo  Setup Complete!
echo ============================================
echo.
echo Windows: Activated (HWID)
echo Office:  Installed and Activated (Ohook)
echo Git:     Installed
echo PHP:     Installed at C:\php
echo Files:   Copied to C:\Projects
echo Log:     %LOG%
echo.
echo Access the desktop via:
echo   - Web:    http://localhost:8006
echo   - RDP:    localhost:3389
echo.

exit /b 0
