@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================
echo Argon - development launcher
echo ========================================
echo.
echo QML is loaded directly from the source tree.
echo C++ is built incrementally; unchanged files are not rebuilt.
echo No release packaging or deployment is performed.
echo.

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "BUILD_DIR=%~dp0build-dev"
set "SIM_ROOT=%LOCALAPPDATA%\Argon-sim"
if not defined LOCALAPPDATA set "SIM_ROOT=%USERPROFILE%\AppData\Local\Argon-sim"

if not exist "%QT_ROOT%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo [ERROR] Qt 6 CMake package was not found under "%QT_ROOT%".
    goto :failed
)
if not exist "%QT_ROOT%\qml\QtQuick" (
    echo [ERROR] Qt Quick QML modules were not found under "%QT_ROOT%\qml".
    goto :failed
)
if not exist "%MINGW_ROOT%\bin\g++.exe" (
    echo [ERROR] MinGW compiler was not found at "%MINGW_ROOT%\bin\g++.exe".
    goto :failed
)
if not exist "%MINGW_ROOT%\bin\mingw32-make.exe" (
    echo [ERROR] MinGW Make was not found at "%MINGW_ROOT%\bin\mingw32-make.exe".
    goto :failed
)

set "PATH=%MINGW_ROOT%\bin;%QT_ROOT%\bin;%PATH%"
set "QT_PLUGIN_PATH=%QT_ROOT%\plugins"
set "QT_QPA_PLATFORM_PLUGIN_PATH=%QT_ROOT%\plugins\platforms"
set "QML_IMPORT_PATH=%QT_ROOT%\qml"
set "QML2_IMPORT_PATH=%QT_ROOT%\qml"
set "QT_QUICK_CONTROLS_STYLE=Basic"
set "ARGON_DEV_QML_DIR=%~dp0qml"
rem Use the same persistent user data as the normal Argon-sim installation.
set "ARGON_DATA_ROOT=%SIM_ROOT%"

echo === Configuring the isolated development build ===
cmake -S "%~dp0." -B "%BUILD_DIR%" -G "MinGW Makefiles" ^
    -DCMAKE_PREFIX_PATH="%QT_ROOT%" ^
    -DCMAKE_CXX_COMPILER="%MINGW_ROOT%\bin\g++.exe" ^
    -DCMAKE_MAKE_PROGRAM="%MINGW_ROOT%\bin\mingw32-make.exe" ^
    -DARGON_RUNTIME_OUTPUT_DIR= ^
    -DARGON_DEV_SOURCE_QML=ON ^
    -DARGON_ENABLE_SCRIPT_CONSOLE=ON ^
    -DARGON_BUILD_SCRIPTING_TESTS=ON
if errorlevel 1 goto :failed

echo.
echo === Building Argon (incremental C++ build) ===
cmake --build "%BUILD_DIR%" --target Argon --parallel
if errorlevel 1 goto :failed

if not exist "%BUILD_DIR%\Argon.exe" (
    echo [ERROR] The development executable was not created:
    echo "%BUILD_DIR%\Argon.exe"
    goto :failed
)

if not exist "%SIM_ROOT%\Logs" mkdir "%SIM_ROOT%\Logs"
if exist "%SIM_ROOT%\Logs\argon-runtime.log" del /f /q "%SIM_ROOT%\Logs\argon-runtime.log"

echo.
echo === Launching source-QML development build ===
echo Executable: "%BUILD_DIR%\Argon.exe"
echo QML source: "%ARGON_DEV_QML_DIR%"
echo User data:  "%SIM_ROOT%"
echo Press F12 for the interpreter console.
echo.

"%BUILD_DIR%\Argon.exe"
set "ARGON_EXIT_CODE=%errorlevel%"

if not "%ARGON_EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Argon exited with code %ARGON_EXIT_CODE%.
    if exist "%SIM_ROOT%\Logs\argon-runtime.log" (
        echo.
        echo === Runtime log ===
        type "%SIM_ROOT%\Logs\argon-runtime.log"
    )
    goto :failed
)

echo.
echo Argon closed normally.
pause
exit /b 0

:failed
echo.
echo Development launch failed. Read the diagnostic output above.
pause
exit /b 1
