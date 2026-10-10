@echo off
REM ============================================================
REM  Pilotes : lance Snappy Driver Installer Origin (SDIO) depuis la cle
REM  (open source GPLv3, portable). SDIO demande lui-meme les droits
REM  administrateur. Packs de pilotes : voir LISEZMOI.txt.
REM ============================================================
set "SDIODIR=%~dp0..\Logiciels\SDIO\app"
for /f "delims=" %%f in ('dir /b /s "%SDIODIR%\SDIO_x64*.exe" 2^>nul') do (
    start "" /d "%%~dpf" "%%f"
    goto :eof
)
echo SDIO est introuvable sur la cle (dossier Logiciels\SDIO).
echo Relancez la preparation de la cle avec Internet pour l'ajouter.
pause
