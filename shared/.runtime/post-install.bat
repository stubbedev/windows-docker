@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: post-install.bat
:: Runs at the end of phase-code, every time phase-code re-runs.
:: This script must be idempotent — it re-runs on every redeploy
:: where post-install.bat itself has changed.
::
:: PHP and Composer are already on PATH:
::   - php             (C:\php\php.exe)
::   - composer        (C:\php\composer.bat -> php composer.phar)
:: ============================================================

echo ============================================
echo  Post-Install Commands
echo ============================================
echo.

:: --- Example: Clone or update a repo (idempotent) ---
:: if not exist "C:\Projects\your-repo\.git" (
::     echo Cloning project repository...
::     cd /d C:\Projects
::     git clone https://github.com/your-org/your-repo.git
:: ) else (
::     echo Updating project repository...
::     git -C C:\Projects\your-repo pull --ff-only
:: )

:: --- Example: Install Composer dependencies ---
:: cd /d C:\Projects\your-repo
:: call composer install --no-interaction --no-dev

:: --- Example: Restart a Laravel queue worker ---
:: (Pair this with shared\.runtime\post-install-stop.bat so the
:: worker is killed before phase-php replaces C:\php.)
:: cd /d C:\Projects\your-repo
:: start /B php artisan queue:work --tries=3

echo No post-install commands defined.
echo Edit shared\.runtime\post-install.bat to add your commands.
echo.

exit /b 0
