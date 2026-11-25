@echo off
setlocal EnableExtensions
title Delta Force - Map Download Switch

rem =====================================================================
rem  Launcher for the PowerShell script that sits next to this file.
rem  Keep both files in the same folder. Double-click this .bat only.
rem =====================================================================

rem  Pinned on purpose: the source folder also holds the packer script,
rem  so a *.ps1 wildcard could pick the wrong one.
set "PS1=%~dp0DeltaForce-MapDownload.ps1"

if not exist "%PS1%" (
    echo [ERROR] DeltaForce-MapDownload.ps1 not found next to this .bat file.
    echo         Keep the .bat and the .ps1 in the same folder.
    echo.
    pause
    exit /b 1
)

rem ---- require administrator (firewall rules need it) ----
fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges - please confirm the UAC prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

rem ---- run ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
