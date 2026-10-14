# ⚗️ Alchemist — transformez un PC nu en poste prêt à l'emploi

[![Version](https://img.shields.io/github/v/release/dreamdogbo/alchemist-usb?label=version)](https://github.com/dreamdogbo/alchemist-usb/releases)
[![Analyse PowerShell](https://github.com/dreamdogbo/alchemist-usb/actions/workflows/lint.yml/badge.svg)](https://github.com/dreamdogbo/alchemist-usb/actions/workflows/lint.yml)
[![Tests Linux](https://github.com/dreamdogbo/alchemist-usb/actions/workflows/tests-linux.yml/badge.svg)](https://github.com/dreamdogbo/alchemist-usb/actions/workflows/tests-linux.yml)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
[![SemVer](https://img.shields.io/badge/versioning-SemVer-brightgreen.svg)](https://semver.org/lang/fr/)
[![Conventional Commits](https://img.shields.io/badge/commits-Conventional-yellow.svg)](https://www.conventionalcommits.org/fr/)

> Une clé USB **Ventoy**, un assistant, et n'importe quel PC devient un poste **Windows 11** ou **Linux**
> (Ubuntu LTS, Linux Mint, Debian, Fedora) complet : système, bureautique, outils de développement,
> pilotes et réglages. Pensé pour les techniciens, les mainteneurs et les développeurs.

**by [dreamdogbo](https://github.com/dreamdogbo)** · Windows et Linux · PowerShell 7 / Windows PowerShell 5.1 · 🇫🇷 Français · 🇬🇧 [English](#english-summary)

![Assistant Alchemist](docs/assistant-cle-fr.png)

---

## Sommaire

- [En 30 secondes](#en-30-secondes)
- [Le parcours : Système → Usage → Versions → Clé](#le-parcours--système--usage--versions--clé)
- [Démarrage rapide — Windows](#démarrage-rapide--windows)
- [Démarrage rapide — Linux](#démarrage-rapide--linux)
- [Sur le poste à installer](#sur-le-poste-à-installer)
- [La stack](#la-stack)
- [Ligne de commande](#ligne-de-commande)
- [Sécurité et intégrité](#sécurité-et-intégrité)
- [Personnaliser](#personnaliser)
- [Architecture](#architecture)
- [Versions et méthode de travail](#versions-et-méthode-de-travail)
- [Feuille de route](#feuille-de-route)
- [Limites connues](#limites-connues)
- [English summary](#english-summary)

## En 30 secondes

| | |
| --- | --- |
| 🧭 **Choix guidé** | Système (Windows / Linux) → usage (bureautique / développement) → versions → clé |
| 🪟 **Windows 11** | ISO officielle (FR, EN, ES, DE, PT), Microsoft 365 hors ligne **ou** LibreOffice / ONLYOFFICE, logiciels, **installation 100 % hors ligne** |
| 🐧 **Linux** | Ubuntu LTS (recommandé), Linux Mint, Debian, Fedora — stack bureautique ou développeur via les dépôts officiels |
| 👩‍💻 **Développeurs** | VS Code, Git + GitHub CLI, Docker Engine natif + Podman Desktop, Trivy (scan de sécurité), WSL 2, Python/uv, Node.js LTS, Java, .NET, Go, Rust, Bruno, DBeaver… |
| 📄 **Microsoft 365 sous Linux** | **version de bureau intégrale** (vrai Word, Excel, PowerPoint, Outlook, OneNote) via LinOffice, + ONLYOFFICE |
| 🎨 **Création** | GIMP, Inkscape, Krita, Kdenlive, OBS… et la suite open source ArtCraft (PhotoCraft, VectorCraft, FilmCraft…) |
| 🔌 **Clé de A à Z** | installe / met à jour **Ventoy** lui-même (option, garde-fous), puis tout le reste en une fois |
| 🖥️ **Partout** | crée la clé depuis **Windows** (`Creer-Cle.bat`) ou **Linux** (`creer-cle.sh`) |
| 🛡️ **Sûr** | sources officielles, SHA256 vérifiés, signatures contrôlées, clé jamais formatée sans confirmation tapée |
| ♻️ **À jour** | relancer = mise à jour : seules les nouvelles versions sont téléchargées |

**Le dépôt ne contient aucun logiciel** : seulement des scripts (quelques centaines de Ko). Tout est
téléchargé au moment où vous préparez une clé, depuis les sources officielles, en dernière version stable.

## Le parcours : Système → Usage → Versions → Clé

1. **Système** : Windows ou Linux.
2. **Usage** : bureautique ou développement (détermine la stack proposée).
3. **Versions** : cases à cocher — Windows 11 dans la langue choisie ; pour Linux, Ubuntu LTS (dernière et
   précédente), Linux Mint, Debian, Fedora, et même Windows 11 pour un double démarrage.
4. **Clé** : une clé Ventoy détectée automatiquement, **ou une clé neuve** sur laquelle Alchemist installe
   Ventoy (après confirmation tapée).

## Démarrage rapide — Windows

Prérequis : Windows 10/11 avec Internet, [winget](https://learn.microsoft.com/windows/package-manager/winget/)
(présent par défaut sur Windows 11), une clé USB de 32 Go ou plus.

```powershell
git clone https://github.com/dreamdogbo/alchemist-usb.git
```

ou téléchargez l'archive de la [dernière version](https://github.com/dreamdogbo/alchemist-usb/releases), puis
**double-cliquez `Creer-Cle.bat`**. Cochez « Clé neuve : installer Ventoy » si la clé n'a pas encore Ventoy.

**Si la fenêtre ne s'ouvre pas** : un message indique la cause (archive non extraite, PowerShell restreint par
l'entreprise…) et le détail est dans `logs\demarrage-*.log`. Pour voir toutes les erreurs, lancez
`Creer-Cle.bat -Console` depuis une invite de commandes. Une **ancienne clé** que Ventoy refuse (ISO écrite
avec Rufus en mode DD, partitions verrouillées, disque en lecture seule) est remise à zéro puis réessayée
automatiquement en mode « Clé neuve ».

## Démarrage rapide — Linux

Prérequis : PowerShell 7 (proposé automatiquement : `sudo snap install powershell --classic`), `zenity`.

```bash
git clone https://github.com/dreamdogbo/alchemist-usb.git && cd alchemist-usb
bash creer-cle.sh
```

Depuis Linux, on prépare les clés **Linux** (avec Windows 11 en option). Les clés Windows complètes
(Microsoft 365 hors ligne, logiciels winget) se préparent depuis Windows.

## Sur le poste à installer

**Windows** — démarrer sur la clé, choisir l'ISO Windows 11 puis le modèle `Windows11_HorsLigne.xml`
(compte local sans Internet), puis sur le bureau : **`postinstall\Lancer.bat`**.

![Assistant du poste](docs/assistant-poste-fr.png)

**Linux** — démarrer sur la clé, choisir la distribution, installer, puis dans le dossier `linux` de la clé :
`bash lancer.sh` (fenêtre de choix des logiciels, Internet requis).

## La stack

Résumé ci-dessous ; le détail complet est dans **[docs/STACK.md](docs/STACK.md)**.

| | Bureautique | Développement (en plus) |
| --- | --- | --- |
| **Windows** | Microsoft 365 / LibreOffice / ONLYOFFICE, Chrome, Firefox, Acrobat Reader, PDF24, PDFCraft, 7-Zip, VLC, Notepad++, ShareX, Teams, Zoom, Chocolatey + GUI, ClamAV | VS Code, PowerShell 7, PowerToys, Git, GitHub CLI, WSL 2, Podman + Podman Desktop, Trivy, Python, Node.js LTS, Java, .NET SDK, Bruno, DBeaver, KeePassXC |
| **Linux** | **Microsoft 365 de bureau intégral (LinOffice)**, ONLYOFFICE, LibreOffice, Chrome, PDFCraft, Okular, Zoom, polices Office, ClamAV, pare-feu, Timeshift | VS Code, Git + gh + lazygit, Docker Engine + Podman Desktop, Trivy, KVM, Python + uv, Node.js LTS, Java, .NET, Go, Rust, Bruno, DBeaver, outils terminal |
| **Options** | Création (GIMP, Inkscape, Krita, Kdenlive, OBS…), suite ArtCraft, WinBoat (autres applications Windows), DevOps, JetBrains Toolbox, Docker Desktop (licence payante en entreprise/administration) | |

## Ligne de commande

```powershell
# Windows ou Linux (PowerShell 7)
./Build-Kit.ps1 -Systeme Windows -Usage Developpement -DryRun     # simulation
./Build-Kit.ps1 -Systeme Linux -Usage Developpement -Avec LinuxMint
./Build-Kit.ps1 -Systeme Windows -Usage Bureautique -SansOffice -Avec LibreOffice -Langue en
./Build-Kit.ps1 -InstallerVentoy -Disque 2 -ConfirmerEffacement EFFACER-2                  # Windows : clé neuve
sudo pwsh ./Build-Kit.ps1 -Systeme Linux -InstallerVentoy -Disque /dev/sdb -ConfirmerEffacement EFFACER-sdb
./Build-Kit.ps1 -MettreAJourVentoy                                # Ventoy à jour, données conservées
./Build-Kit.ps1 -ListerProfils
```

| Paramètre | Rôle |
| --- | --- |
| `-Systeme Windows\|Linux` `-Usage Bureautique\|Developpement` | choix du profil (ou `-Profil <nom>`) |
| `-Langue fr\|en\|es\|de\|pt` | langue de l'ISO Windows, d'Office et du clavier |
| `-Only a,b` / `-Avec a,b` / `-SansOffice` | sélection exacte / ajout d'options / sans Microsoft 365 |
| `-DriveLetter E` (Windows) / `-KeyPath /media/moi/Ventoy` (Linux) | clé (sinon détection automatique) |
| `-InstallerVentoy -Disque … -ConfirmerEffacement EFFACER-…` | clé neuve : installe Ventoy (efface le disque), options `-VentoyGPT`, `-VentoyFS`, `-VentoySansSecureBoot` |
| `-MettreAJourVentoy` | met Ventoy à jour sans effacer |
| `-DryRun`, `-SkipDownload` | simulation ; mise en place hors ligne depuis le cache |
| `-SansVerifSignature` | Authenticode non exigé (les SHA256 publiés restent vérifiés) |
| `-SauvegardeVers <dossier>` `[-SauvegardeComplete]` | sauvegarde préalable des données de la clé |
| `-WindowsIsoUrl <url>` | lien officiel Microsoft si Fido est bloqué |
| `-ListerProfils [-Json]`, `-ListerElements` | informations pour scripts et assistants |

Codes de sortie : `0` OK · `1` au moins un ÉCHEC · `2` erreur / clé invalide · `3` source officielle du système ou d'Office introuvable.

Post-installation Linux : `installer-poste.sh -u bureautique|developpement [-c id1,id2] [-t] [-n] [-y] [--liste]`.
Post-installation Windows : `Install-Poste.ps1 [-Logiciels a,b] [-AvecOutils] [-SansOffice] [-NomPoste X] [-SansReglages]`.

## Sécurité et intégrité

- **Sources officielles uniquement** : Microsoft, éditeurs, dépôt winget, releases GitHub stables, sites des
  distributions, dépôts apt/dnf officiels, Flathub. **Aucune ISO modifiée, aucun outil d'activation** :
  licences légitimes uniquement.
- **SHA256** publiés (winget, GitHub, distributions, Go) toujours vérifiés ; `MANIFEST.sha256` permet de
  vérifier toute la clé (`sha256sum -c MANIFEST.sha256`).
- **Signatures Authenticode** contrôlées sous Windows (désactivables, tracé dans le journal).
- **Préparer ou mettre à jour une clé ne la formate jamais** ; seuls les fichiers du kit sont modifiés.
- **Clé neuve (option)** : USB/SD uniquement, jamais le disque système ni celui où se trouve Alchemist,
  confirmation tapée, droits administrateur, sauvegarde proposée.
- **Rien de lourd sur votre ordinateur** : la zone de téléchargement est **sur la clé** (`kit-cache`).

## Personnaliser

- **Logiciel Windows** : un bloc dans `config/profils/windows11-*.psd1` (types `Winget`, `GitHub`, `Url`).
- **Composant Linux** : une ligne dans `COMPOSANTS` et une fonction `comp_<id>` dans
  `payload/linux/linux/installer-poste.sh` (helpers `paquets "deb" "rpm"`, `flatpak_installer`, `github_paquet`).
- **Nouveau profil** : un fichier dans `config/profils/` ; il peut **hériter** d'un autre (`Herite`, `Items`,
  `Retirer`, `ParDefaut`, `NonParDefaut`).
- **Langue d'interface** : copier `lang/fr.psd1` (et `payload/windows/postinstall/lang/fr.psd1`) en `xx.psd1`.

## Architecture

```text
alchemist-usb/
├── Creer-Cle.bat / Assistant.ps1     assistant Windows (fenêtre) ; modules/Lanceur.ps1 : contrôles de démarrage
├── creer-cle.sh                      assistant Linux (zenity)
├── Build-Kit.ps1                     moteur (Windows et Linux, PowerShell 7 / 5.1)
├── config/profils/*.psd1             profils Système × Usage (héritage)
├── modules/                          Drive, Ventoy, Profile, Budget, Download, Sync, Backup, Report
├── payload/windows/                  copié sur les clés Windows (post-installation, LISEZMOI, Ventoy)
├── payload/linux/                    copié sur les clés Linux (linux/lancer.sh, installer-poste.sh)
├── lang/                             textes des assistants (FR, EN…)
├── tests/linux/                      tests des scripts Linux (exécutés dans GitHub Actions)
└── docs/                             STACK.md, captures
```

## Versions et méthode de travail

- **Versions** : [SemVer](https://semver.org/lang/fr/), source unique [`VERSION`](VERSION) ;
  historique dans le [CHANGELOG](CHANGELOG.md) (Keep a Changelog).
- **Développement** : GitHub Flow (`main` stable, branches `feat/…`, Pull Requests), commits
  [Conventional Commits](https://www.conventionalcommits.org/fr/), CI (PSScriptAnalyzer, shellcheck, simulation
  sur Ubuntu / Debian / Fedora / Mint), publication automatique à chaque étiquette `vX.Y.Z`.
- Détails : [CONTRIBUTING](CONTRIBUTING.md) · Sécurité : [SECURITY](SECURITY.md) · Évolutions : [ROADMAP](ROADMAP.md).

## Feuille de route

- [x] Windows 11 hors ligne, Microsoft 365 ou suites gratuites, assistants FR/EN (v1.0)
- [x] Installation / mise à jour de Ventoy (v1.1)
- [x] Système × usage, Linux multi-distributions, stack développeur, création de clé depuis Linux (v1.2)
- [ ] Installation Linux automatisée (autoinstall / kickstart), paquets Linux hors ligne sur la clé
- [ ] Profils statistiques / données et graphisme
- [ ] Assistant de migration Windows → Linux (données, SSH, Git, extensions VS Code)

Détails : [ROADMAP.md](ROADMAP.md).

## Limites connues

- **Fido** : Microsoft bloque parfois les téléchargements automatisés → lien officiel (`-WindowsIsoUrl`) ou ISO
  déposée dans le cache ; une ISO déjà sur la clé est conservée.
- **Post-installation Linux** : en ligne (dépôts officiels) ; l'installation hors ligne viendra plus tard.
- **Compte local Windows hors ligne** : Microsoft durcit l'OOBE ; repli `Maj+F10` → `start ms-cxh:localonly`.
- La suite **ArtCraft** est encore jeune (versions 0.x) : proposée en option.
- **Clé en FAT32** : aucun fichier de 4 Go ou plus (ISO de Windows) ; le kit le signale avant de télécharger.
  Réinstallez Ventoy en exFAT (case « Clé neuve »).

---

## English summary

**Alchemist** turns a bare PC into a ready-to-use **Windows 11** or **Linux** (Ubuntu LTS, Mint, Debian, Fedora)
workstation from a single **Ventoy** USB key. Pick the **system**, the **usage** (office / development) and the
**versions**; Alchemist downloads everything from official sources (latest stable, SHA256-verified), can install
Ventoy itself, and works from **Windows** (`Creer-Cle.bat`) or **Linux** (`creer-cle.sh`). Windows keys install fully
**offline**; Linux keys install the stack from official repositories (VS Code, native Docker Engine + Podman Desktop,
Trivy, Git/gh, Python/uv, Node.js, Java, .NET, Go, Rust, full desktop Microsoft 365 via LinOffice, ONLYOFFICE…). See [docs/STACK.md](docs/STACK.md).
Docker Desktop is no longer checked by default (paid licence for public sector and large organisations; extra VM
on Linux): Podman Desktop drives the native Docker Engine and Podman instead. No activation tools: legitimate licences only.

---

Conçu et maintenu par **[dreamdogbo](https://github.com/dreamdogbo)** · Contributions bienvenues : [CONTRIBUTING.md](CONTRIBUTING.md).
