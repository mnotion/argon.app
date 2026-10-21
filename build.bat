@echo off
color 0A
setlocal EnableExtensions
cd /d "%~dp0"

rem Keep the window open when launched directly.
rem /nopause lets run.bat build/deploy without pausing before it launches the app.
set "KEEP_WINDOW_OPEN=1"
if /I "%~1"=="/nopause" set "KEEP_WINDOW_OPEN=0"

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "BUILD_DIR=%~dp0build"
rem Keep the runnable test deployment out of OneDrive-synced Desktop folders.
rem Large Qt payload trees are prone to access-denied rename/move failures under sync.
set "SIM_ROOT=%LOCALAPPDATA%\Argon-sim"
if not defined LOCALAPPDATA set "SIM_ROOT=%USERPROFILE%\AppData\Local\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"
set "SIM_BOOTSTRAP_DIR=%SIM_ROOT%\Bootstrap"
set "SIM_STAGE_ROOT=%SIM_ROOT%\.build-stage"
set "SIM_STAGE_APP_DIR=%SIM_STAGE_ROOT%\App"
set "SIM_STAGE_BOOTSTRAP_DIR=%SIM_STAGE_ROOT%\Bootstrap"
set "PREVIOUS_APP_DIR=%SIM_ROOT%\.previous-App"
set "PREVIOUS_BOOTSTRAP_DIR=%SIM_ROOT%\.previous-Bootstrap"
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
mkdir "%SIM_STAGE_BOOTSTRAP_DIR%"
if errorlevel 1 goto :build_failed

echo.
echo === Configuring Argon, Updater, and Bootstrap ===
cmake -S "%~dp0." -B "%BUILD_DIR%" -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="%QT_ROOT%" -DCMAKE_CXX_COMPILER="%MINGW_ROOT%\bin\g++.exe" -DCMAKE_MAKE_PROGRAM="%MINGW_ROOT%\bin\mingw32-make.exe" -DARGON_RUNTIME_OUTPUT_DIR="%SIM_STAGE_APP_DIR%" -DARGON_BOOTSTRAP_OUTPUT_DIR="%SIM_STAGE_BOOTSTRAP_DIR%" -DARGON_UPDATER_OUTPUT_DIR="%SIM_ROOT%\Updater" -DARGON_UPDATER_VERSION="1.1.0.0" -DARGON_BOOTSTRAP_VERSION="1.0.0.0"
if errorlevel 1 (
    echo.
    echo [ERROR] CMake configuration failed. See output above.
    goto :build_failed
)

echo.
echo === Compiling Argon, Updater, and Bootstrap ===
cmake --build "%BUILD_DIR%" --parallel
if errorlevel 1 (
    echo [ERROR] Compilation failed. See output above.
    goto :build_failed
)
if not exist "%SIM_STAGE_APP_DIR%\Argon.exe" (
    echo [ERROR] Build finished but staged Argon.exe was not created.
    echo Check the CMake runtime output configuration.
    goto :build_failed
)
if not exist "%SIM_STAGE_BOOTSTRAP_DIR%\Bootstrap.exe" (
    echo [ERROR] Build finished but staged Bootstrap.exe was not created.
    echo Check the CMake bootstrap output configuration.
    goto :build_failed
)
if not exist "%SIM_ROOT%\Updater\ArgonUpdater.exe" (
    echo [ERROR] Build finished but ArgonUpdater.exe was not created in "%SIM_ROOT%\Updater".
    goto :build_failed
)

echo.
echo === Deploying Qt DLLs, plugins, and QML modules ===
"%QT_ROOT%\bin\windeployqt.exe" --qmldir "%~dp0qml" --compiler-runtime "%SIM_STAGE_APP_DIR%\Argon.exe"
if errorlevel 1 (
    echo [ERROR] Qt dependency deployment failed. See output above.
    goto :build_failed
)
rem Bootstrap is a native Win32 executable and does not require Qt deployment.

echo.
echo === Preparing representative Search QR test data ===
if exist "%SOURCE_SEARCH%\README.md" if not exist "%TARGET_SEARCH%\README.md" copy "%SOURCE_SEARCH%\README.md" "%TARGET_SEARCH%\README.md" >nul
if exist "%SOURCE_SEARCH%\LDA1.pdf" if not exist "%TARGET_SEARCH%\LDA1.pdf" copy "%SOURCE_SEARCH%\LDA1.pdf" "%TARGET_SEARCH%\LDA1.pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (2).pdf" if not exist "%TARGET_SEARCH%\LDA1 (2).pdf" copy "%SOURCE_SEARCH%\LDA1 (2).pdf" "%TARGET_SEARCH%\LDA1 (2).pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (3).pdf" if not exist "%TARGET_SEARCH%\LDA1 (3).pdf" copy "%SOURCE_SEARCH%\LDA1 (3).pdf" "%TARGET_SEARCH%\LDA1 (3).pdf" >nul

echo.
echo === Activating staged Argon and Bootstrap ===
rem Stop running instances before replacing their deployed folders. Windows can
rem deny directory activation while an executable or one of its DLLs is in use.
echo Closing running Argon and Bootstrap processes, if any...
taskkill /F /T /IM Argon.exe >nul 2>&1
taskkill /F /T /IM Bootstrap.exe >nul 2>&1
timeout /t 2 /nobreak >nul

rem Keep both previous payloads until the replacement app and bootstrap are active.
if exist "%PREVIOUS_APP_DIR%" rmdir /s /q "%PREVIOUS_APP_DIR%"
if exist "%PREVIOUS_BOOTSTRAP_DIR%" rmdir /s /q "%PREVIOUS_BOOTSTRAP_DIR%"
if exist "%PREVIOUS_APP_DIR%" (
    echo [ERROR] Could not clear previous app backup.
    goto :build_failed
)
if exist "%PREVIOUS_BOOTSTRAP_DIR%" (
    echo [ERROR] Could not clear previous bootstrap backup.
    goto :build_failed
)

if exist "%SIM_BOOTSTRAP_DIR%" (
    move "%SIM_BOOTSTRAP_DIR%" "%PREVIOUS_BOOTSTRAP_DIR%" >nul
    if errorlevel 1 (
        echo [ERROR] Could not move the existing Bootstrap folder to backup.
        echo Close any running Bootstrap instance and retry.
        goto :build_failed
    )
)
if exist "%SIM_APP_DIR%" (
    move "%SIM_APP_DIR%" "%PREVIOUS_APP_DIR%" >nul
    if errorlevel 1 (
        echo [ERROR] Could not move the existing App folder to backup.
        if exist "%PREVIOUS_BOOTSTRAP_DIR%" if not exist "%SIM_BOOTSTRAP_DIR%" move "%PREVIOUS_BOOTSTRAP_DIR%" "%SIM_BOOTSTRAP_DIR%" >nul
        goto :build_failed
    )
)

move "%SIM_STAGE_BOOTSTRAP_DIR%" "%SIM_BOOTSTRAP_DIR%" >nul
if errorlevel 1 (
    echo [ERROR] Could not activate the new Bootstrap folder.
    if exist "%PREVIOUS_APP_DIR%" if not exist "%SIM_APP_DIR%" move "%PREVIOUS_APP_DIR%" "%SIM_APP_DIR%" >nul
    if exist "%PREVIOUS_BOOTSTRAP_DIR%" if not exist "%SIM_BOOTSTRAP_DIR%" move "%PREVIOUS_BOOTSTRAP_DIR%" "%SIM_BOOTSTRAP_DIR%" >nul
    goto :build_failed
)

move "%SIM_STAGE_APP_DIR%" "%SIM_APP_DIR%" >nul
if errorlevel 1 (
    echo [ERROR] Could not activate the new Argon app folder.
    echo Source: "%SIM_STAGE_APP_DIR%"
    echo Target: "%SIM_APP_DIR%"
    echo Windows denied the folder move. Check file locks and folder permissions.
    if exist "%SIM_APP_DIR%" rmdir /s /q "%SIM_APP_DIR%"
    if exist "%PREVIOUS_APP_DIR%" if not exist "%SIM_APP_DIR%" move "%PREVIOUS_APP_DIR%" "%SIM_APP_DIR%" >nul
    if exist "%SIM_BOOTSTRAP_DIR%" rmdir /s /q "%SIM_BOOTSTRAP_DIR%"
    if exist "%PREVIOUS_BOOTSTRAP_DIR%" if not exist "%SIM_BOOTSTRAP_DIR%" move "%PREVIOUS_BOOTSTRAP_DIR%" "%SIM_BOOTSTRAP_DIR%" >nul
    goto :build_failed
)

rem Clear runtime payload copies deployed into build/ by earlier versions of this script.
rem CMake intermediates remain there; the runnable app and Qt payload live under Argon-sim.
if exist "%BUILD_DIR%\Argon.exe" del /f /q "%BUILD_DIR%\Argon.exe"
for %%F in ("%BUILD_DIR%\*.dll") do if exist "%%~fF" del /f /q "%%~fF"
for %%D in (plugins qml translations platforms imageformats iconengines styles tls networkinformation generic printsupport) do if exist "%BUILD_DIR%\%%~D" rmdir /s /q "%BUILD_DIR%\%%~D"

rem Previous payloads are removed only after both new folders were activated.
if exist "%PREVIOUS_APP_DIR%" (
    rmdir /s /q "%PREVIOUS_APP_DIR%"
    if exist "%PREVIOUS_APP_DIR%" echo [WARNING] Previous app payload could not be cleaned; it remains at "%PREVIOUS_APP_DIR%".
)
if exist "%PREVIOUS_BOOTSTRAP_DIR%" (
    rmdir /s /q "%PREVIOUS_BOOTSTRAP_DIR%"
    if exist "%PREVIOUS_BOOTSTRAP_DIR%" echo [WARNING] Previous bootstrap payload could not be cleaned; it remains at "%PREVIOUS_BOOTSTRAP_DIR%".
)
if exist "%SIM_STAGE_ROOT%" rmdir /s /q "%SIM_STAGE_ROOT%"

echo.
echo === Creating desktop shortcut ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "$desktop = [Environment]::GetFolderPath('Desktop'); $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Argon.lnk')); $shortcut.TargetPath = '%SIM_APP_DIR%\Argon.exe'; $shortcut.WorkingDirectory = '%SIM_ROOT%'; $shortcut.Description = 'Launch Argon'; $shortcut.Save()"
if errorlevel 1 echo [WARNING] Could not create the desktop shortcut. Argon itself was built successfully.

echo.
echo === Creating Start Menu shortcut ===
powershell -NoProfile -ExecutionPolicy Bypass -Command "$programs = [Environment]::GetFolderPath('Programs'); $argonMenu = Join-Path $programs 'Argon'; if (-not (Test-Path -LiteralPath $argonMenu)) { New-Item -ItemType Directory -Path $argonMenu -Force | Out-Null }; $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut((Join-Path $argonMenu 'Argon.lnk')); $shortcut.TargetPath = '%SIM_APP_DIR%\\Argon.exe'; $shortcut.WorkingDirectory = '%SIM_ROOT%'; $shortcut.Description = 'Launch Argon'; $shortcut.IconLocation = '%SIM_APP_DIR%\\Argon.exe,0'; $shortcut.Save()"
if errorlevel 1 echo [WARNING] Could not create the Start Menu shortcut. Argon itself was built successfully.

echo.
echo ========================================
echo BUILD AND DEPLOYMENT SUCCEEDED
echo Runnable app:       "%SIM_APP_DIR%\Argon.exe"
echo Bootstrap:          "%SIM_BOOTSTRAP_DIR%\Bootstrap.exe"
echo Test data:          "%TARGET_SEARCH%"
echo User data:          "%SIM_ROOT%\UserData"
echo Update backups:     "%SIM_ROOT%\Updates\Backups"
echo Logs:               "%SIM_ROOT%\Logs"
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
