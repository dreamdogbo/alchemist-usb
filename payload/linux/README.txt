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
  The assistant opens in the browser (same as on Windows): pick the usage (office /
  development), check the software, click "Install". Classic windows: bash lancer.sh --zenity
  Without a window:  sudo bash installer-poste.sh -u developpement -y
  Dry run:           bash installer-poste.sh -u developpement -n -y

MICROSOFT 365 ON LINUX (full desktop version)
  Component "office365": the real desktop Word, Excel, PowerPoint, Outlook, OneNote in a hidden
  lightweight Windows (LinOffice: Podman + KVM + FreeRDP), launched from the Linux menu.
  Requires virtualization enabled, 8 GB RAM, 64 GB free, a Microsoft 365 licence.

CONTAINERS (development usage)
  Native Docker Engine + Podman Desktop (GUI) + Trivy (security scanner). Docker Desktop is still
  offered, unchecked (paid licence for public sector and organisations over 250 employees or $10M).
  Log out and back in after installation (docker, kvm groups). Podman Desktop also shows the
  LinOffice/WinBoat containers: do not delete them.

Logs: /var/log/kit-poste/ (copy in the home folder).
