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
set "SIM_ROOT=%USERPROFILE%\Desktop\Argon-sim"
set "SIM_APP_DIR=%SIM_ROOT%\App"
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
echo === Configuring Argon ===
cmake -S "%~dp0." -B "%BUILD_DIR%" -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="%QT_ROOT%" -DCMAKE_CXX_COMPILER="%MINGW_ROOT%\bin\g++.exe" -DCMAKE_MAKE_PROGRAM="%MINGW_ROOT%\bin\mingw32-make.exe"
if errorlevel 1 (
    echo.
    echo [ERROR] CMake configuration failed. See output above.
    goto :build_failed
)

echo.
echo === Compiling Argon ===
cmake --build "%BUILD_DIR%" --parallel
if errorlevel 1 (
    echo.
    echo [ERROR] Compilation failed. See output above.
    goto :build_failed
)
if not exist "%BUILD_DIR%\Argon.exe" (
    echo [ERROR] Build completed but build\Argon.exe was not found.
    goto :build_failed
)

echo.
echo === Preparing desktop test folder ===
if not exist "%SIM_ROOT%" mkdir "%SIM_ROOT%"
if errorlevel 1 goto :build_failed

rem App contains only the executable payload. Rebuild it cleanly so stale Qt DLLs
rem from a previous build cannot remain beside the new executable.
if exist "%SIM_APP_DIR%" (
    rmdir /s /q "%SIM_APP_DIR%"
    if exist "%SIM_APP_DIR%" (
        echo [ERROR] Could not replace "%SIM_APP_DIR%".
        echo Close any running Argon-sim instance and run build.bat again.
        goto :build_failed
    )
)
mkdir "%SIM_APP_DIR%"
if errorlevel 1 goto :build_failed

echo.
echo === Copying Argon.exe to Argon-sim ===
copy /y "%BUILD_DIR%\Argon.exe" "%SIM_APP_DIR%\Argon.exe"
if errorlevel 1 (
    echo [ERROR] Could not copy Argon.exe to the desktop test folder.
    goto :build_failed
)

echo.
echo === Deploying Qt DLLs, plugins, and QML modules ===
"%QT_ROOT%\bin\windeployqt.exe" --qmldir "%~dp0qml" --compiler-runtime "%SIM_APP_DIR%\Argon.exe"
if errorlevel 1 (
    echo [ERROR] Qt dependency deployment failed. See output above.
    goto :build_failed
)

echo.
echo === Preparing test data ===
if not exist "%TARGET_SEARCH%" mkdir "%TARGET_SEARCH%"
if errorlevel 1 (
    echo [ERROR] Could not create the Argon-sim Search QR test folder.
    goto :build_failed
)

rem Seed representative test files only when absent. Never overwrite user test files.
if exist "%SOURCE_SEARCH%\README.md" if not exist "%TARGET_SEARCH%\README.md" copy "%SOURCE_SEARCH%\README.md" "%TARGET_SEARCH%\README.md" >nul
if exist "%SOURCE_SEARCH%\LDA1.pdf" if not exist "%TARGET_SEARCH%\LDA1.pdf" copy "%SOURCE_SEARCH%\LDA1.pdf" "%TARGET_SEARCH%\LDA1.pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (2).pdf" if not exist "%TARGET_SEARCH%\LDA1 (2).pdf" copy "%SOURCE_SEARCH%\LDA1 (2).pdf" "%TARGET_SEARCH%\LDA1 (2).pdf" >nul
if exist "%SOURCE_SEARCH%\LDA1 (3).pdf" if not exist "%TARGET_SEARCH%\LDA1 (3).pdf" copy "%SOURCE_SEARCH%\LDA1 (3).pdf" "%TARGET_SEARCH%\LDA1 (3).pdf" >nul

echo.
echo ========================================
echo BUILD AND DEPLOYMENT SUCCEEDED
echo Runnable app: "%SIM_APP_DIR%\Argon.exe"
echo Test data:    "%TARGET_SEARCH%"
echo User data:    "%SIM_ROOT%\UserData"
echo Logs:         "%SIM_ROOT%\Logs"
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
