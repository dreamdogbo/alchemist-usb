# Journal des versions

Toutes les évolutions notables du projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet respecte
la [gestion sémantique de version](https://semver.org/lang/fr/) (`MAJEUR.MINEUR.CORRECTIF`).

## [Non publié]

### Prévu

- Profils par usage : bureautique, développement, statistiques (Windows et Linux).
- Mise à jour de Ventoy sur la clé depuis la release officielle vérifiée (mode *Update*, sans effacement).
- Noms lisibles dans le menu Ventoy (`menu_alias`) et persistance pour les systèmes Linux.

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

[Non publié]: https://github.com/dreamdogbo/kit-ventoy/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/dreamdogbo/kit-ventoy/releases/tag/v1.0.0
