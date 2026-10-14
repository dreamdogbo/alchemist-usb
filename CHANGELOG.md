# Journal des versions

Toutes les évolutions notables du projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet respecte
la [gestion sémantique de version](https://semver.org/lang/fr/) (`MAJEUR.MINEUR.CORRECTIF`).

## [Non publié]

### Corrigé

- Windows : l'assistant ne se lançait pas, sans aucun message (PowerShell démarré sans fenêtre). Nouveau
  lanceur `modules/Lanceur.ps1` : message clair et `logs\demarrage-*.log` si la fenêtre ne peut pas s'ouvrir
  (archive ZIP non extraite, PowerShell en mode restreint AppLocker/WDAC), fichiers du kit débloqués
  (marque « Internet »), un seul assistant ouvert à la fois. Dépannage : `Creer-Cle.bat -Console`.
- Windows : fenêtre figée au démarrage et à « Actualiser » quand un lecteur réseau déconnecté, un lecteur de
  CD ou un lecteur de cartes vide était présent : ces lecteurs ne sont plus interrogés.
- Ancienne clé Ventoy non reconnue quand le libellé de sa partition n'était pas exactement « Ventoy »
  (renommée, ou affichée « VENTOY » en FAT32) : la partition VTOYEFI du même disque suffit désormais.
- Clé neuve : « Le volume n'est pas prêt » juste après l'installation de Ventoy ; le kit attend que Windows
  ait monté la partition (jusqu'à 30 s) avant de la contrôler.
- Clé neuve sur une ancienne clé (ISO écrite en mode DD, partitions verrouillées, table abîmée) : quand
  Ventoy2Disk refuse le disque, la table de partitions est effacée puis l'installation est réessayée. Un
  disque hors ligne ou en lecture seule est remis en état ; une clé verrouillée par son interrupteur est
  signalée clairement.
- Ventoy2Disk bloqué (fenêtre d'erreur invisible) : arrêt après 20 min avec un message, au lieu d'une attente
  sans fin.
- Préparation lancée en administrateur (clé neuve) : `winget` introuvable, car c'est un alias propre à
  chaque utilisateur. Il est maintenant cherché dans le paquet App Installer.
- Autorisation administrateur refusée : message explicite au lieu d'une simple ligne d'erreur dans le journal.
- Téléchargements longs (ISO de plusieurs Go) abandonnés après 3 coupures réseau : une tentative qui a
  progressé n'est plus comptée, l'ISO finit par reprise.
- Proxy d'entreprise avec authentification Windows (erreur 407) : identifiants du poste transmis.
- Clé en FAT32 : l'ISO de Windows (plus de 4 Go) échouait après un long téléchargement ; le kit le signale
  avant de télécharger et explique comment réinstaller Ventoy en exFAT.

### Ajouté

- **Windows 10 22H2** (dernière version, ISO officielle Microsoft via Fido) proposé dans « Systèmes
  supplémentaires », décoché par défaut, pour les PC incompatibles avec Windows 11. Tous les logiciels de la clé
  et la post-installation fonctionnent aussi sous Windows 10 ; installation hors ligne Ventoy avec le même modèle.
  Lien vers la page officielle Microsoft sur l'écran de préparation ; un lien `-WindowsIsoUrl` collé à la main
  est attribué à la bonne version de Windows (`Win10_…` / `Win11_…`).
- **Images personnelles** (bouton « ISO personnelle… », `-IsoPersonnelle`) : Windows 7, 8.1 sous licence ou tout
  autre système copié dans `ISO/Personnel/`, avec vérification SHA256 de la copie ; jamais supprimé par le kit.
  Microsoft ne distribue plus Windows 7 : le kit ne propose aucune source non officielle.
- **Pack de compatibilité Windows 7** (dernières versions officielles encore compatibles) : .NET Framework 4.8,
  WMF 5.1 / PowerShell 5.1 (empreinte SHA256 fixée), Firefox ESR 115. Coché automatiquement quand une ISO de
  Windows 7 est ajoutée ; `Lancer.bat` détecte Windows 7/8.1 et ouvre ce pack avec son mode d'emploi
  (`postinstall\Windows7.txt`) au lieu d'échouer.
- Colonne « Windows » dans la liste : versions de Windows compatibles avec chaque logiciel ; conseil contextuel
  quand Windows 10 ou le pack Windows 7 est coché.
- Profils : champ `Compat` (versions de Windows prises en charge) et `Sha256` dans `Files` (fichier officiel figé
  et non signé).
- CI : l'assistant Windows est construit en FR et EN à chaque commit, captures publiées en artefact.
- Une seule préparation à la fois sur un poste (assistant ouvert deux fois, assistant et ligne de commande) :
  la seconde s'arrête avec un message au lieu d'écrire les mêmes fichiers de la clé en parallèle.
- Windows : mise en veille suspendue pendant la préparation (l'écran peut s'éteindre).
- Fin de préparation : cache d'écriture de la clé vidé avant d'annoncer « terminé ».

## [1.5.2] - 2026-10-12

### Corrigé

- Linux : « Pas d'accès à Internet » à tort sur Ubuntu de bureau, qui n'installe pas `curl` par défaut. Le
  script installe désormais `curl` (et `python3`, `gpg` si besoin) avant de vérifier la connexion, accepte
  toute réponse HTTP de trois sites, et affiche l'erreur réseau réelle en cas d'échec.

## [1.5.1] - 2026-10-12

### Corrigé

- Clé Linux préparée sous Windows : `lancer.sh` et `installer-poste.sh` échouaient (« $'\r' : commande
  introuvable », « env: 'bash\r' ») quand la copie du kit avait des fins de ligne Windows (Git pour Windows,
  `core.autocrlf`). Le dépôt impose désormais LF aux scripts Linux (`.gitattributes`) et Build-Kit les
  convertit en LF à la préparation de la clé, quelle que soit la copie du kit.

## [1.5.0] - 2026-10-12

### Ajouté

- Linux : composant `zram` (coché) : mémoire d'échange compressée en RAM (zstd, 50 % de la RAM, prioritaire).
- Linux : Timeshift configuré en **mode Btrfs** (5 instantanés quotidiens + 3 hebdomadaires) quand `/` est le
  sous-volume `@` ; sinon laissé à configurer. Une configuration existante est conservée.
- Linux sur Btrfs : disques de machines virtuelles sans copie à l'écriture (LinOffice, libvirt).
- Windows, profil développement : **Dev Drive** (ReFS) dans un VHDX dynamique sur `C:`, remonté à chaque
  démarrage, avec dossier `Projets` et caches npm, pip et NuGet ; ignoré si Windows, la RAM ou l'espace libre
  ne le permettent pas.
- Double démarrage : la post-installation Windows met l'horloge en UTC et désactive le démarrage rapide si un
  Linux est détecté ; la post-installation Linux rappelle ces réglages si Windows est présent.

## [1.4.2] - 2026-10-11

### Ajouté

- CI : Dependabot met à jour chaque semaine les actions GitHub épinglées par SHA (une PR groupée, préfixe `ci`).

## [1.4.1] - 2026-10-11

### Modifié

- CI : toutes les actions GitHub sont épinglées par SHA de commit (`actions/checkout` v5.1.0,
  `actions/upload-artifact` v4.6.2) ; règle ajoutée à CONTRIBUTING.md.

### Corrigé

- Linux : les commandes lancées pour l'utilisateur (Podman sans root de LinOffice, nvm, rustup, uv, Trivy)
  partent de son dossier personnel ; lancé depuis un dossier inaccessible à l'utilisateur (ex. /root),
  Microsoft 365 intégral échouait sur « cannot chdir … Permission denied ».
- Test Office 365 intégral (`test-linoffice.yml`) : réussit désormais de bout en bout (installation de Windows
  et d'Office, diagnostic, captures de Word, Excel et PowerPoint) ; ses étapes s'exécutent dans le dossier et
  avec la configuration de l'utilisateur de test.

## [1.4.0] - 2026-10-11

### Ajouté

- **Podman Desktop** (Apache 2.0) : interface graphique qui pilote le Docker Engine natif (`/var/run/docker.sock`)
  et Podman. Linux : composant `podmandesktop` (Flathub), coché pour le développement. Windows : éléments
  `Podman` (moteur, machine WSL 2) et `PodmanDesktop`.
- **Trivy** (Aqua Security) : scan des vulnérabilités des images et des dépendances, des secrets et des mauvaises
  configurations, SBOM. Linux : composant `trivy` (dépôt officiel, base pré-téléchargée). Windows : élément
  `Trivy` (archive portable installée dans `%ProgramFiles%\Alchemist\Trivy` et ajoutée au PATH).
- Post-installation Windows : prise en charge des outils en ligne de commande livrés en archive zip.
- Docker Engine : rotation des journaux des conteneurs (`/etc/docker/daemon.json` : `json-file`, 3 × 10 Mo,
  `live-restore`), écrit seulement s'il n'existe pas.
- CI : analyse Trivy du dépôt (secrets, mauvaises configurations), action officielle épinglée par SHA.
- Documentation : « Pourquoi Podman Desktop plutôt que Docker Desktop » et « Utiliser Trivy » (docs/STACK.md).

### Modifié

- **Docker Desktop décoché par défaut**, sous Linux comme sous Windows : machine virtuelle supplémentaire sous
  Linux, licence payante pour les administrations et les organisations de plus de 250 salariés ou 10 M$ de
  chiffre d'affaires. Il reste proposé en option.
- Test réel Linux : `podmandesktop` et `trivy` remplacent `dockerdesktop` ; le vérificateur contrôle Podman
  Desktop et Trivy, et Docker Desktop seulement s'il est installé.

### Corrigé

- Aide de `installer-poste.sh` : la ligne `set -Eeuo pipefail` n'apparaît plus dans `--aide`.

## [1.3.1] - 2026-10-10

### Ajouté

- Test **réel** de la stack Linux sur GitHub Actions (`test-reel-linux.yml`) : 27 composants installés,
  48 outils vérifiés, idempotence ; chaque lundi.
- Test Office 365 intégral (`test-linoffice.yml`) : KVM, Xvfb, captures de Word/Excel/PowerPoint ; mensuel.

### Corrigé

- LinOffice : Podman sans root fiabilisé (identifiants subordonnés, session systemd attendue, dossiers
  de configuration propres à l'utilisateur, écran transmis à FreeRDP).
- Vérificateur : les commandes vont jusqu'au bout (faux échec Docker).

## [1.3.0] - 2026-10-10

### Ajouté

- **Microsoft 365 de bureau intégral sous Linux** (composant `office365`, coché par défaut) : le vrai Word,
  Excel, PowerPoint, Outlook et OneNote via **LinOffice** (Windows minimal dockur/windows en conteneur Podman +
  KVM, affichage FreeRDP, applications dans le menu Linux). Vérification préalable de la virtualisation, de
  8 Go de RAM et de 64 Go libres ; installation automatique dans la session de l'utilisateur.

### Modifié

- Version web de Microsoft 365 et Microsoft Edge décochées par défaut (option conservée pour Teams, qui n'existe
  plus en version de bureau Linux) ; WinBoat présenté comme alternative pour les autres applications Windows.
- Documentation : la couche Wine/CrossOver ne fait plus fonctionner Microsoft 365 (janvier 2026) ; la voie
  stable est la virtualisation légère.

## [1.2.0] - 2026-10-10

Le projet devient **Alchemist** (dépôt `dreamdogbo/alchemist-usb`, ancien nom redirigé).

### Ajouté

- Parcours **Système → Usage → Versions → Clé** : profils Windows / Linux × Bureautique / Développement,
  avec **héritage** de profils (module `Profile.psm1`), paramètres `-Systeme` / `-Usage`.
- Profil **Windows 11 — Développement** : VS Code, PowerShell 7, PowerToys, Git, GitHub CLI, WSL 2 (MSI officiel),
  Docker Desktop, Python, Node.js LTS, Java Temurin 25, .NET SDK 10, Go, Rust, Bruno, DBeaver, Postman, KeePassXC.
- Profils **Linux** (Ubuntu LTS par défaut, Ubuntu 24.04, Linux Mint, Debian, Fedora, Windows 11 en option)
  avec choix d'une version précise d'Ubuntu (`Series`).
- **Post-installation Linux multi-distributions** (`linux/installer-poste.sh` + assistant `linux/lancer.sh`) :
  familles apt et dnf, 35 composants, dépôts officiels, simulation, journal, bilan. Microsoft 365 en applications
  web, ONLYOFFICE, WinBoat, Docker Engine + Desktop, KVM, langages, DevOps, création.
- Catégorie **Création** (GIMP, Inkscape, Krita, Kdenlive, OBS, Audacity) et **suite ArtCraft** (PhotoCraft,
  VectorCraft, FilmCraft, LightCraft, EffectCraft, DesignCraft) sous Windows et Linux.
- **Alchemist sous Linux** : moteur PowerShell 7 multiplateforme (clé par point de montage `-KeyPath`,
  Ventoy via `Ventoy2Disk.sh`), assistant `creer-cle.sh` (zenity).
- Zone de téléchargement **sur la clé** par défaut (`kit-cache`) : rien de lourd sur l'ordinateur.
- `-ListerProfils -Json` et `-ListerElements` pour les assistants et scripts.
- Documentation de la stack : `docs/STACK.md`.
- CI : tests Linux dans GitHub Actions (shellcheck, moteur sous Linux, simulation Ubuntu 26.04/24.04, Debian 13,
  Fedora, Linux Mint).

### Modifié

- Assistant Windows : sélection Système / Usage, conseils adaptés au système, nouveau titre.
- Post-installation Windows : activation des fonctionnalités WSL 2 pour Docker Desktop.

## [1.1.0] - 2026-10-10

### Ajouté

- Installation de Ventoy sur une clé neuve depuis l'assistant ou `-InstallerVentoy -Disque N` : release
  officielle `ventoy/Ventoy` (SHA256 vérifié), ligne de commande officielle, puis préparation du contenu en une
  seule opération.
- Mise à jour de Ventoy sans effacement (`-MettreAJourVentoy` / case de l'assistant).
- Garde-fous : disques USB/SD uniquement, jamais le disque système ni celui du kit, confirmation tapée,
  droits administrateur, sauvegarde préalable de toutes les partitions du disque.
- Libellé « Système (menu Ventoy) » pour les ISO dans l'assistant.

### Remarque

- Garde-fous et téléchargement de Ventoy testés ; l'installation réelle sur une clé sera validée lors du test
  de la clé Linux.

## [1.0.0] - 2026-10-10

Première version stable : clé Windows 11 complète, installable hors ligne.

### Ajouté

- Assistant graphique de création de clé (`Creer-Cle.bat`) : profils, langue du système, détection
  automatique de la clé Ventoy, cases à cocher, simulation, journal en direct, sauvegarde préalable.
- Assistant graphique du poste (`postinstall\Lancer.bat`) : état de chaque logiciel, installation
  sélective, nom du poste, réglages, pilotes (SDIO), outils portables, « Compléter la clé (Internet) ».
- Thème visuel commun (bandeau, icônes d'état, boutons modernes) et signature de l'auteur.
- Interface multilingue (français, anglais) par fichiers `lang\*.psd1` ; contenu multilingue
  (`-Langue fr|en|es|de|pt` : ISO Windows, Office, clavier d'installation).
- Profil `windows11-bureautique` : Windows 11, Microsoft 365 Apps hors ligne ou LibreOffice / ONLYOFFICE,
  runtimes, navigateurs, PDF (Acrobat Reader, PDF24, PDFCraft), utilitaires, Teams, Zoom,
  Chocolatey + Chocolatey GUI, antivirus ClamAV (analyse à la demande, configuré automatiquement),
  outils technicien (SDIO, CrystalDiskInfo, HWiNFO).
- Multiboot optionnel : Ubuntu LTS, Linux Mint, Debian, Fedora (dernière version stable, SHA256 officiel).
- Sources GitHub : dernière release stable, contrôle du `digest` SHA256 publié.
- Vérification Authenticode désactivable (`-SansVerifSignature`).
- Sauvegarde des données de la clé avant préparation (`-SauvegardeVers`, `-SauvegardeComplete`).
- Modèle d'installation Windows hors ligne (compte local) proposé par Ventoy.
- Idempotence (MANIFEST.sha256), reprise des téléchargements, budget d'espace par priorité.
- Conservation de l'ISO Windows présente sur la clé si Microsoft bloque temporairement Fido.
- Pilotes : liens officiels validés par fabricant (Dell, HP, Lenovo, ASUS, Acer, MSI, Surface) et par
  composant (Intel, AMD, NVIDIA), fabricant détecté automatiquement ; menu « Pilotes » de l'assistant.
- Rejet des pages web renvoyées à la place d'un fichier (miroirs, captchas).
- Version unique (`VERSION`) affichée dans les fenêtres, les journaux et sur la clé.
- Intégration continue : PSScriptAnalyzer, syntaxe PowerShell 5.1, lecture des profils et langues.

[Non publié]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.5.2...HEAD
[1.5.2]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.4.2...v1.5.0
[1.4.2]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/dreamdogbo/alchemist-usb/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/dreamdogbo/alchemist-usb/releases/tag/v1.0.0
