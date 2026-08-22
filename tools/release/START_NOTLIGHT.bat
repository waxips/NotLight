@echo off
setlocal
cd /d "%~dp0"
title NotLight

if not exist "NotLight.exe" (
  echo NotLight.exe is missing from this folder.
  echo Please extract the whole NotLight ZIP before starting the program.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP_WINDOWS_DEPENDENCIES.ps1" -QuietIfReady
if errorlevel 1 (
  echo.
  echo Setup did not finish. NotLight was not started.
  pause
  exit /b 1
)

start "" "%~dp0NotLight.exe"
exit /b 0
