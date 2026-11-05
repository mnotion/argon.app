@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================
echo Argon - build, deploy, and launch
echo ========================================
echo The normal installed app is rebuilt from the latest source first.
echo CMake builds incrementally, so unchanged C++ files are reused.
echo QML resources are refreshed and the updated app is deployed.
echo.

rem Never let source-QML development overrides leak into the installed app.
set "ARGON_DEV_QML_DIR="
set "QML_IMPORT_PATH="
set "QML2_IMPORT_PATH="
set "ARGON_DATA_ROOT="

echo === Building and deploying the latest Argon source ===
call "%~dp0build.bat" /nopause
if errorlevel 1 goto :build_failed

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "SIM_ROOT=%LOCALAPPDATA%\Argon-sim"
if not defined LOCALAPPDATA set "SIM_ROOT=%USERPROFILE%\AppData\Local\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"

if not exist "%SIM_APP_DIR%\Argon.exe" (
    echo [ERROR] Build completed but the deployed Argon executable was not found:
    echo "%SIM_APP_DIR%\Argon.exe"
    goto :launch_failed
)

rem The deployment normally carries its Qt runtime beside Argon.exe. Keep the
rem toolchain paths available as a fallback for the local development install.
if exist "%MINGW_ROOT%\bin" set "PATH=%MINGW_ROOT%\bin;%PATH%"
if exist "%QT_ROOT%\bin" set "PATH=%QT_ROOT%\bin;%PATH%"
set "QT_QUICK_CONTROLS_STYLE=Basic"

if not exist "%SIM_ROOT%\Logs" mkdir "%SIM_ROOT%\Logs"
if exist "%SIM_ROOT%\Logs\argon-runtime.log" del /f /q "%SIM_ROOT%\Logs\argon-runtime.log"

echo.
echo === Launching newly built Argon ===
echo Executable: "%SIM_APP_DIR%\Argon.exe"
echo Data root:  "%SIM_ROOT%"
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

:build_failed
echo.
echo [ERROR] The build or deployment failed. Argon was not launched.
echo Review the build diagnostics above.
pause
exit /b 1

:launch_failed
echo.
echo [ERROR] The new app could not be launched because deployment is incomplete.
pause
exit /b 1
