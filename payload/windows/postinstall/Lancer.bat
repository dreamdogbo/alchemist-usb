@echo off
REM ============================================================
REM  Installation du poste depuis la cle Ventoy (fenetre)
REM  Double-cliquer ce fichier, puis accepter la demande
REM  d'autorisation (droits administrateur).
REM
REM  Mode automatique sans fenetre (tout installer) :
REM     Lancer.bat -Auto            (+ options : -SansOffice  -NomPoste PC-012)
REM ============================================================
cd /d "%~dp0"
if /i "%~1"=="-Auto" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Poste.ps1" -AttendreFin %2 %3 %4 %5 %6
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Assistant-Poste.ps1"
)
