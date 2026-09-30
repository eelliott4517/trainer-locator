@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Trainer Locator installer

rem Installs the TrainerLocator addon into the WoW: Forever beta.
rem Double-click it, or pass your World of Warcraft folder:
rem   Install-TrainerLocator.bat "D:\Games\World of Warcraft"

set "FLAVOR=_classic_beta_"
set "SRC=%~dp0TrainerLocator"
set "WOW="

echo Trainer Locator installer
echo.

if not exist "%SRC%\TrainerLocator.toc" goto :nosource

rem 1) A folder given on the command line
if not "%~1"=="" call :consider "%~1"
if defined WOW goto :found

rem 2) Blizzard's registry entries (InstallPath points at the WoW folder or a game folder inside it)
for %%K in ("HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft" "HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft" "HKCU\SOFTWARE\Blizzard Entertainment\World of Warcraft") do (
	for /f "tokens=2,*" %%A in ('reg query %%K /v InstallPath 2^>nul ^| find /i "InstallPath"') do call :consider "%%B"
)
if defined WOW goto :found

rem 3) The usual install locations
call :consider "%ProgramFiles(x86)%\World of Warcraft"
call :consider "%ProgramFiles%\World of Warcraft"
for %%D in (C D E F G H) do (
	call :consider "%%D:\World of Warcraft"
	call :consider "%%D:\Games\World of Warcraft"
	call :consider "%%D:\Program Files (x86)\World of Warcraft"
	call :consider "%%D:\Program Files\World of Warcraft"
	call :consider "%%D:\Blizzard\World of Warcraft"
	call :consider "%%D:\Battle.net\World of Warcraft"
)
if defined WOW goto :found

rem 4) Ask
echo Couldn't find the WoW: Forever beta automatically.
echo Paste the path of your World of Warcraft folder and press Enter.
echo Tip: open that folder in File Explorer, click the address bar and copy it.
echo.
set "ANSWER="
set /p "ANSWER=Folder: "
if not defined ANSWER goto :cancel
set "ANSWER=%ANSWER:"=%"
call :consider "%ANSWER%"
if defined WOW goto :found
echo.
echo That folder doesn't contain %FLAVOR%. Make sure the Forever beta is installed there.
goto :fail

:found
set "GAME=%WOW%\%FLAVOR%"
set "ADDONS=%GAME%\Interface\AddOns"
set "DEST=%ADDONS%\TrainerLocator"
echo Found the WoW: Forever beta in:
echo   "%GAME%"
if not exist "%ADDONS%\" mkdir "%ADDONS%" 2>nul
if not exist "%ADDONS%\" goto :denied
rem Replace any older copy. Your settings live in WTF, so they're kept.
if exist "%DEST%\" rmdir /s /q "%DEST%"
if exist "%DEST%\" goto :denied
xcopy "%SRC%" "%DEST%\" /E /I /Q /Y >nul
if errorlevel 1 goto :denied
if not exist "%DEST%\TrainerLocator.toc" goto :denied

echo.
echo Installed to:
echo   "%DEST%"
echo.
tasklist /NH 2>nul | findstr /I /B "wow" >nul
if errorlevel 1 goto :notrunning
echo WoW is running. Quit and restart it to load the addon. A /reload won't pick up a new addon.
goto :tips
:notrunning
echo Start WoW: Forever and type /trainers.
:tips
echo If the AddOns list marks it out of date, tick "Load out of date AddOns".
goto :done

rem Accepts the WoW folder itself, or a folder inside it such as _retail_, _classic_beta_ or its AddOns folder
:consider
if defined WOW exit /b 0
set "CAND=%~1"
if not defined CAND exit /b 0
if "%CAND:~-1%"=="\" set "CAND=%CAND:~0,-1%"
if not defined CAND exit /b 0
for %%P in ("%CAND%" "%CAND%\.." "%CAND%\..\.." "%CAND%\..\..\..") do (
	if not defined WOW if exist "%%~fP\%FLAVOR%\" set "WOW=%%~fP"
)
exit /b 0

:nosource
echo Can't find the TrainerLocator folder next to this installer.
echo Extract the whole zip first, then run Install-TrainerLocator.bat from the extracted folder.
goto :fail

:denied
echo.
echo Couldn't write to:
echo   "%ADDONS%"
echo Right-click Install-TrainerLocator.bat and choose "Run as administrator",
echo or copy the TrainerLocator folder into that AddOns folder yourself.
goto :fail

:cancel
echo Cancelled.

:fail
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0
