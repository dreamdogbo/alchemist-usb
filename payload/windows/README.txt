==========================================================================
 INSTALLATION KEY — WINDOWS 11 WORKSTATION (works WITHOUT Internet)
 Alchemist v{{KIT_VERSION}} by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
==========================================================================

KEY CONTENTS
  ISO\{{ISO_NAME}}            Official Windows 11 (64-bit)
  ISO\Windows10_*.iso         Official Windows 10 22H2 (if added)
  ISO\Linux\...               Linux systems (if added when building the key)
  ISO\Personnel\              Your own images (Windows 7, 8.1…), if added
  Windows7\                   Windows 7 compatibility pack (if added):
                              see postinstall\Windows7.txt (French)
  Bureautique\                Microsoft 365 Apps and/or LibreOffice / ONLYOFFICE
  Logiciels\                  Browsers, PDF, media, utilities, tools
  postinstall\Lancer.bat      Installs software after Windows (window)
  postinstall\Pilotes.bat     Installs drivers (Snappy Driver Installer Origin)
  MANIFEST.sha256             Integrity hashes (do not edit)

STEP 1 — INSTALL WINDOWS 11 (or another system)
  1. Plug in the key, power on, open the boot menu (F12, F11, F9, F8 or Esc).
  2. Choose the USB key: the Ventoy menu lists every system.
  3. Choose the Windows 11 (or Windows 10) ISO, then the
     "Windows11_HorsLigne.xml" template (recommended: LOCAL account without
     Internet). Windows 7: see postinstall\Windows7.txt (Legacy/CSM boot).
  4. Product key: type it, or "I don't have a product key" (licensed PCs
     activate later automatically). PRO edition recommended.
  5. "Custom" install: CHOOSE THE RIGHT DISK. Deleting a partition erases it.
  6. Create the user account. If a screen still requires a network:
     Shift+F10, type  start ms-cxh:localonly  then Enter.

STEP 2 — SOFTWARE AND SETTINGS (on the Windows desktop)
  1. Open the key, folder postinstall, double-click Lancer.bat: the assistant opens
     in the browser (same assistant as for Linux).
  2. It shows each program: already installed / on the key / online (winget).
     Check what you need, optionally a computer name, click "Install" and accept
     the administrator prompt. Windows is activated with the PC's own licence, if any.
  Classic window (also "Complete the key" and drivers menu): Lancer.bat -Classique
  3. Wait for the final message (20-40 min with Office). Keep the key plugged in.
  4. Restart the PC.
  "Complete the key (Internet)" button: downloads missing programs ONTO THE KEY.

STEP 3 — DRIVERS: double-click postinstall\Pilotes.bat (SDIO).

Activation: official licences only. Logs: C:\PostInstall\
