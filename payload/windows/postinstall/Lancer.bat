@echo off
REM ============================================================
REM  Installation du poste depuis la cle Ventoy (fenetre)
REM  Double-cliquer ce fichier, puis accepter la demande
REM  d'autorisation (droits administrateur).
REM
REM  Assistant universel dans le navigateur (identique sous Linux) ;
REM  fenetre classique : Lancer.bat -Classique
REM
REM  Mode automatique sans fenetre (tout installer) :
REM     Lancer.bat -Auto            (+ options : -SansOffice  -NomPoste PC-012)
REM ============================================================
cd /d "%~dp0"

REM Windows 7 / 8.1 : la post-installation exige Windows 10 ou 11 (PowerShell 5.1).
REM On ouvre le pack de compatibilite Windows 7 de la cle et son mode d'emploi.
ver | findstr /r /i /c:"version 6\.[0-3]\." >nul
if not errorlevel 1 (
    if exist "%~dp0..\Windows7\" start "" explorer.exe "%~dp0..\Windows7"
    start "" notepad.exe "%~dp0Windows7.txt"
    exit /b 0
)
if /i "%~1"=="-Auto" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Poste.ps1" -AttendreFin %2 %3 %4 %5 %6
    exit /b
)
if /i "%~1"=="-Classique" goto :classique
if not exist "%~dp0alchemist.html" goto :classique
REM Assistant universel ; s'il ne demarre pas (code non nul), fenetre classique
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { & '%~dp0Assistant-Poste-Web.ps1' } catch { & '%~dp0Assistant-Poste.ps1' }"
exit /b

:classique
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Assistant-Poste.ps1"
