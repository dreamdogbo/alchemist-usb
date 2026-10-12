# Proposition — Partitionnement selon le disque, l'usage et le système

> **Statut : proposition à discuter** — rien n'est implémenté. Aujourd'hui, Alchemist ne partitionne
> jamais le disque du poste : le technicien choisit le disque et la disposition dans l'installateur
> officiel (Windows « Personnalisée », installateur de la distribution Linux).

## 1. Objectifs et garde-fous

**Objectif** : proposer, pour chaque combinaison **système** (Windows, Linux, double démarrage) ×
**usage** (bureautique, développement) × **taille de disque**, une disposition éprouvée, appliquée
automatiquement si le technicien le demande, et documentée sinon.

**Garde-fous (non négociables)** :

1. **Le mode manuel reste le défaut.** Le mode automatique est une option explicite, à la préparation
   de la clé **et** au démarrage du poste.
2. **Disque vide uniquement** par défaut : si le disque cible contient déjà des partitions, l'installation
   automatique s'arrête. L'effacement d'un disque non vide exige un choix distinct « EFFACER le disque »
   dans le menu Ventoy, plus une confirmation tapée (même logique que `-ConfirmerEffacement`).
3. **Jamais la clé Ventoy, jamais un disque USB** comme cible ; un seul disque interne pris en compte
   (le plus petit disque NVMe/SATA non amovible, affiché avant effacement).
4. **ISO officielles non modifiées** : seuls des fichiers de réponse (unattend, autoinstall, kickstart,
   preseed) et des scripts injectés par les plugins Ventoy sont utilisés.

## 2. Classes de disque

Les tailles sont celles annoncées par le fabricant (un disque « 256 Go » offre ≈ 238 Gio).

| Classe | Taille | Windows seul | Linux seul | Double démarrage | Microsoft 365 intégral sous Linux (LinOffice, 64 Go) |
| --- | --- | :-: | :-: | :-: | :-: |
| **XS** | < 128 Go | ● | ● | ✗ refusé | ✗ refusé |
| **S** | 128 – 255 Go | ● | ● | ✗ refusé | ⚠ déconseillé (≈ 60 Go restants) |
| **M** | 256 – 511 Go | ● | ● | ● | ● (Linux seul) · ✗ en double démarrage |
| **L** | 512 Go – 1 To | ● | ● | ● | ● |
| **XL** | > 1 To ou 2ᵉ disque | ● | ● | ● | ● |

Budget indicatif d'un poste installé (hors données) : système 25–40 Go ; stack bureautique +10 Go ;
stack développement +30–60 Go (Flatpak, SDK, images de conteneurs) ; LinOffice 64 Go ; WSL 2 + Podman
sous Windows 20–40 Go.

## 3. Windows 11 seul

Disposition GPT/UEFI recommandée par Microsoft, avec deux ajustements :

- partition **EFI de 260 Mo** (au lieu de 100 Mo, compatible disques 4K natifs) ;
- partition de récupération **WinRE de 1 Go placée après `C:`** : marge pour les mises à jour de WinRE
  (des partitions trop petites ont fait échouer la mise à jour KB5034441 en 2024).

| Classe | Bureautique | Développement |
| --- | --- | --- |
| XS · S | EFI 260 Mo · MSR 16 Mo · **C: (tout)** · WinRE 1 Go | EFI · MSR · **C: (tout)** · WinRE · *Dev Drive en VHDX dynamique de 64 Go* |
| M | EFI · MSR · **C: (tout)** · WinRE | EFI · MSR · **C: 200 Go** · WinRE · **D: Dev Drive (ReFS, reste)** |
| L | EFI · MSR · **C: 200 Go** · WinRE · **D: Données (NTFS, reste)** | EFI · MSR · **C: 250 Go** · WinRE · **D: Dev Drive (ReFS, reste)** |
| XL | EFI · MSR · **C: 250 Go** · WinRE · **D: Données (reste)** | EFI · MSR · **C: 300 Go** · WinRE · **D: Dev Drive 300 Go** · **E: Données (reste)** |

Pourquoi :

- **Bureautique** : une partition `D: Données` (à partir de 512 Go) permet de réinstaller Windows sans
  toucher aux documents ; en dessous, un seul `C:` évite de « bloquer » de l'espace, et OneDrive
  protège les dossiers.
- **Développement** : un **Dev Drive** (ReFS, Windows 11 22H2+) accélère Git, npm, NuGet, Maven, etc.,
  et Microsoft Defender l'analyse en mode performance. `C:` reste large car **WSL 2 et la machine
  Podman** stockent leurs disques virtuels dans le profil de l'utilisateur.
- **Chiffrement** : BitLocker (ou chiffrement de l'appareil) recommandé sur les portables ; la clé de
  récupération doit être sauvegardée (compte local : impression ou fichier, pas de compte Microsoft).

## 4. Linux seul

Une seule disposition, valable pour toutes les tailles, grâce à **Btrfs** et ses sous-volumes : pas de
taille fixe pour `/` et `/home`, qui partagent tout l'espace.

| Partition | Taille | Rôle |
| --- | --- | --- |
| EFI (FAT32) | 1 Go | chargeurs, micrologiciels (fwupd), plusieurs noyaux |
| `/boot` (ext4) | 2 Go | **seulement si chiffrement LUKS** |
| Btrfs (éventuellement dans LUKS2) | reste | sous-volumes ci-dessous |

| Sous-volume | Point de montage | Instantanés Timeshift | Remarque |
| --- | --- | :-: | --- |
| `@` | `/` | ● | |
| `@home` | `/home` | ● (option) | |
| `@docker` | `/var/lib/docker` | — | développement : images et conteneurs exclus des instantanés |
| `@swap` | `/swap` | — | fichier d'échange (sans copie à l'écriture) |
| — | `~/.local/share/containers` | — | LinOffice : dossier en `chattr +C` (disque virtuel de Windows sans copie à l'écriture) |

- **Timeshift** (installé par le composant `sauvegarde`) passe en **mode Btrfs** : instantanés immédiats
  et sans coût d'espace, possibles uniquement avec la convention `@` / `@home`.
- **Échange** : fichier de 4 Go (RAM ≥ 16 Go) à 8 Go (RAM < 16 Go) ; Fedora garde **zram**. Pas
  d'hibernation (souvent bloquée par Secure Boot).
- **Bureautique et développement** : même disposition ; seul `@docker` s'ajoute en développement.
- **Chiffrement LUKS2** : proposé (coché pour les portables) ; la phrase secrète est demandée à
  l'installation.

## 5. Double démarrage (Windows + Linux)

Windows est installé en premier, Linux ensuite sur l'espace laissé libre. **Une seule partition EFI**
(1 Go, créée par le scénario Windows du kit), partagée.

| Classe | Windows principal | Linux principal |
| --- | --- | --- |
| M (256 – 511 Go) | Windows 60 % · Linux 40 % | Windows 120 Go · Linux reste |
| L (512 Go – 1 To) | Windows 60 % · Linux 40 % (min. 200 Go) | Windows 200 Go · Linux reste |
| XL | Windows 50 % · Linux 50 % · *option : partition d'échange NTFS « Partage » 10 %* | idem |

Réglages appliqués par les post-installations (indispensables en double démarrage) :

- Windows : **démarrage rapide désactivé** (`powercfg /h off`), sinon la partition NTFS reste
  « hibernée » et Linux ne peut pas l'écrire.
- Horloge : Windows en UTC (`RealTimeIsUniversal = 1`), sinon une heure de décalage à chaque changement.
- **BitLocker** : clé de récupération affichée avant l'installation de Linux (un changement de chargeur
  peut la demander au prochain démarrage).
- **LinOffice non proposé** en dessous de 512 Go : Office est déjà disponible nativement sous Windows.

## 6. Mise en œuvre technique

| Système | Mécanisme | Calcul des tailles | Points à valider |
| --- | --- | --- | --- |
| Windows 11 | Plugin Ventoy `auto_install` : plusieurs modèles unattend proposés au démarrage (« Manuel », « Automatique — Bureautique », « Automatique — Développement », « Double démarrage ») ; plugin Ventoy `injection` : script `diskpart` dans WinPE (passe `windowsPE`, `RunSynchronous`) | Le script lit la taille du disque, choisit la classe, crée les partitions (méthode Microsoft `shrink` pour placer WinRE après `C:`), puis `InstallTo` | Détection fiable du disque cible et du « disque vide » en WinPE ; Dev Drive créé par la post-installation (`Format-Volume -DevDrive`) |
| Ubuntu | autoinstall (fichier `user-data` via `auto_install` Ventoy) | `early-commands` qui réécrit la section `storage` selon la taille | Prise en charge des sous-volumes Btrfs par l'installateur ; Ubuntu Desktop 24.04+ uniquement |
| Fedora | kickstart | `%pre` qui génère `/tmp/part.ks` (`%include`) | Noms de sous-volumes `@`/`@home` (Fedora utilise `root`/`home` : Timeshift en mode rsync sinon) |
| Debian | preseed | recettes `partman` (`min`/`priorité`/`max`) proportionnelles par nature | Sous-volumes Btrfs non gérés par partman : ext4 `/` unique en repli |
| Linux Mint | preseed (installateur Ubiquity) | idem Debian | Prise en charge partielle : mode manuel conservé si non concluant |

Côté moteur :

- `Build-Kit.ps1 -Partitionnement Manuel|Auto` (défaut `Manuel`) ; profils : champ `Partitionnement`
  avec les tailles ci-dessus (modifiable par l'administration) ;
- assistants : case « Proposer l'installation automatique (efface un disque vide) » ;
- `installer-poste.sh` et `Install-Poste.ps1` : réglages post-installation des sections 3 à 5.

## 7. Feuille de route proposée

| Étape | Contenu | Risque |
| --- | --- | --- |
| **1 — Sans partitionnement** | Post-installations : Timeshift en mode Btrfs s'il est disponible, `chattr +C` pour LinOffice, sous-volume `@docker` si possible, double démarrage (démarrage rapide, horloge UTC), Dev Drive en VHDX sous Windows (développement) | faible : rien n'est effacé |
| **2 — Guide** | `docs/PARTITIONNEMENT.md` : ces dispositions à appliquer à la main dans les installateurs | nul |
| **3 — Linux automatique** | Debian (preseed) puis Ubuntu (autoinstall) puis Fedora (kickstart), disque vide uniquement ; tests en VM sur GitHub Actions (KVM disponible, comme LinOffice) | moyen |
| **4 — Windows automatique** | Modèles unattend + script WinPE ; tests en VM (dockur/windows ou QEMU) | moyen à élevé |

## 8. Décisions à prendre

1. Btrfs par défaut sous Linux (instantanés Timeshift) ou ext4 (plus simple, choix par défaut d'Ubuntu) ?
2. Chiffrement (BitLocker, LUKS) coché par défaut sur les portables ?
3. Tailles de `C:` (200/250/300 Go) et du Dev Drive : à ajuster selon le parc ?
4. Double démarrage : quel système est principal par défaut ?
5. Démarrer par l'étape 1 (sans risque) avant tout partitionnement automatique ?
