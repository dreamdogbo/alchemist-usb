@echo off
REM ============================================================
REM  Pilotes : ouvre la bonne source de pilotes pour ce PC
REM   - avec Internet : page OFFICIELLE du fabricant (detecte)
REM   - sans Internet : Snappy Driver Installer Origin (SDIO) depuis la cle
REM  Options : Pilotes.bat SDIO | Fabricant | Windows | Liste
REM ============================================================
set "SRC=%~1"
if "%SRC%"=="" set "SRC=Auto"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Pilotes.ps1" -Source %SRC%
if errorlevel 1 pause
