@echo off
setlocal
cd /d "%~dp0"

rem Keep the window open when build.bat is launched directly.
rem run.bat passes /nopause because it continues by launching Argon.
set "KEEP_WINDOW_OPEN=1"
if /I "%~1"=="/nopause" set "KEEP_WINDOW_OPEN=0"

set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"
set "BUILD_DIR=%~dp0build"

echo ========================================
echo Argon build
echo ========================================
echo Repository: %CD%
echo Build directory: %BUILD_DIR%
echo.

if not exist "%QT_ROOT%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo [ERROR] Qt 6 CMake package was not found under "%QT_ROOT%".
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
    echo [ERROR] CMake configuration failed. See the output above.
    goto :build_failed
)

echo.
echo === Building Argon ===
cmake --build "%BUILD_DIR%" --parallel
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed. See the compiler output above.
    goto :build_failed
)

echo.
echo ========================================
echo BUILD SUCCEEDED
echo Executable: "%BUILD_DIR%\Argon.exe"
echo ========================================
if not exist "%BUILD_DIR%\Argon.exe" (
    echo [ERROR] Build command succeeded, but build\Argon.exe was not found.
    goto :build_failed
)

if "%KEEP_WINDOW_OPEN%"=="1" (
    echo.
    pause
)
exit /b 0

:build_failed
set "BUILD_EXIT_CODE=1"
if "%KEEP_WINDOW_OPEN%"=="1" (
    echo.
    echo The build did not complete. Read the error output above.
    pause
)
exit /b %BUILD_EXIT_CODE%
