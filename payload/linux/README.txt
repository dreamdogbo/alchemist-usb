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

MICROSOFT 365 ON LINUX (full desktop version)
  Component "office365": the real desktop Word, Excel, PowerPoint, Outlook, OneNote in a hidden
  lightweight Windows (LinOffice: Podman + KVM + FreeRDP), launched from the Linux menu.
  Requires virtualization enabled, 8 GB RAM, 64 GB free, a Microsoft 365 licence.

Logs: /var/log/kit-poste/ (copy in the home folder).
