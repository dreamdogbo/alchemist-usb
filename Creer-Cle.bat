@echo off
REM ============================================================
REM  Alchemist - Assistant de preparation de cle (fenetre)
REM  Double-cliquer ce fichier.
REM ============================================================
cd /d "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0Assistant.ps1"
