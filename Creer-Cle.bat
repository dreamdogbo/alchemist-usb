@echo off
REM ============================================================
REM  Alchemist - Assistant de preparation de cle (fenetre)
REM  Double-cliquer ce fichier.
REM
REM  Le lanceur (modules\Lanceur.ps1) affiche un message clair si
REM  la fenetre ne peut pas s'ouvrir, au lieu d'echouer en silence.
REM  Depannage : Creer-Cle.bat -Console (garde la console ouverte)
REM ============================================================
setlocal
cd /d "%~dp0" 2>nul

REM Lance depuis l'archive ZIP sans l'avoir extraite : les autres fichiers manquent
if not exist "%~dp0Assistant.ps1" goto :archive
if not exist "%~dp0modules\Lanceur.ps1" goto :archive

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

if /i "%~1"=="-Console" (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0modules\Lanceur.ps1" -Console
    pause
    exit /b
)
start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0modules\Lanceur.ps1"
exit /b

:archive
echo.
echo  Alchemist : des fichiers du kit sont introuvables a cote de Creer-Cle.bat.
echo.
echo  Vous l'avez sans doute ouvert DEPUIS l'archive ZIP. Faites d'abord :
echo    clic droit sur l'archive ^> Extraire tout... ^> puis double-cliquez
echo    Creer-Cle.bat dans le dossier extrait.
echo.
pause
exit /b 1
