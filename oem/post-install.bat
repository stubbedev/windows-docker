@echo off
setlocal EnableDelayedExpansion

echo ============================================
echo  Post-Install Commands
echo ============================================
echo.

:: PHP and Composer are already in PATH at this point.
:: `composer` works as a command thanks to C:\php\composer.bat.
:: Each command runs sequentially. Failures do not abort the script.

:: --- Example: Clone a repo ---
:: echo Cloning project repository...
:: cd /d C:\Projects
:: git clone https://github.com/your-org/your-repo.git
:: cd /d C:\Projects\your-repo

:: --- Example: Install Composer dependencies ---
:: echo Installing Composer dependencies...
:: cd /d C:\Projects\your-repo
:: call composer install --no-interaction --no-dev

:: --- Example: Start a Laravel worker ---
:: echo Starting Laravel worker...
:: cd /d C:\Projects\your-repo
:: start /B php artisan queue:work --tries=3

echo No post-install commands defined.
echo Edit C:\OEM\post-install.bat to add your commands.
echo.

exit /b 0
