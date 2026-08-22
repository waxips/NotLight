@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo NotLight - check Windows export runtime
echo ============================================================
echo.
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check_export_runtime_windows.ps1"
set EXITCODE=%ERRORLEVEL%
echo.
if not "%EXITCODE%"=="0" (
  echo FAILED. Read the error above or send a screenshot of this whole window.
) else (
  echo CHECK PASSED.
)
echo.
pause
exit /b %EXITCODE%
