@echo off
setlocal
cd /d "%~dp0"
title NotLight

if not exist "NotLight.exe" (
  echo NotLight.exe is missing from this folder.
  echo Please extract the entire NotLight ZIP before starting the program.
  echo.
  pause
  exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Windows PowerShell could not be found.
  echo NotLight first-run setup cannot continue on this system.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_WINDOWS_DEPENDENCIES.ps1" -QuietIfReady
if errorlevel 1 (
  echo.
  echo Setup did not finish. NotLight was not started.
  echo You can run START_NOTLIGHT.bat again after checking your Internet connection.
  echo.
  pause
  exit /b 1
)

start "" "%~dp0NotLight.exe"
exit /b 0
