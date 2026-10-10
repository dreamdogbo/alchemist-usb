==========================================================================
 LINUX INSTALLATION KEY (Ubuntu LTS, Linux Mint, Debian, Fedora…)
 Alchemist v{{KIT_VERSION}} by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
==========================================================================

STEP 1 — INSTALL LINUX
  Boot the key (F12/F11/F9/F8/Esc), pick the ISO in the Ventoy menu (Ubuntu LTS
  recommended), follow the installer. Check "third-party software" if offered.
  CAREFUL with the disk choice: erasing a disk deletes its data.

STEP 2 — SOFTWARE (on the Linux desktop, with Internet)
  Open the key, folder "linux", right-click → "Open in Terminal", then:
      bash lancer.sh
  Pick the usage (office / development), check the software, confirm.
  Without a window:  sudo bash installer-poste.sh -u developpement -y
  Dry run:           bash installer-poste.sh -u developpement -n -y

MICROSOFT 365 ON LINUX
  Web apps (Word, Excel, PowerPoint, Outlook, Teams, OneDrive) via Microsoft Edge,
  ONLYOFFICE for local editing, WinBoat for full desktop Office (licence required).

Logs: /var/log/kit-poste/ (copy in the home folder).
