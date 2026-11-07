@echo off
rem Starts the Timffle local bridge (relay.mjs) for the websites you name.
rem No website is allowed unless you give it: double-click and type one exact
rem website origin when asked (for example https://game.example), or run
rem   start-relay.cmd https://game.example http://game.example
rem to allow several. Then paste proxyUrl from connection.json into the
rem extension options and add the same websites there.
setlocal
cd /d "%~dp0"
set "ORIGINS="
:args
if "%~1"=="" goto ask
set ORIGINS=%ORIGINS% --origin "%~1"
shift
goto args
:ask
if defined ORIGINS goto run
set "SITE="
set /p "SITE=Website address (for example https://game.example): "
if not defined SITE goto none
set ORIGINS=--origin "%SITE%"
:run
node relay.mjs %ORIGINS%
pause
exit /b
:none
echo No website given; the bridge was not started.
pause
exit /b 2
