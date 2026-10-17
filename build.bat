@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Keep the window open when launched directly.
rem run.bat passes /nopause because it launches the app after deployment.
set "KEEP_WINDOW_OPEN=1"
if /I "%~1"=="/nopause" set "KEEP_WINDOW_OPEN=0"

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "BUILD_DIR=%~dp0build"
rem Resolve the actual Windows Desktop folder (including OneDrive redirection).
set "DESKTOP_DIR="
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2^>nul`) do set "DESKTOP_DIR=%%D"
if not defined DESKTOP_DIR set "DESKTOP_DIR=%USERPROFILE%\Desktop"
set "SIM_ROOT=%DESKTOP_DIR%\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"
set "SIM_STAGE_ROOT=%SIM_ROOT%\.build-stage"
set "SIM_STAGE_APP_DIR=%SIM_STAGE_ROOT%\App"
set "PREVIOUS_APP_DIR=%SIM_ROOT%\.previous-App"
set "SOURCE_SEARCH=%~dp0Argon\UserData\Search QR"
set "TARGET_SEARCH=%SIM_ROOT%\UserData\Search QR"

echo ========================================
echo Argon build and desktop deployment
echo ========================================
echo Build intermediates: %BUILD_DIR%
echo Runnable test folder: %SIM_ROOT%
echo.

if not exist "%QT_ROOT%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo [ERROR] Qt 6 CMake package was not found under "%QT_ROOT%".
    goto :build_failed
)
if not exist "%QT_ROOT%\bin\windeployqt.exe" (
    echo [ERROR] windeployqt.exe was not found under "%QT_ROOT%\bin".
    goto :build_failed
)
if not exist "%MINGW_ROOT%\bin\g++.exe" (
    echo [ERROR] MinGW compiler was not found at "%MINGW_ROOT%\bin\g++.exe".
    goto :build_failed
)
if not exist "%MINGW_ROOT%\bin\mingw32-make.exe" (
    echo [ERROR] MinGW Make was not found at "%MINGW_ROOT%\bin\mingw32-make.exe".
    goto :build_failed
)

set "PATH=%MINGW_ROOT%\bin;%QT_ROOT%\bin;%PATH%"

echo.
echo === Preparing Argon-sim data folders ===
if not exist "%SIM_ROOT%" mkdir "%SIM_ROOT%"
if errorlevel 1 goto :build_failed
if not exist "%SIM_ROOT%\Updater" mkdir "%SIM_ROOT%\Updater"
if not exist "%SIM_ROOT%\Bootstrap" mkdir "%SIM_ROOT%\Bootstrap"
if not exist "%SIM_ROOT%\UserData\Settings" mkdir "%SIM_ROOT%\UserData\Settings"
if not exist "%SIM_ROOT%\UserData\Cache" mkdir "%SIM_ROOT%\UserData\Cache"
if not exist "%SIM_ROOT%\UserData\Search QR" mkdir "%SIM_ROOT%\UserData\Search QR"
if not exist "%SIM_ROOT%\UserData\Documents" mkdir "%SIM_ROOT%\UserData\Documents"
if not exist "%SIM_ROOT%\UserData\Accounts" mkdir "%SIM_ROOT%\UserData\Accounts"
if not exist "%SIM_ROOT%\UserData\Analytics\Daily" mkdir "%SIM_ROOT%\UserData\Analytics\Daily"
if not exist "%SIM_ROOT%\Updates\Downloads" mkdir "%SIM_ROOT%\Updates\Downloads"
if not exist "%SIM_ROOT%\Updates\Staging" mkdir "%SIM_ROOT%\Updates\Staging"
if not exist "%SIM_ROOT%\Updates\Backups" mkdir "%SIM_ROOT%\Updates\Backups"
if not exist "%SIM_ROOT%\Logs" mkdir "%SIM_ROOT%\Logs"

rem Clean only the temporary build payload. Never delete UserData, Updates, or Logs.
if exist "%SIM_STAGE_ROOT%" rmdir /s /q "%SIM_STAGE_ROOT%"
if exist "%SIM_STAGE_ROOT%" (
    echo [ERROR] Could not clear temporary staging folder: "%SIM_STAGE_ROOT%"
    goto :build_failed
)
mkdir "%SIM_STAGE_APP_DIR%"
if errorlevel 1 goto :build_failed

echo.
echo === Configuring Argon ===
cmake -S "%~dp0." -B "%BUILD_DIR%" -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="%QT_ROOT%" -DCMAKE_CXX_COMPILER="%MINGW_ROOT%\bin\g++.exe" -DCMAKE_MAKE_PROGRAM="%MINGW_ROOT%\bin\mingw32-make.exe" -DARGON_RUNTIME_OUTPUT_DIR="%SIM_STAGE_APP_DIR%"
if errorlevel 1 (
    echo.
    echo [ERROR] CMake configuration failed. See output above.
    goto :build_failed
)

echo.
echo === Compiling Argon into desktop staging ===
cmake --build "%BUILD_DIR%" --parallel
if errorlevel 1 (
    echo.
    echo [ERROR] Compilation failed. See output above.
    goto :build_failed
)
if not exist "%SIM_STAGE_APP_DIR%\Argon.exe" (
    echo [ERROR] Build finished but staged Argon.exe was not created.
    echo Check the CMake runtime output configuration.
    goto :build_failed
)

echo.
echo === Deploying Qt DLLs, plugins, and QML modules ===
"%QT_ROOT%\bin\windeployqt.exe" --qmldir "%~dp0qml" --compiler-runtime "%SIM_STAGE_APP_DIR%\Argon.exe"
if errorlevel 1 (
    echo [ERROR] Qt dependency deployment failed. See output above.
    goto :build_failed
)

echo.
echo === Preparing representative Search QR test data ===
if exist "%SOURCE_SEARCH%\README.md" if not exist "%TARGET_SEARCH%\README.md" copy "%SOURCE_SEARCH%\README.md" "%TARGET_SEARCH%\README.md" >nul
if exist "%SOURCE_SEARCH%\LDA1.pdf" if not exist "%TARGET_SEARCH%\LDA1.pdf" copy "%SOURCE_SEARCH%\LDA1.pdf" "%TARGET_SEARCH%\LDA1.pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (2).pdf" if not exist "%TARGET_SEARCH%\LDA1 (2).pdf" copy "%SOURCE_SEARCH%\LDA1 (2).pdf" "%TARGET_SEARCH%\LDA1 (2).pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (3).pdf" if not exist "%TARGET_SEARCH%\LDA1 (3).pdf" copy "%SOURCE_SEARCH%\LDA1 (3).pdf" "%TARGET_SEARCH%\LDA1 (3).pdf" >nul

echo.
echo === Activating new desktop app bundle ===
rem Keep the previous bundle until the fully-deployed staging bundle is ready.
if exist "%PREVIOUS_APP_DIR%" rmdir /s /q "%PREVIOUS_APP_DIR%"
if exist "%PREVIOUS_APP_DIR%" (
    echo [ERROR] Could not clear previous app backup.
    echo Close any old Argon-sim instance and rebuild.
    goto :build_failed
)

if exist "%SIM_APP_DIR%" (
    move "%SIM_APP_DIR%" "%PREVIOUS_APP_DIR%" >nul
    if errorlevel 1 (
        echo [ERROR] Could not move the existing App folder to backup.
        echo Close any running Argon-sim instance and retry.
        goto :build_failed
    )
)

move "%SIM_STAGE_APP_DIR%" "%SIM_APP_DIR%" >nul
if errorlevel 1 (
    echo [ERROR] Could not activate the new Argon-sim app folder.
    if exist "%PREVIOUS_APP_DIR%" if not exist "%SIM_APP_DIR%" move "%PREVIOUS_APP_DIR%" "%SIM_APP_DIR%" >nul
    goto :build_failed
)

rem Clear runtime payload copies deployed into build/ by earlier versions of this script.
rem CMake intermediates remain there; the runnable app and Qt payload live under Argon-sim.
if exist "%BUILD_DIR%\Argon.exe" del /f /q "%BUILD_DIR%\Argon.exe"
for %%F in ("%BUILD_DIR%\*.dll") do if exist "%%~fF" del /f /q "%%~fF"
for %%D in (plugins qml translations platforms imageformats iconengines styles tls networkinformation generic printsupport) do if exist "%BUILD_DIR%\%%~D" rmdir /s /q "%BUILD_DIR%\%%~D"

rem Remove old app payload only after the new bundle has been activated.
if exist "%PREVIOUS_APP_DIR%" (
    rmdir /s /q "%PREVIOUS_APP_DIR%"
    if exist "%PREVIOUS_APP_DIR%" echo [WARNING] Previous payload could not be cleaned; it remains at "%PREVIOUS_APP_DIR%".
)
if exist "%SIM_STAGE_ROOT%" rmdir /s /q "%SIM_STAGE_ROOT%"

echo.
echo ========================================
echo BUILD AND DEPLOYMENT SUCCEEDED
echo Runnable app: "%SIM_APP_DIR%\Argon.exe"
echo Test data:    "%TARGET_SEARCH%"
echo User data:    "%SIM_ROOT%\UserData"
echo Logs:         "%SIM_ROOT%\Logs"
echo CMake intermediates only: "%BUILD_DIR%"
echo ========================================
if "%KEEP_WINDOW_OPEN%"=="1" (
    echo.
    pause
)
exit /b 0

:build_failed
set "BUILD_EXIT_CODE=1"
if "%KEEP_WINDOW_OPEN%"=="1" (
    echo.
    echo Build/deployment failed. Read the diagnostic output above.
    pause
)
exit /b %BUILD_EXIT_CODE%
