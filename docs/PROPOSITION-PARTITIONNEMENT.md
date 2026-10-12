# Proposition — Partitionnement idéal selon le scénario, l'usage et le disque

> **Statut : recommandation d'architecture.** L'étape 1 (réglages sans partitionnement) est livrée dans
> la **v1.5.0** ; les étapes 2 à 5 restent à faire. Alchemist ne partitionne toujours pas le disque du
> poste : le technicien choisit le disque et la disposition dans l'installateur officiel.

## 1. Principes directeurs

1. **Un disque, un système** (« Full ») par défaut. L'autre système tourne *dans* le premier : WSL 2
   sous Windows, LinOffice / WinBoat sous Linux. Le double démarrage est l'exception, sur demande.
2. **Le moins de partitions possible.** Une partition de taille fixe est un pari sur l'avenir qui finit
   toujours par être perdu (« `C:` plein, `D:` vide »). On découpe l'espace avec des outils souples :
   sous-volumes Btrfs sous Linux, disque virtuel dynamique (VHDX) sous Windows.
3. **Les partitions protègent mal les données ; les sauvegardes les protègent.** Instantanés
   (Timeshift) pour revenir en arrière, OneDrive / sauvegarde externe pour les documents (règle 3-2-1).
4. **Dispositions standard des éditeurs**, ajustées au minimum : un poste conforme à ce que Microsoft,
   Canonical et Fedora attendent se met à jour, se répare et se dépanne sans surprise.
5. **Chiffrement par défaut sur les portables**, avec clé de récupération remise au responsable du parc.

## 2. Garde-fous du mode automatique

- Le mode **Manuel** (actuel) reste disponible et proposé en premier dans le menu Ventoy.
- **Disque vide uniquement** ; un disque déjà partitionné arrête l'installation. L'effacement d'un disque
  non vide est un choix distinct (« EFFACER le disque »), confirmé par une saisie.
- Cible : un **disque interne** (NVMe, SATA), jamais la clé Ventoy ni un disque USB ; s'il y en a
  plusieurs, le plus petit est proposé et affiché (modèle, taille) avant tout effacement.
- ISO officielles **non modifiées** : seuls des fichiers de réponse et des scripts injectés par Ventoy.

## 3. Scénarios et tailles minimales

| Scénario | Disque | L'autre système | Bureautique | Développement |
| --- | --- | --- | --- | --- |
| **Full Windows** | 100 % Windows | WSL 2 (Ubuntu), machine Podman | 128 Go min. · 256 Go conseillé | 256 Go min. · 512 Go conseillé |
| **Full Linux** | 100 % Linux | LinOffice (Microsoft 365 intégral), WinBoat | 128 Go min. · **256 Go avec LinOffice** | 256 Go min. · 512 Go conseillé |
| **Double démarrage** | partagé | installé à côté | 512 Go min. | 512 Go min. · **2 disques idéal** |

Espace du système « invité », compté dans ces minima :

| Invité | Emplacement | Budget |
| --- | --- | --- |
| WSL 2 | VHDX dynamique dans le profil, sur `C:` | 20 Go (bureautique) · 40–80 Go (développement) |
| Machine Podman (Windows) | VHDX WSL, sur `C:` | 20–40 Go |
| LinOffice | `~/.local/share/containers` (`@home`) | 64 Go libres exigés ; ≈ 25 Go occupés (mesuré en CI) |
| WinBoat | conteneur Docker (`@docker`) | 64 Go conseillés (emplacement exact à vérifier) |

## 4. Full Windows — disposition Microsoft, un seul `C:`

```
GPT / UEFI, Secure Boot actif
├─ EFI        260 Mo   FAT32     (compatible disques 4K natifs)
├─ MSR         16 Mo
├─ C:         reste    NTFS      Windows, applications, profils, WSL 2, Podman
└─ WinRE        1 Go   NTFS      récupération, APRÈS C: (agrandissable lors des mises à jour)
```

- **Pas de `D: Données`**, quelle que soit la taille : les profils, OneDrive, WSL et la plupart des
  applications écrivent dans `C:` ; une partition de données se remplit rarement au bon rythme et
  complique la redirection des dossiers. Les documents sont protégés par **OneDrive (déplacement des
  dossiers connus)** ou une sauvegarde, pas par une partition.
- **WinRE de 1 Go après `C:`** : les partitions de récupération trop petites ont fait échouer la mise à
  jour KB5034441 (2024) ; placée après `C:`, elle reste extensible.
- **Développement : Dev Drive en VHDX dynamique**, créé par la post-installation sur `C:` (ReFS,
  Windows 11 22H2+, Defender en mode performance) : 128 Go maximum (256–511 Go), 256 Go (512 Go – 1 To),
  512 Go (> 1 To). Il reçoit les dépôts et les caches (`npm`, `NuGet`, `Maven`, `pip`, `cargo`) ; il ne
  réserve que l'espace réellement utilisé et se redimensionne sans repartitionner.
- **BitLocker** : portables, clé de récupération imprimée ou enregistrée hors du poste (compte local).
- Fichier d'échange et veille prolongée : gérés par Windows (aucun réglage).

## 5. Full Linux — Btrfs à sous-volumes, une seule partition de données

```
GPT / UEFI, Secure Boot actif (shim signé)
├─ EFI     1 Go   FAT32   chargeurs, micrologiciels (fwupd), plusieurs noyaux
├─ /boot   2 Go   ext4    UNIQUEMENT si chiffrement (GRUB ne lit pas LUKS2/Argon2)
└─ Btrfs   reste          [dans LUKS2 sur les portables]
     @           /                  instantanés Timeshift
     @home       /home              instantanés Timeshift (option) ; LinOffice ici
     @var_log    /var/log           hors instantanés : un retour arrière garde les journaux
     @docker     /var/lib/docker    développement / WinBoat ; hors instantanés
     @swap       /swap              fichier d'échange (sans copie à l'écriture)
```

| Réglage | Valeur | Raison |
| --- | --- | --- |
| Options de montage | `noatime,compress=zstd:1` | moins d'écritures sur le SSD, 20–40 % d'espace gagné sur le système, coût CPU négligeable |
| TRIM | `discard=async` (défaut des noyaux récents) + `fstrim.timer` | performance et durée de vie du SSD |
| Mémoire d'échange | **zram** (50 % de la RAM, zstd, prioritaire) + fichier de **4 Go** dans `@swap` | réactivité sous pression mémoire ; le fichier évite les arrêts brutaux (OOM) ; pas d'hibernation (bloquée avec Secure Boot) |
| Disques de machines virtuelles | `chattr +C` sur `~/.local/share/containers` (LinOffice) et `/var/lib/libvirt/images` | pas de copie à l'écriture : évite la fragmentation des disques virtuels |
| Instantanés | **Timeshift en mode Btrfs**, 5 quotidiens + 3 hebdomadaires, avant chaque mise à jour | retour arrière en une minute ; *ce n'est pas une sauvegarde* |
| Chiffrement | **LUKS2** sur les portables (phrase + clé de récupération) ; déverrouillage TPM2 là où la distribution le gère | perte ou vol |

Distributions :

- **Ubuntu LTS et Fedora** : disposition ci-dessus (Fedora utilise Btrfs par défaut ; les sous-volumes
  sont renommés `@`/`@home` pour Timeshift).
- **Debian et Linux Mint** : leurs installateurs automatiques ne créent pas de sous-volumes ; repli en
  **ext4 `/` unique** + fichier d'échange + zram, sans instantanés Btrfs (Timeshift en mode rsync).

Bureautique et développement partagent la même disposition : l'usage change le contenu, pas le
découpage (`@docker` reste vide en bureautique).

## 6. Double démarrage — seulement sur demande

**Idéal : deux disques**, un par système, chacun avec sa propre partition EFI et sa disposition « Full »
(sections 4 et 5). Aucune dépendance entre les deux : une mise à jour de l'un ne casse jamais l'autre ;
le choix se fait au menu de démarrage du micrologiciel (F12…) ou dans GRUB.

**Un seul disque (512 Go minimum)** :

```
├─ EFI     1 Go   FAT32   partagée (créée 1 Go par le scénario, pas 100 Mo)
├─ MSR    16 Mo
├─ C:      X      NTFS    Windows
├─ WinRE   1 Go   NTFS
├─ [/boot  2 Go   ext4    si chiffrement Linux]
└─ Btrfs   reste          Linux (sous-volumes de la section 5)
```

| Disque | Bureautique (Windows principal) | Développement (Linux principal) |
| --- | --- | --- |
| 512 Go – 1 To | `C:` 60 % · Linux 40 % | `C:` 200 Go · Linux reste |
| > 1 To | `C:` 50 % · Linux 50 % | `C:` 250 Go · Linux reste |

- Pas de partition « Partage » : Linux lit et écrit le NTFS de Windows (pilote `ntfs3`) ; les
  documents communs vont dans OneDrive ou un dossier de `C:`.
- Obligatoire : **démarrage rapide et veille prolongée désactivés** sous Windows (sinon le NTFS reste
  « hiberné », Linux ne peut pas l'écrire et risque de le corrompre) ; **horloge en UTC** des deux côtés
  (`RealTimeIsUniversal = 1`).
- **BitLocker** : clé de récupération sauvegardée *avant* d'installer Linux (un changement de chargeur
  peut la demander).
- WSL 2 et LinOffice non installés par défaut : le vrai système est à côté.

## 7. Mise en œuvre

| Système | Mécanisme | Calcul des tailles | À valider |
| --- | --- | --- | --- |
| Windows 11 | plugin Ventoy `auto_install` : modèles unattend « Manuel », « Full Windows », « Double démarrage » ; plugin `injection` : script `diskpart` en WinPE (`RunSynchronous`) | disposition fixe (Full) ; `C:` calculé selon la taille (double démarrage) ; méthode Microsoft `shrink` pour WinRE après `C:` | détection du disque cible et du « disque vide » en WinPE |
| Ubuntu LTS | autoinstall (`user-data` via `auto_install`) | `early-commands` qui écrit la section `storage` | sous-volumes Btrfs dans curtin ; Ubuntu Desktop 24.04+ |
| Fedora | kickstart | `%pre` → `/tmp/part.ks` (`%include`) | renommage des sous-volumes |
| Debian · Mint | preseed | recettes `partman` (proportionnelles par nature) | Ubiquity (Mint) : prise en charge partielle |
| Post-installations | `installer-poste.sh`, `Install-Poste.ps1` | — | Dev Drive (`Format-Volume -DevDrive` sur un VHDX), zram, `chattr +C`, Timeshift Btrfs, réglages double démarrage |

Tests : chaque scénario est installé en machine virtuelle sur GitHub Actions (KVM disponible, comme le
test LinOffice), sur des disques virtuels de 128 Go, 256 Go et 1 To ; on vérifie la table de partitions
obtenue, le démarrage, puis la post-installation.

## 8. Feuille de route

| Étape | Contenu | Risque |
| --- | --- | --- |
| **1 — Réglages sans partitionnement** ✅ v1.5.0 | zram, `chattr +C` (LinOffice, libvirt), Timeshift en mode Btrfs s'il est disponible, Dev Drive VHDX (Windows, développement), double démarrage (démarrage rapide, horloge UTC) | faible : rien n'est effacé |
| **2 — Guide** | `docs/PARTITIONNEMENT.md` : ces dispositions, pas à pas, dans les installateurs | nul |
| **3 — Full Linux automatique** | Ubuntu puis Fedora, puis Debian/Mint (repli ext4) ; disque vide uniquement | moyen |
| **4 — Full Windows automatique** | disposition Microsoft + WinRE après `C:` | moyen |
| **5 — Double démarrage automatique** | deux disques d'abord, puis un seul disque | élevé |

## 9. En résumé

| | Full Windows | Full Linux | Double démarrage |
| --- | --- | --- | --- |
| Partitions | EFI · MSR · `C:` · WinRE | EFI · [/boot] · Btrfs | 2 disques, ou EFI partagée + Windows + Linux |
| Découpage souple | Dev Drive VHDX | sous-volumes Btrfs | idem de chaque côté |
| Protection | BitLocker (portables) · OneDrive / sauvegarde | LUKS2 (portables) · Timeshift + sauvegarde | les deux |
| L'autre système | WSL 2 · Podman | LinOffice · WinBoat | à côté |
