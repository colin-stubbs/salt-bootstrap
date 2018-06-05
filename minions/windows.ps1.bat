@echo off

REM We need to force unrestricted execution policy here
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force"

REM Run powershell from URL
powershell https://files.routedlogic.net/salt/bootstrap/windows.ps1

REM Change execution policy back to restricted
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy Restricted -Force"
