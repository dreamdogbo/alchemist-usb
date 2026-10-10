# Feuille de route

Objectif : **une seule clé, un seul assistant** pour préparer n'importe quel poste — Windows ou Linux —
selon **le système**, **l'usage** et **le profil de l'utilisateur**, avec une attention particulière aux
développeurs qui passent de Windows à Linux.

Les versions suivent [SemVer](https://semver.org/lang/fr/) ; l'avancement réel est consigné dans le
[CHANGELOG](CHANGELOG.md).

---

## v1.1 — La clé de A à Z

- [x] **Installer Ventoy** sur une clé vierge depuis l'assistant (release officielle `ventoy/Ventoy`,
      SHA256 vérifié, ligne de commande officielle `Ventoy2Disk VTOYCLI`), puis préparer le contenu
      **en une seule opération**.
- [x] **Mettre à jour Ventoy** sur une clé existante sans effacer les données (mode *Update*).
- [x] Garde-fous : disques USB uniquement, jamais le disque système, confirmation tapée, sauvegarde proposée.
- [ ] Menu Ventoy lisible (`menu_alias`) : « Windows 11 (FR) », « Ubuntu 26.04 LTS »…

## v1.2 — Profils par usage (Windows)

L'assistant demande **qui** va utiliser le poste et **pour quoi faire** :

| Profil | Contenu ajouté |
| --- | --- |
| Bureautique | profil actuel |
| Développement | VS Code, Git, Windows Terminal, PowerShell 7, Python, Node.js LTS, Go, Rust (rustup), JDK LTS, Docker Desktop, WSL 2 + Ubuntu, Postman/Bruno, DBeaver, JetBrains Toolbox |
| Statistiques / données | R + RStudio, Python (Anaconda/Miniforge), Jupyter, JASP, PSPP, QGIS, Power BI Desktop |
| Graphisme / vidéo | Inkscape, GIMP, Krita, Blender, Kdenlive, DaVinci Resolve, OBS Studio, Audacity, HandBrake |

## v2.0 — Outil universel (Windows, Linux, macOS)

Le kit doit pouvoir **créer une clé depuis n'importe quel système** :

- [ ] Moteur commun en **PowerShell 7** (déjà multiplateforme) ; les parties propres à Windows (winget, Fido,
      WinForms, Authenticode) deviennent des *fournisseurs* interchangeables.
- [ ] Ventoy : `Ventoy2Disk.exe` sous Windows, `Ventoy2Disk.sh` sous Linux (même logique de garde-fous).
- [ ] Interface graphique multiplateforme (Avalonia UI ou interface web locale) remplaçant WinForms ;
      la ligne de commande reste identique partout.
- [ ] Téléchargements Windows depuis Linux : liens officiels directs (Microsoft, éditeurs, GitHub) quand winget
      n'est pas disponible.

## v2.x — Linux de première classe (priorité : bascule Windows → Linux)

### Installation automatisée

- [ ] Choix **Ubuntu LTS** (recommandé), Fedora Workstation ou Linux Mint, installés en automatique par
      Ventoy (Ubuntu *autoinstall* / cloud-init, Fedora *kickstart*), avec un compte et une langue choisis.
- [ ] Script de post-installation Linux (`postinstall-linux/install.sh`) équivalent à `Install-Poste.ps1` :
      profils, détection de l'existant, journal, bilan ; paquets **apt/dnf + Flatpak (Flathub)**.
- [ ] Mode hors ligne : paquets `.deb`/`.rpm` et bundles Flatpak embarqués sur la clé, comme pour Windows.

### Profil « Développeur Linux »

| Besoin | Outils |
| --- | --- |
| Éditeurs / IDE | VS Code (dépôt Microsoft), JetBrains Toolbox, Neovim |
| Conteneurs | **Docker Engine + Compose** (dépôt officiel Docker) ou **Docker Desktop for Linux**, Podman, Portainer |
| Langages | Python (pyenv/uv), Node.js LTS (nvm/fnm), Go, Rust (rustup), JDK LTS (SDKMAN), .NET SDK |
| Outils | Git, GitHub CLI, zsh + Oh My Zsh, tmux, kubectl, Helm, Terraform, Ansible, AWS/Azure/GCP CLI |
| Bases de données | DBeaver, PostgreSQL/MySQL en conteneurs |
| API | Bruno, Postman |

### Microsoft 365 sous Linux

Office n'existe pas en version native Linux. Solutions proposées, de la plus simple à la plus complète :

1. **Microsoft 365 web** installé en applications (PWA Edge/Chrome) : Word, Excel, PowerPoint, Outlook, Teams —
   fidélité totale des documents, nécessite Internet.
2. **Suites compatibles natives** : **ONLYOFFICE** (meilleure compatibilité .docx/.xlsx/.pptx), LibreOffice,
   WPS Office.
3. **Office de bureau complet dans une VM Windows intégrée** : **WinApps** / **WinBoat** (open source) lancent
   Word, Excel, PowerPoint comme des applications Linux (Windows en conteneur Docker/KVM, licence Office requise).

### Équivalents des logiciels Windows / Adobe

| Usage | Équivalents Linux |
| --- | --- |
| PDF (Acrobat) | **PDFCraft** (AppImage / Flatpak), Okular, Xournal++, PDF Arranger |
| Illustrator | **Inkscape** |
| Photoshop | **GIMP**, **Krita**, Photopea (web) |
| InDesign | Scribus |
| Lightroom | darktable, RawTherapee |
| Premiere / montage vidéo | **Kdenlive**, **DaVinci Resolve** (natif Linux), Shotcut |
| After Effects | Natron, Blender (compositing) |
| Enregistrement / streaming | OBS Studio |
| Audio | Audacity, Ardour |
| 3D | Blender |

## v2.1 — Assistant de migration Windows → Linux

- [ ] Sauvegarde et transfert des **données utilisateur** (Documents, Bureau, Images, navigateurs).
- [ ] Reprise des **outils de développement** : clés SSH, `.gitconfig`, dépôts, extensions VS Code
      (`code --list-extensions`), variables d'environnement.
- [ ] Liste des logiciels Windows installés → **proposition d'équivalents Linux** (table ci-dessus).
- [ ] Double démarrage (dual boot) assisté ou installation Linux seule.

## Plus tard

- Autres langues d'interface (ES, DE, PT, AR…) et traduction des journaux techniques.
- Packs de pilotes hors ligne sélectifs (réseau, chipset) pour SDIO.
- Persistance Ventoy pour les systèmes Linux « live ».
- Interface multiplateforme (créer la clé depuis Linux).
