# La stack Alchemist

Ce qu'Alchemist installe selon le **système** et l'**usage** choisis. Tout vient de sources officielles,
dans la dernière version stable au moment où la clé est préparée (Windows) ou au moment de la
post-installation (Linux).

Légende : ● installé par défaut · ○ proposé (à cocher)

## Linux (Ubuntu LTS recommandé · Linux Mint · Debian · Fedora)

Post-installation : `linux/lancer.sh` (fenêtre) ou `installer-poste.sh` (ligne de commande),
familles apt (Ubuntu, Mint, Debian) et dnf (Fedora), dépôts officiels des éditeurs.

| Domaine | Outils | Bureautique | Développement |
| --- | --- | :-: | :-: |
| Système | mises à jour, Flatpak + Flathub, pilotes (ubuntu-drivers) et micrologiciels (fwupd), codecs + VLC, réglages GNOME | ● | ● |
| Polices | compatibles Office : Carlito (Calibri), Caladea (Cambria), Liberation, Microsoft core fonts, Fira Code | ● | ● |
| Sécurité | pare-feu (ufw / firewalld), ClamAV + ClamTk, KeePassXC, Timeshift | ● | ● |
| Navigateurs | Google Chrome, Microsoft Edge (Firefox déjà présent) | ● | ● |
| **Microsoft 365 intégral** | **Word, Excel, PowerPoint, Outlook, OneNote de bureau** via **LinOffice** (Windows léger KVM + FreeRDP, applications dans le menu Linux) | ● | ● |
| Microsoft 365 en ligne | Teams, OneDrive, Office web (raccourcis Edge) | ● | ● |
| Suites locales | **ONLYOFFICE** (meilleure compatibilité .docx/.xlsx/.pptx) · LibreOffice | ● | ● / ○ |
| Applications Windows | **WinBoat** : toute application Windows en conteneur (alternative à LinOffice) | ○ | ○ |
| PDF | **PDFCraft**, Okular, Xournal++, PDF Arranger | ● | ● |
| Communication | Zoom · Slack, Discord | ● · ○ | ● · ○ |
| Terminal et compilation | build-essential, cmake, gdb, ShellCheck, direnv, ripgrep, fd, fzf, bat, eza, tmux, Neovim, httpie, yq, zsh, tldr | | ● |
| Git | Git, Git LFS, **GitHub CLI (gh)**, lazygit, Meld | | ● |
| Éditeur | **Visual Studio Code** (dépôt Microsoft) · JetBrains Toolbox | | ● · ○ |
| Conteneurs | **Docker Engine + Compose + Buildx**, **Docker Desktop**, KVM/QEMU + virt-manager | | ● |
| Langages | Python 3 + pipx + **uv**, **Node.js LTS** (nvm) + pnpm/yarn (corepack), Java JDK + Maven, .NET SDK, Go, Rust (rustup) | | ● |
| API et données | **Bruno**, **DBeaver** Community | | ● |
| DevOps | kubectl, Helm, Terraform, Ansible, AWS CLI, Azure CLI | | ○ |
| Création | GIMP, Inkscape, Krita, Kdenlive, OBS Studio, Audacity, HandBrake (DaVinci Resolve : manuel) | ○ | ○ |
| Suite ArtCraft | PhotoCraft (Photoshop), VectorCraft (Illustrator), FilmCraft (montage), LightCraft (Lightroom), EffectCraft (After Effects), DesignCraft (InDesign) | ○ | ○ |

### Microsoft 365 intégral sous Linux : LinOffice

Microsoft ne publie pas Office pour Linux, et les couches Wine/CrossOver ne font plus fonctionner
Microsoft 365 (CrossOver le classe « ne démarre pas » depuis janvier 2026). La solution **intégrale et
stable** est la vraie version Windows d'Office dans un **Windows minimal** (dockur/windows) en conteneur
**Podman + KVM**, dont les fenêtres sont affichées par **FreeRDP** comme des applications Linux :
**[LinOffice](https://github.com/eylenburg/linoffice)** (basé sur WinApps).

- **100 % Office** : macros VBA, compléments, mise en page, Outlook, OneNote — c'est le vrai Office.
- **Intégré** : Word, Excel, PowerPoint, Outlook, OneNote dans le menu ; ouverture des fichiers de
  `/home` par clic droit ; presse-papier partagé.
- **Automatique** : Windows et Office sont téléchargés depuis Microsoft ; la connexion au compte
  Microsoft 365 active Office 365. Mises à jour : `linoffice.sh update`.
- **Prérequis** (vérifiés par Alchemist) : virtualisation activée (VT-x/AMD-V), **8 Go de RAM**,
  **64 Go libres**, **licence Microsoft 365** légitime.
- **Compléments** : Microsoft 365 en ligne (Teams, OneDrive) et ONLYOFFICE pour l'édition rapide hors ligne.

## Windows 11

Contenu **hors ligne** sur la clé, installé par `postinstall\Lancer.bat` (fenêtre).

| Domaine | Outils | Bureautique | Développement |
| --- | --- | :-: | :-: |
| Système | Windows 11 officiel (FR, EN, ES, DE, PT), installation avec compte local hors ligne | ● | ● |
| Bureautique | Microsoft 365 Apps hors ligne · **ou** LibreOffice / ONLYOFFICE (gratuits) | ● · ○ | ● · ○ |
| Runtimes | Visual C++ 2015+ (x64, x86), .NET Desktop Runtime | ● | ● |
| Navigateurs | Chrome, Firefox | ● | ● |
| PDF | Acrobat Reader, PDF24, **PDFCraft** | ● | ● |
| Utilitaires | 7-Zip, VLC, Notepad++, ShareX, Chocolatey + Chocolatey GUI | ● | ● |
| Communication | Teams, Zoom | ● | ● |
| Sécurité | Microsoft Defender (intégré) + **ClamAV** (analyse à la demande) · KeePassXC | ● · | ● |
| Éditeur et terminal | **VS Code**, PowerShell 7, PowerToys · JetBrains Toolbox | | ● · ○ |
| Git | **Git**, **GitHub CLI** · GitHub Desktop | | ● · ○ |
| Conteneurs | **WSL 2**, **Docker Desktop** | | ● |
| Langages | **Python**, **Node.js LTS**, Java (Temurin 25), .NET SDK 10 · Go, Rust | | ● · ○ |
| API et données | **Bruno**, **DBeaver** · Postman | | ● · ○ |
| Création | GIMP, Inkscape, Krita, Kdenlive, OBS Studio, Audacity · Suite ArtCraft | ○ | ● (GIMP, Inkscape) · ○ |
| Outils technicien | Snappy Driver Installer Origin, CrystalDiskInfo, HWiNFO, liens pilotes officiels des fabricants | ○ | ○ |

## Multiboot

Une même clé peut porter plusieurs systèmes : Ubuntu LTS (dernière et précédente), Linux Mint, Debian,
Fedora et Windows 11. Ventoy affiche un menu au démarrage.

## Développeur : passer de Windows à Linux (Ubuntu LTS)

1. Préparez une clé **Linux — Développement** (Ubuntu coché ; ajoutez Windows 11 si vous gardez un double
   démarrage).
2. Installez Ubuntu, puis `bash lancer.sh` : la stack développement est pré-cochée.
3. Récupérez votre environnement : clés SSH (`~/.ssh`), `~/.gitconfig`, extensions VS Code
   (`code --list-extensions` sous Windows, puis `code --install-extension …`), dépôts (`gh repo clone`).
4. Bureautique : Microsoft 365 web pour la fidélité, ONLYOFFICE en local, WinBoat si des macros sont
   indispensables.
5. Création : GIMP / Krita (Photoshop), Inkscape (Illustrator), Kdenlive ou DaVinci Resolve (montage),
   ou la suite ArtCraft quand elle sera mûre.
