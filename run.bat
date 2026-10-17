@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
rem Resolve the actual Windows Desktop folder (including OneDrive redirection).
set "DESKTOP_DIR="
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2^>nul`) do set "DESKTOP_DIR=%%D"
if not defined DESKTOP_DIR set "DESKTOP_DIR=%USERPROFILE%\Desktop"
set "SIM_ROOT=%DESKTOP_DIR%\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"
set "ARGON_DATA_ROOT=%SIM_ROOT%"

echo ========================================
echo Argon-sim runtime test
echo ========================================
echo Test installation: %SIM_ROOT%
echo.

rem Running must not compile or deploy dependencies. Use build.bat explicitly for that.
if not exist "%SIM_APP_DIR%\Argon.exe" (
    echo [ERROR] Deployed Argon.exe was not found at "%SIM_APP_DIR%\Argon.exe".
    echo Run build.bat first to compile Argon and deploy its Qt dependencies.
    echo.
    pause
    exit /b 1
)

set "PATH=%MINGW_ROOT%\bin;%QT_ROOT%\bin;%PATH%"
set "QT_QUICK_CONTROLS_STYLE=Basic"

if not exist "%SIM_ROOT%\Logs" mkdir "%SIM_ROOT%\Logs"
if exist "%SIM_ROOT%\Logs\argon-runtime.log" del "%SIM_ROOT%\Logs\argon-runtime.log"

echo.
echo === Launching deployed Argon.exe ===
echo Runtime data root: %ARGON_DATA_ROOT%
"%SIM_APP_DIR%\Argon.exe"
set "ARGON_EXIT_CODE=%errorlevel%"

if not "%ARGON_EXIT_CODE%"=="0" (
    echo.
    echo Argon exited with an error. Exit code: %ARGON_EXIT_CODE%
    echo.
    echo === Runtime error details ===
    if exist "%SIM_ROOT%\Logs\argon-runtime.log" (
        type "%SIM_ROOT%\Logs\argon-runtime.log"
    ) else (
        echo No runtime log was created. The process may have failed before Qt logging initialized.
    )
    echo.
    pause
    exit /b %ARGON_EXIT_CODE%
)

echo.
echo Argon exited normally.
echo Runtime log: "%SIM_ROOT%\Logs\argon-runtime.log"
pause
exit /b 0
