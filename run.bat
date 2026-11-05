@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================
echo Argon - launch existing installation
echo ========================================
echo This launcher does not compile, configure, or deploy anything.
echo.

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "SIM_ROOT=%LOCALAPPDATA%\Argon-sim"
if not defined LOCALAPPDATA set "SIM_ROOT=%USERPROFILE%\AppData\Local\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"

rem Always use the canonical installed app, never a stale Desktop or build copy.
rem Clear inherited development overrides so Argon uses the same data as build.bat.
set "ARGON_DATA_ROOT="

if not exist "%SIM_APP_DIR%\Argon.exe" (
    echo [ERROR] The deployed Argon executable was not found:
    echo "%SIM_APP_DIR%\Argon.exe"
    echo.
    echo Run build.bat explicitly once to create the installation.
    echo After that, run.bat will launch it without compiling.
    echo.
    pause
    exit /b 1
)

rem The deployment normally carries its Qt runtime beside Argon.exe. Keep the
rem toolchain paths available as a fallback for the local development install.
if exist "%MINGW_ROOT%\bin" set "PATH=%MINGW_ROOT%\bin;%PATH%"
if exist "%QT_ROOT%\bin" set "PATH=%QT_ROOT%\bin;%PATH%"
set "QT_QUICK_CONTROLS_STYLE=Basic"

if not exist "%SIM_ROOT%\Logs" mkdir "%SIM_ROOT%\Logs"

echo Launching: "%SIM_APP_DIR%\Argon.exe"
echo Data root: "%SIM_ROOT%"
echo Press F12 inside Argon to open the developer interpreter console.
echo.

"%SIM_APP_DIR%\Argon.exe"
set "ARGON_EXIT_CODE=%errorlevel%"

if not "%ARGON_EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Argon exited with code %ARGON_EXIT_CODE%.
    echo.
    if exist "%SIM_ROOT%\Logs\argon-runtime.log" (
        echo === Runtime log ===
        type "%SIM_ROOT%\Logs\argon-runtime.log"
    ) else (
        echo No runtime log was created.
    )
    echo.
    pause
    exit /b %ARGON_EXIT_CODE%
)

echo.
echo Argon closed normally.
pause
exit /b 0
