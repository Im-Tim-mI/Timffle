@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Per-user install of the Timffle socket helper for Google Chrome.
rem No administrator rights, background service or security setting changes.
set "ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"
set "TARGET="
if /i "%ARCH%"=="AMD64" set "TARGET=windows-amd64"
if /i "%ARCH%"=="ARM64" set "TARGET=windows-arm64"
if /i "%ARCH%"=="x86" set "TARGET=windows-386"
set "RC=1"
if not defined TARGET goto unsupported
"%~dp0bin\%TARGET%\timffle-socket-helper.exe" --install
set "RC=%ERRORLEVEL%"
goto done
:unsupported
echo Unsupported Windows architecture: %ARCH%
:done
echo.
pause
exit /b %RC%
