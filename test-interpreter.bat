@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ========================================
echo Argon Script - targeted interpreter tests
echo ========================================
echo Only ArgonScriptingTests is built. The Argon desktop app is not rebuilt
echo and no files are deployed.
echo.

set "BUILD_DIR=%~dp0build"
set "QT_ROOT=C:\Qt\6.12.0\mingw_64"
set "MINGW_ROOT=C:\Qt\Tools\mingw1310_64"

if not exist "%BUILD_DIR%\CMakeCache.txt" (
    echo [ERROR] No configured CMake build was found at "%BUILD_DIR%".
    echo The test target is prepared by the existing build.bat configuration.
    echo Run build.bat only when you intentionally want to configure/build the app.
    goto :failed
)

findstr /B /C:"ARGON_BUILD_SCRIPTING_TESTS:BOOL=ON" "%BUILD_DIR%\CMakeCache.txt" >nul
if errorlevel 1 (
    echo [ERROR] This build directory was not configured with scripting tests enabled.
    echo The normal build.bat configuration enables this option.
    echo Do not run this file as a launcher; use run.bat to open Argon.
    goto :failed
)

if exist "%MINGW_ROOT%\bin" set "PATH=%MINGW_ROOT%\bin;%PATH%"
if exist "%QT_ROOT%\bin" set "PATH=%QT_ROOT%\bin;%PATH%"

echo === Building only ArgonScriptingTests ===
cmake --build "%BUILD_DIR%" --target ArgonScriptingTests --parallel
if errorlevel 1 goto :failed

echo.
echo === Running only ArgonScriptingTests ===
ctest --test-dir "%BUILD_DIR%" --output-on-failure -R "^ArgonScriptingTests$"
if errorlevel 1 goto :failed

echo.
echo Interpreter tests passed.
echo.
echo === Launching Argon via run.bat ===
call "%~dp0run.bat"
exit /b %errorlevel%

:failed
echo.
echo Interpreter test command failed. See the diagnostic output above.
pause
exit /b 1
