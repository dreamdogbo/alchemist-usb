<#
.SYNOPSIS
    Prépare une clé Ventoy (déjà installée) selon un PROFIL : système, bureautique, logiciels,
    outils technicien et post-installation, prête à l'emploi hors ligne.

.DESCRIPTION
    Étapes :
      0. (option) Sauvegarde des données présentes sur la clé.
      1. Contrôle de la clé (détection automatique, libellé « Ventoy », espace libre).
      2. Résolution des sources officielles (Fido/Microsoft, CDN Office, winget, GitHub, éditeurs).
      3. Budget d'espace par priorité (rien n'est écrit si ça ne rentre pas).
      4. Téléchargement vérifié dans cache\<Nom>\ (reprise, 3 tentatives, SHA256, signature).
      5. Mise en place sur la clé, suppression des anciennes versions gérées, MANIFEST.sha256.
      6. Post-installation, catalogue.json, LISEZMOI.txt, modèle d'installation Ventoy.
      7. Rapport final OK / ÉCHEC / IGNORÉ et journal horodaté dans logs\.

    La clé n'est JAMAIS formatée, partitionnée ni réinstallée. Les fichiers qui ne sont pas
    listés dans /MANIFEST.sha256 (fichiers personnels) ne sont jamais modifiés.
    Interface graphique : Assistant.ps1 (ou double-clic sur Creer-Cle.bat).

.PARAMETER Profil
    Nom du profil (fichier de config\profils\ sans extension). Défaut : windows11-bureautique.
.PARAMETER Systeme
    Windows ou Linux : avec -Usage, choisit le profil correspondant (au lieu de -Profil).
.PARAMETER Usage
    Bureautique ou Developpement.
.PARAMETER ListerProfils
    Affiche les profils disponibles et quitte (-Json pour une sortie JSON).
.PARAMETER ListerElements
    Affiche en JSON les éléments du profil choisi et quitte (utilisé par les assistants).
.PARAMETER Json
    Sortie JSON pour -ListerProfils.
.PARAMETER KeyPath
    Chemin de la clé (point de montage sous Linux, ex. /media/moi/Ventoy). Sinon : détection automatique.
.PARAMETER Langue
    Langue du contenu de la clé (ISO Windows, Office, clavier) : fr, en, es, de, pt…
    (codes définis dans le profil, rubrique Langues). Défaut : LangueDefaut du profil.
.PARAMETER DriveLetter
    Lettre de la clé Ventoy. Si absent : détection automatique de la clé libellée « Ventoy ».
.PARAMETER SansOffice
    N'embarque pas Office (libère environ 4 Go).
.PARAMETER Only
    Ne traite que les éléments nommés (ex. -Only Chrome,VLC). Les noms sont ceux du profil.
.PARAMETER Avec
    Ajoute des éléments facultatifs (non cochés par défaut) à la sélection standard.
    Ex. : -SansOffice -Avec LibreOffice (suite bureautique gratuite au lieu d'Office).
.PARAMETER SkipDownload
    Aucun accès Internet : met en place ce qui est déjà complet dans cache\ et régénère
    la post-installation.
.PARAMETER DryRun
    Simulation : contrôle la clé, interroge les sources, affiche le budget d'espace.
    Aucune écriture sur la clé (hors journal du kit).
.PARAMETER SansVerifSignature
    Désactive le contrôle des signatures Authenticode (les SHA256 publiés restent vérifiés).
.PARAMETER SauvegardeVers
    Dossier (hors clé) où sauvegarder les fichiers personnels de la clé avant préparation.
.PARAMETER SauvegardeComplete
    Avec -SauvegardeVers : sauvegarde toute la clé, pas seulement les fichiers personnels.
.PARAMETER WindowsIsoUrl
    Lien de téléchargement officiel Microsoft de l'ISO (domaine microsoft.com obligatoire),
    à utiliser quand Microsoft bloque Fido (erreur « 715-123130 » / « Sentinel »).
.PARAMETER IsoPersonnelle
    Images fournies par l'utilisateur (ISO Windows 7 / 8.1 sous licence, autre système…) copiées
    dans ISO/Personnel/ de la clé, avec vérification SHA256. Fichiers personnels : jamais supprimés.
.PARAMETER CachePath
    Dossier de préparation (défaut : cache\ à côté de ce script). Sur le même volume que la
    clé, la mise en place est un simple déplacement.
.PARAMETER LogFile
    Chemin imposé du journal (utilisé par l'assistant graphique pour l'afficher en direct).
.PARAMETER InstallerVentoy
    Installe Ventoy (release officielle, SHA256 vérifié) sur le disque -Disque AVANT de préparer le
    contenu. EFFACE le disque : exige -ConfirmerEffacement EFFACER-<numéro> et les droits administrateur.
    Disques USB/SD uniquement, jamais le disque système ni celui où se trouve le kit.
.PARAMETER Disque
    Disque pour -InstallerVentoy : numéro sous Windows (Get-Disk), /dev/sdX sous Linux (lsblk).
.PARAMETER ConfirmerEffacement
    Confirmation explicite de l'effacement : « EFFACER-<numéro> » (Windows) ou « EFFACER-sdX » (Linux).
.PARAMETER VentoyGPT
    Table de partitions GPT au lieu de MBR (défaut Ventoy).
.PARAMETER VentoySansSecureBoot
    Désactive la prise en charge du Secure Boot par Ventoy (déconseillé).
.PARAMETER VentoyFS
    Système de fichiers de la partition de données : exFAT (défaut Ventoy) ou NTFS.
.PARAMETER MettreAJourVentoy
    Met à jour Ventoy sur la clé détectée, SANS effacer les données (mode Update officiel).

.EXAMPLE
    .\Build-Kit.ps1 -DryRun
.EXAMPLE
    .\Build-Kit.ps1 -Profil windows11-bureautique -DriveLetter E
.EXAMPLE
    .\Build-Kit.ps1 -Only Chrome,Firefox -SauvegardeVers D:\Sauvegardes
.EXAMPLE
    .\Build-Kit.ps1 -InstallerVentoy -Disque 2 -ConfirmerEffacement EFFACER-2 -SauvegardeVers D:\Sauvegardes
.EXAMPLE
    .\Build-Kit.ps1 -MettreAJourVentoy

.NOTES
    Codes de sortie : 0 = OK, 1 = au moins un élément en ÉCHEC, 2 = clé invalide ou erreur
    générale, 3 = source officielle introuvable pour le système ou Office (arrêt).
    Compatible Windows PowerShell 5.1 et PowerShell 7.
#>
[CmdletBinding()]
param(
    [string] $Profil = '',
    [ValidateSet('Windows', 'Linux')] [string] $Systeme,
    [ValidateSet('Bureautique', 'Developpement')] [string] $Usage,
    [switch] $ListerProfils,
    [switch] $ListerElements,
    [switch] $Json,
    [string] $Langue,
    [string] $DriveLetter,
    [switch] $SansOffice,
    [string[]] $Only,
    [string[]] $Avec,
    [switch] $SkipDownload,
    [switch] $DryRun,
    [switch] $SansVerifSignature,
    [string] $SauvegardeVers,
    [switch] $SauvegardeComplete,
    [string] $WindowsIsoUrl,
    [string[]] $IsoPersonnelle,
    [string] $CachePath,
    [string] $LogFile,
    [switch] $InstallerVentoy,
    [string] $Disque,
    [string] $KeyPath,
    [string] $ConfirmerEffacement,
    [switch] $VentoyGPT,
    [switch] $VentoySansSecureBoot,
    [ValidateSet('exFAT', 'NTFS')] [string] $VentoyFS = 'exFAT',
    [switch] $MettreAJourVentoy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { Write-Verbose 'Encodage console inchangé.' }

$kitRoot = $PSScriptRoot
# Version du kit (SemVer) : source unique = fichier VERSION
$kitVersion = '0.0.0'
$versionFile = Join-Path $kitRoot 'VERSION'
if (Test-Path -LiteralPath $versionFile) { $kitVersion = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim() }
foreach ($m in @('Report', 'Drive', 'Budget', 'Download', 'Sync', 'Backup', 'Ventoy', 'Profile')) {
    Import-Module (Join-Path $kitRoot "modules/$m.psm1") -Force -DisableNameChecking
}

# ---------------------------------------------------------------------- profils disponibles
$profileDir = Join-Path $kitRoot 'config/profils'
$allProfiles = Get-KitProfileList -Directory $profileDir

if ($ListerProfils) {
    if ($Json) { $allProfiles | Select-Object Name, Nom, Systeme, Usage, Description | ConvertTo-Json -Depth 3 -Compress; exit 0 }
    foreach ($p in $allProfiles) { Write-Host ("{0,-28} {1,-8} {2,-14} {3}" -f $p.Name, $p.Systeme, $p.Usage, $p.Description) }
    exit 0
}
# Profil : par nom (-Profil), ou par système + usage (-Systeme / -Usage), sinon profil par défaut
if (-not $Profil) {
    if ($Systeme -or $Usage) {
        $match = @($allProfiles | Where-Object { (-not $Systeme -or $_.Systeme -eq $Systeme) -and (-not $Usage -or $_.Usage -eq $Usage) })
        if ($match.Count -eq 0) { Write-Error "Aucun profil pour Systeme=$Systeme Usage=$Usage."; exit 2 }
        $Profil = $match[0].Name
    }
    else { $Profil = 'windows11-bureautique' }
}
if ($ListerElements) {
    # Éléments du profil en JSON (assistants graphiques, Windows et Linux)
    $pd = @($allProfiles | Where-Object { $_.Name -eq $Profil }) | Select-Object -First 1
    if (-not $pd) { Write-Error "Profil « $Profil » introuvable."; exit 2 }
    $out = [ordered]@{ Profil = $pd.Name; Nom = $pd.Nom; Systeme = $pd.Systeme; Usage = $pd.Usage; Langues = @(); Items = @() }
    if ($pd.Data.ContainsKey('Langues')) { $out.Langues = @($pd.Data.Langues.Keys | Sort-Object) }
    $out.Items = @($pd.Data.Items | ForEach-Object {
            [ordered]@{ Name = $_.Name; Category = [string]$_['Category']; Type = $_.Type
                Default = -not ($_.ContainsKey('Default') -and -not $_.Default); SizeMB = [int]$_['EstimatedSizeMB']; Mode = [string]$_['Mode'] }
        })
    $out | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

$exitCode = 0
$freeBefore = -1.0
$freeAfter = -1.0
$phase = 'init'
$keyRoot = ''
[void](Initialize-KitLog -LogDirectory (Join-Path $kitRoot 'logs') -LogFile $LogFile)

# Une seule préparation à la fois sur ce poste : deux préparations simultanées (double-clic,
# assistant + ligne de commande) écriraient les mêmes fichiers de la clé et la rendraient incohérente.
# Une simulation n'écrit rien sur la clé : elle n'est pas concernée.
$buildLock = $null
if (-not $DryRun) {
    try {
        $buildLock = New-Object System.Threading.Mutex($false, 'Global\Alchemist-Build')
        $acquired = $false
        try { $acquired = $buildLock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) {
            $buildLock.Dispose(); $buildLock = $null
            Write-KitLog -Level ERROR -Message 'Une autre préparation de clé est déjà en cours sur ce poste. Attendez sa fin (ou arrêtez-la) avant d''en lancer une nouvelle.'
            exit 2
        }
    }
    catch {
        # Accès refusé : verrou créé par une préparation lancée avec d'autres droits, donc détenu
        $denied = $false
        for ($ex = $_.Exception; $ex; $ex = $ex.InnerException) { if ($ex -is [System.UnauthorizedAccessException]) { $denied = $true } }
        if ($denied) {
            Write-KitLog -Level ERROR -Message 'Une autre préparation de clé est déjà en cours sur ce poste (lancée en administrateur). Attendez sa fin avant d''en lancer une nouvelle.'
            exit 2
        }
        $buildLock = $null
        Write-Verbose ('Verrou de préparation indisponible : {0}' -f $_.Exception.Message)
    }
    Set-KitKeepAwake -Enabled $true -Confirm:$false
}

try {
    Write-KitLog -Level STEP -Message ("Alchemist v{2} — {0}{1}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $(if ($DryRun) { ' — MODE SIMULATION' } else { '' }), $kitVersion)
    Write-KitLog -Message ("PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
    Initialize-KitNetwork
    # Authenticode n'existe que sous Windows : sous Linux, seuls les SHA256 publiés font foi
    Set-KitSignaturePolicy -Disabled:($SansVerifSignature -or -not (Test-KitWindows))
    if ($SansVerifSignature) { Write-KitLog -Level WARN -Message 'Vérification des signatures Authenticode DÉSACTIVÉE (les SHA256 publiés restent contrôlés).' }

    # ------------------------------------------------------------------ configuration (profil)
    $profilePath = Join-Path $profileDir "$Profil.psd1"
    if (-not (Test-Path -LiteralPath $profilePath)) {
        $known = (@(Get-ChildItem -LiteralPath $profileDir -Filter '*.psd1') | ForEach-Object BaseName) -join ', '
        throw "Profil « $Profil » introuvable. Profils disponibles : $known"
    }
    $config = Get-KitProfile -Directory $profileDir -Name $Profil
    Write-KitLog -Message ("Profil : {0} — {1}" -f $Profil, $config.Nom)
    $allItems = @($config.Items)

    # Langue du contenu (ISO, Office, clavier) : appliquée aux éléments du profil
    $langInfo = $null
    if ($config.ContainsKey('Langues')) {
        if (-not $Langue) { $Langue = $config.LangueDefaut }
        if (-not $config.Langues.ContainsKey($Langue)) { throw ("Langue « {0} » non prévue dans le profil. Choix : {1}" -f $Langue, (($config.Langues.Keys | Sort-Object) -join ', ')) }
        $langInfo = $config.Langues[$Langue]
        foreach ($it in $allItems) {
            if ($it.Type -eq 'WindowsIso') {
                $it.FidoLang = $langInfo.FidoLang
                $it.FileName = ([string]$it.FileName).Replace('{LANG}', $langInfo.IsoSuffix)
            }
            if ($it.Type -eq 'Office') { $it.OfficeLanguage = $langInfo.Office }
        }
        Write-KitLog -Message ("Langue du contenu : {0} ({1}, Office {2})" -f $Langue, $langInfo.Label, $langInfo.Office)
    }
    # Sélection : -Only (liste exacte) sinon éléments « par défaut » du profil, plus -Avec
    $validNames = @($allItems | ForEach-Object { $_.Name })
    $splitNames = { param($list) @($list | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $names = @(& $splitNames $Only) + @(& $splitNames $Avec)
    $unknown = @($names | Where-Object { $_ -notin $validNames })
    if ($unknown.Count -gt 0) {
        throw ("Nom(s) inconnu(s) : {0}. Noms valides : {1}" -f ($unknown -join ', '), ($validNames -join ', '))
    }
    if ($Only) { $items = @($allItems | Where-Object { $_.Name -in $names }) }
    else {
        $extra = @(& $splitNames $Avec)
        $items = @($allItems | Where-Object { -not ($_.ContainsKey('Default') -and -not $_.Default) -or $_.Name -in $extra })
        $optional = @($allItems | Where-Object { $_.ContainsKey('Default') -and -not $_.Default -and $_.Name -notin $extra } | ForEach-Object Name)
        if ($optional.Count -gt 0) { Write-KitLog -Message ("Éléments facultatifs non inclus (ajoutez-les avec -Avec) : {0}" -f ($optional -join ', ')) }
    }
    if ($SansOffice) { $items = @($items | Where-Object { $_.Type -ne 'Office' }) }
    $marginBytes = [double]$config.MarginMB * 1MB

    # ------------------------------------------------------------------ 0b. installation de Ventoy (option)
    $installedRoot = ''
    if ($InstallerVentoy) {
        $phase = 'ventoy'
        if (-not $Disque) { throw 'Précisez le disque : -Disque <numéro> (Windows, voir Get-Disk) ou -Disque /dev/sdX (Linux, voir lsblk).' }
        $diskName = Split-Path -Leaf $Disque
        Write-KitLog -Level STEP -Message "0. Installation de Ventoy sur le disque $Disque (le disque sera EFFACÉ)"
        if ($ConfirmerEffacement -cne "EFFACER-$diskName") {
            throw "Confirmation manquante : ajoutez -ConfirmerEffacement EFFACER-$diskName (toutes les données du disque $Disque seront perdues)."
        }
        $target = Assert-KitVentoyTarget -Disk $Disque -KitRoot $kitRoot
        Write-KitLog -Message ("Disque cible : {0} — {1} — {2} Go — volumes : {3}" -f $target.Id, $target.Model, $target.SizeGB, ($target.Letters -join ', '))
        if ($DryRun) {
            Write-KitLog -Level WARN -Message 'Simulation : Ventoy serait installé (rien n''est effacé en simulation).'
            if (-not $target.IsVentoy) {
                Add-KitResult -Name 'Ventoy' -Status 'OK' -Detail "serait installé sur le disque $Disque (simulation)"
                $exitCode = Show-KitReport -DryRun
                exit $exitCode
            }
        }
        else {
            if (-not (Test-KitAdmin)) { throw 'L''installation de Ventoy nécessite les droits administrateur (Windows) ou root (Linux : sudo).' }
            if ($SauvegardeVers) {
                foreach ($l in $target.Letters) {
                    $volRoot = $(if (Test-KitWindows) { "$($l):\" } else { $l.TrimEnd('/') + '/' })
                    $bk = Backup-KitDrive -KeyRoot $volRoot -Destination $SauvegardeVers -Manifest @{} -Complete
                    if ($bk.Files -gt 0) { Add-KitResult -Name "Sauvegarde $l" -Status 'OK' -Detail ("{0} fichier(s) dans {1}" -f $bk.Files, $bk.Folder) -SizeMB ($bk.Bytes / 1MB) }
                }
                $SauvegardeVers = $null   # la clé sera vierge : rien d'autre à sauvegarder ensuite
            }
            $ventoy = Save-KitVentoy -ToolsDir (Join-Path ([IO.Path]::GetTempPath()) 'alchemist-ventoy')
            Install-KitVentoy -Exe $ventoy.Exe -Disk $target.Id -Gpt:$VentoyGPT -NoSecureBoot:$VentoySansSecureBoot -FileSystem $VentoyFS -Label $config.VolumeLabel -Confirm:$false
            $installedRoot = Wait-KitVentoyVolume -Disk $target.Id -Label $config.VolumeLabel
            Add-KitResult -Name 'Ventoy' -Status 'OK' -Detail ("Ventoy {0} installé sur le disque {1} ({2})" -f $ventoy.Version, $target.Id, $installedRoot)
        }
    }

    # ------------------------------------------------------------------ 1. clé
    $phase = 'drive'
    Write-KitLog -Level STEP -Message '1. Contrôle de la clé'
    $rootToCheck = ''
    if ($installedRoot) { $rootToCheck = $installedRoot }
    elseif ($KeyPath) { $rootToCheck = $KeyPath }
    elseif ($DriveLetter) { $rootToCheck = Get-KitDriveRoot -DriveLetter ([char]$DriveLetter) }
    else {
        # Détection automatique : une seule clé « Ventoy » branchée => on la prend
        $candidates = @(Find-KitVentoyDrive -ExpectedLabel $config.VolumeLabel)
        if ($candidates.Count -eq 0) { throw "Aucune clé « $($config.VolumeLabel) » détectée. Branchez (et montez) la clé Ventoy, cochez « Clé neuve » pour installer Ventoy, ou précisez -DriveLetter / -KeyPath." }
        if ($candidates.Count -gt 1) { throw ("Plusieurs clés Ventoy détectées ({0}) : précisez -DriveLetter (Windows) ou -KeyPath (Linux)." -f (($candidates | ForEach-Object Root) -join ', ')) }
        $rootToCheck = $candidates[0].Root
        Write-KitLog -Message ("Clé Ventoy détectée automatiquement : {0}" -f $rootToCheck)
    }
    $drive = Test-KitDrive -Root $rootToCheck -ExpectedLabel $config.VolumeLabel -MinFreeBytes $marginBytes
    $keyRoot = $drive.Root
    $freeBefore = $drive.FreeBytes

    if ($MettreAJourVentoy) {
        $phase = 'ventoy'
        if (Test-KitWindows) { $diskId = [string](Get-Partition -DriveLetter $keyRoot.Substring(0, 1)).DiskNumber }
        else {
            $mp = $keyRoot.TrimEnd('/')
            $diskId = [string](@(Get-KitLinuxBlock | Where-Object { $_.mountpoint -eq $mp }) | Select-Object -First 1).ParentDisk.path
        }
        [void](Assert-KitVentoyTarget -Disk $diskId)
        if ($DryRun) { Write-KitLog -Level WARN -Message "Simulation : Ventoy serait mis à jour sur le disque $diskId (sans effacement)." }
        else {
            if (-not (Test-KitAdmin)) { throw 'La mise à jour de Ventoy nécessite les droits administrateur (Windows) ou root (Linux : sudo).' }
            $ventoy = Save-KitVentoy -ToolsDir (Join-Path ([IO.Path]::GetTempPath()) 'alchemist-ventoy')
            Invoke-KitVentoy2Disk -Exe $ventoy.Exe -Mode Update -Disk $diskId -Confirm:$false
            $keyRoot = Wait-KitVentoyVolume -Disk $diskId -Label $config.VolumeLabel
            Add-KitResult -Name 'Ventoy' -Status 'OK' -Detail ("Ventoy mis à jour en {0} (données conservées)" -f $ventoy.Version)
        }
        $phase = 'drive'
    }

    # Zone de préparation : par défaut SUR LA CLÉ (rien de lourd sur l'ordinateur ; la mise en place
    # est alors un simple déplacement). Dans le dossier du kit s'il est lui-même sur la clé.
    $cacheRoot = $CachePath
    if (-not $cacheRoot) {
        if ([IO.Path]::GetFullPath($kitRoot).StartsWith($keyRoot, [StringComparison]::OrdinalIgnoreCase)) { $cacheRoot = Join-Path $kitRoot 'cache' }
        else { $cacheRoot = Join-Path $keyRoot 'kit-cache' }
    }
    $cacheRoot = [IO.Path]::GetFullPath($cacheRoot)
    if (-not $DryRun -and -not (Test-Path -LiteralPath $cacheRoot)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
    if (-not $cacheRoot.StartsWith($keyRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Write-KitLog -Level WARN -Message "Le cache ($cacheRoot) n'est pas sur la clé : la mise en place sera une copie (plus lente)."
    }
    # Outils (Fido, descripteur Office) : hors clé en DryRun
    $toolsDir = Join-Path $cacheRoot '_outils'
    if ($DryRun) { $toolsDir = Join-Path ([IO.Path]::GetTempPath()) 'alchemist-outils' }
    $officeConfig = Join-Path $kitRoot ('config/' + $(if ($config.ContainsKey('OfficeConfig')) { $config.OfficeConfig } else { 'office-config.xml' }))
    $manifest = Read-KitManifest -KeyRoot $keyRoot
    Write-KitLog -Message ("MANIFEST : {0} fichier(s) déjà gérés par le kit" -f $manifest.Count)

    # ------------------------------------------------------------------ 0. sauvegarde (option)
    if ($SauvegardeVers) {
        $phase = 'backup'
        # Ni le dossier du kit (s'il est sur la clé) ni la zone de préparation ne sont des données
        $exclude = @('kit-cache')
        if ([IO.Path]::GetFullPath($kitRoot).StartsWith($keyRoot, [StringComparison]::OrdinalIgnoreCase)) { $exclude += (Split-Path -Leaf $kitRoot) }
        if ($DryRun) {
            $list = Get-KitBackupList -KeyRoot $keyRoot -Manifest $manifest -ExcludeDirs $exclude -Complete:$SauvegardeComplete
            $sum = 0.0; foreach ($f in $list) { $sum += $f.Length }
            Write-KitLog -Message ("Simulation : {0} fichier(s) ({1}) seraient sauvegardés vers {2}" -f $list.Count, (Format-KitSize $sum), $SauvegardeVers)
        }
        else {
            $bk = Backup-KitDrive -KeyRoot $keyRoot -Destination $SauvegardeVers -Manifest $manifest -ExcludeDirs $exclude -Complete:$SauvegardeComplete
            if ($bk.Files -gt 0) { Add-KitResult -Name 'Sauvegarde' -Status 'OK' -Detail ("{0} fichier(s) dans {1}" -f $bk.Files, $bk.Folder) -SizeMB ($bk.Bytes / 1MB) }
        }
    }

    # Clé Windows préparée depuis Linux : les logiciels winget viennent des manifestes publics de winget
    # (URL de l'éditeur, SHA256 vérifié) et vont sur la clé. Restent installés EN LIGNE sur le poste :
    # Office (l'Office Deployment Tool n'existe que sous Windows) et les fichiers sans empreinte publiée
    # (seule la signature Authenticode, invérifiable sous Linux, prouverait leur origine).
    $onTarget = 'à installer en ligne sur le poste (winget) : clé préparée depuis Linux'
    $deferToTarget = {
        param($it)
        if (Test-KitWindows) { return $false }
        if ($it.Type -eq 'Office') { return $true }
        if ($it.Type -eq 'Url') { return (@($it.Files | Where-Object { -not (Get-KitValue $_ 'Sha256' '') }).Count -gt 0) }
        return $false
    }
    if (-not (Test-KitWindows) -and $config.Systeme -eq 'Windows') {
        Write-KitLog -Level WARN -Message 'Clé Windows préparée depuis Linux : ISO et logiciels sur la clé (manifestes winget, SHA256 vérifiés) ; Office et les rares fichiers sans empreinte publiée seront installés en ligne par la post-installation (Internet requis sur le poste pour ceux-là).'
    }
    if (-not $SkipDownload -and (Test-KitWindows) -and @($items | Where-Object { $_.Type -eq 'Winget' }).Count -gt 0 -and -not (Initialize-KitWinget)) {
        Write-KitLog -Level WARN -Message "winget est introuvable : les logiciels sont pris dans les manifestes publics de winget (même source, SHA256 vérifié). Pour winget : « App Installer » du Microsoft Store."
    }
    # ------------------------------------------------------------------ 2. sources
    $phase = 'resolve'
    Write-KitLog -Level STEP -Message '2. Résolution des sources officielles'
    $plans = @()
    $index = 0
    foreach ($it in $items) {
        $plan = New-KitPlan -Item $it -Index $index
        $index++
        if (& $deferToTarget $it) {
            $plan.Status = 'EN_LIGNE'; $plan.Detail = $onTarget
            Write-KitLog -Message ("{0,-16} {1}" -f $plan.Name, $onTarget)
            $plans += $plan
            continue
        }
        try {
            Resolve-KitPlan -Plan $plan -KeyRoot $keyRoot -CacheRoot $cacheRoot -ToolsDir $toolsDir -FidoUrl $config.FidoUrl -Manifest $manifest -WindowsIsoUrl $WindowsIsoUrl -SkipDownload:$SkipDownload
            # Release GitHub sans SHA256 publié : seule la signature prouverait l'origine (invérifiable ici)
            if (-not (Test-KitWindows) -and $it.Type -eq 'GitHub' -and $plan.Status -eq 'A_TELECHARGER' -and $plan.Source -and -not $plan.Source.Sha256) {
                $plan.Status = 'EN_LIGNE'; $plan.Detail = "$onTarget (aucun SHA256 publié)"
            }
            Write-KitLog -Message ("{0,-16} {1,-14} {2,-12} {3}" -f $plan.Name, $plan.Status, (Format-KitSize $plan.NewBytes), $plan.Version)
        }
        catch {
            $plan.Status = 'INTROUVABLE'
            $plan.Detail = "Source introuvable : $($_.Exception.Message)"
            Write-KitLog -Level ERROR -Message ("{0} : {1}" -f $plan.Name, $plan.Detail)
        }
        $plans += $plan
    }

    # Windows 11 et Office sont essentiels : sans source officielle, on s'arrête (hors DryRun)
    # (un système facultatif, comme Windows 10, n'arrête pas la préparation : il est simplement en ÉCHEC)
    $critical = @($plans | Where-Object { $_.Status -eq 'INTROUVABLE' -and $_.Item.Type -in @('WindowsIso', 'Office') -and -not ($_.Item.ContainsKey('Default') -and -not $_.Item.Default) })
    if ($critical.Count -gt 0 -and -not $DryRun) {
        foreach ($c in $plans) {
            if ($c.Status -eq 'INTROUVABLE') { Add-KitResult -Name $c.Name -Status 'ÉCHEC' -Detail $c.Detail }
        }
        $phase = 'critical'
        throw ("Source officielle introuvable pour : {0}. Arrêt avant toute écriture sur la clé." -f (($critical | ForEach-Object Name) -join ', '))
    }

    # Clé en FAT32 (ancienne clé, ou Ventoy installé avec /FS:FAT32) : aucun fichier de 4 Go ou plus.
    # Sans ce contrôle, l'ISO de Windows échoue après de longues minutes de téléchargement.
    if ($drive.FileSystem -match 'FAT32|^vfat$') {
        foreach ($p in $plans) {
            if ($p.Item.Type -in @('WindowsIso', 'LinuxIso') -and $p.NewBytes -ge 4GB -and $p.Status -notin @('A_JOUR', 'INTROUVABLE')) {
                $p.Status = 'INTROUVABLE'
                $p.Detail = ("La clé est en FAT32 (fichiers limités à 4 Go) : {0} ({1}) ne peut pas y être copié. Réinstallez Ventoy en exFAT (case « Clé neuve », efface la clé) ou utilisez une autre clé." -f $p.Name, (Format-KitSize $p.NewBytes))
                Write-KitLog -Level ERROR -Message $p.Detail
            }
        }
    }

    # ------------------------------------------------------------------ 3. budget
    $phase = 'budget'
    $plans = Select-KitBudget -Plans $plans -FreeBytes (Get-KitFreeSpace -Root $keyRoot) -MarginBytes $marginBytes
    Show-KitBudget -Plans $plans -FreeBytes (Get-KitFreeSpace -Root $keyRoot) -MarginBytes $marginBytes

    # Images personnelles (Windows 7, 8.1…) : copiées après les éléments du profil
    # (séparateur « | » depuis l'assistant ; un tableau PowerShell est aussi accepté)
    $personalIsos = @($IsoPersonnelle | ForEach-Object { $_ -split '\|' } | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
    $addPersonal = {
        foreach ($iso in $personalIsos) {
            $r = Copy-KitPersonalIso -Path $iso -KeyRoot $keyRoot -FileSystem $drive.FileSystem -MarginBytes $marginBytes -DryRun:$DryRun
            $st = $(if ($r.Status -eq 'ÉCHEC') { 'ÉCHEC' } else { 'OK' })
            Add-KitResult -Name ("ISO perso {0}" -f $r.Name) -Status $st -Detail $r.Detail -SizeMB ($r.Bytes / 1MB)
        }
    }

    if ($DryRun) {
        foreach ($p in $plans) {
            switch ($p.Decision) {
                'ACCEPTÉ' {
                    $what = 'à télécharger'
                    if ($p.Status -eq 'CACHE') { $what = 'complet en cache, à mettre en place' }
                    Add-KitResult -Name $p.Name -Status 'OK' -Detail ("{0} ({1}) {2}" -f $what, $p.SizeSource, $p.Version) -SizeMB ($p.NewBytes / 1MB)
                }
                'À JOUR' { Add-KitResult -Name $p.Name -Status 'OK' -Detail "déjà à jour $($p.Version)" -SizeMB ($p.NewBytes / 1MB) }
                'ÉCHEC'  { Add-KitResult -Name $p.Name -Status 'ÉCHEC' -Detail $p.Detail }
                default  { Add-KitResult -Name $p.Name -Status 'IGNORÉ' -Detail $p.Detail -SizeMB ($p.NewBytes / 1MB) }
            }
        }
        & $addPersonal
        $freeAfter = Get-KitFreeSpace -Root $keyRoot
        $exitCode = Show-KitReport -FreeBeforeBytes $freeBefore -FreeAfterBytes $freeAfter -DryRun
        exit $exitCode
    }

    # ------------------------------------------------------------------ 4-5. téléchargement + mise en place
    $phase = 'build'
    Write-KitLog -Level STEP -Message '3. Téléchargement et mise en place (par priorité)'
    foreach ($p in $plans) {
        # Attention : un « continue » placé dans un switch ne ferait que sortir du switch.
        # On utilise donc des if pour passer réellement à l'élément suivant.
        if ($p.Decision -eq 'À JOUR') {
            Add-KitResult -Name $p.Name -Status 'OK' -Detail "déjà à jour $($p.Version)" -SizeMB ($p.NewBytes / 1MB)
            continue
        }
        if ($p.Decision -eq 'ÉCHEC') {
            Add-KitResult -Name $p.Name -Status 'ÉCHEC' -Detail $p.Detail
            continue
        }
        if ($p.Decision -ne 'ACCEPTÉ') {
            Add-KitResult -Name $p.Name -Status 'IGNORÉ' -Detail $p.Detail -SizeMB ($p.NewBytes / 1MB)
            continue
        }
        try {
            Write-KitLog -Level STEP -Message ("--- {0} {1}" -f $p.Name, $p.Version)
            # L'espace est remesuré juste avant : jamais de dépassement, même si l'estimation était fausse
            $need = Get-KitPlanNeed -Plan $p
            $free = Get-KitFreeSpace -Root $keyRoot
            if ($need -gt ($free - $marginBytes)) {
                Add-KitResult -Name $p.Name -Status 'IGNORÉ' -Detail ("Place insuffisante : besoin {0}, libre {1} (marge {2})" -f (Format-KitSize $need), (Format-KitSize $free), (Format-KitSize $marginBytes))
                continue
            }
            if ($p.Status -eq 'CACHE') { $stage = Get-KitStageDir -CacheRoot $cacheRoot -Name $p.Name }
            else { $stage = Save-KitPlan -Plan $p -CacheRoot $cacheRoot -ToolsDir $toolsDir -OfficeConfigPath $officeConfig }

            $prefix = $p.Item.TargetDir.TrimEnd('/') + '/'
            if ($p.Item.Type -eq 'WindowsIso') {
                # Dans ISO/ ne sont gérés que les fichiers du kit : on limite la portée à son ISO
                $prefix = $p.Item.TargetDir.TrimEnd('/') + '/' + [IO.Path]::GetFileNameWithoutExtension($p.Item.FileName)
            }
            $res = Sync-KitStage -StageDir $stage -KeyRoot $keyRoot -TargetDir $p.Item.TargetDir -Manifest $manifest -ObsoleteScope @($prefix)
            Write-KitManifest -KeyRoot $keyRoot -Manifest $manifest
            if ($res.Conflicts.Count -gt 0) {
                Add-KitResult -Name $p.Name -Status 'ÉCHEC' -Detail ("Fichier(s) personnel(s) au même emplacement, non remplacé(s) : {0}" -f ($res.Conflicts -join ', '))
            }
            else {
                $sizeMB = (Get-KitManagedSize -KeyRoot $keyRoot -Manifest $manifest -Prefix $prefix) / 1MB
                Add-KitResult -Name $p.Name -Status 'OK' -Detail ("{0} en place ({1} écrit(s), {2} ancien(s) supprimé(s))" -f $p.Version, $res.Moved, $res.Removed) -SizeMB $sizeMB
            }
        }
        catch {
            # Source « manifeste winget » refusée par l'éditeur (téléchargement direct interdit, 403…) :
            # le logiciel reste au catalogue et la post-installation l'installe en ligne (winget)
            if ($p.Source -and $p.Source.PSObject.Properties['Manifest'] -and $_.Exception.Message -match '403|404|page web') {
                Add-KitResult -Name $p.Name -Status 'IGNORÉ' -Detail ("téléchargement direct refusé par l'éditeur : installé en ligne sur le poste (winget) — {0}" -f $_.Exception.Message)
            }
            else { Add-KitResult -Name $p.Name -Status 'ÉCHEC' -Detail $_.Exception.Message }
        }
    }

    if ($personalIsos.Count -gt 0) {
        Write-KitLog -Level STEP -Message '--- Images personnelles'
        & $addPersonal
    }

    # ------------------------------------------------------------------ 6. post-installation, LISEZMOI, Ventoy
    Write-KitLog -Level STEP -Message '4. Post-installation, catalogue, LISEZMOI, modèle Ventoy'
    try {
        $gen = Join-Path $cacheRoot '_kit'
        if (Test-Path -LiteralPath $gen) { Remove-Item -LiteralPath $gen -Recurse -Force }
        New-Item -ItemType Directory -Path $gen -Force | Out-Null
        # Clé double système : la post-installation de CHAQUE système présent sur la clé est embarquée
        # (clé Windows avec Ubuntu => dossier linux/ ; clé Linux avec Windows 11 => postinstall/ et ventoy/)
        # (copiée en dernier, la post-installation du système principal garde son LISEZMOI)
        $mainPayload = $(if ($config.ContainsKey('Payload')) { $config.Payload } else { 'payload/windows' })
        $onKey = @($plans | Where-Object { $_.Decision -in @('ACCEPTÉ', 'À JOUR') } | ForEach-Object { $_.Item.Type })
        # ISO déjà sur la clé (préparation précédente, éventuellement depuis l'autre système) comprises
        $managedIsos = @($manifest.Keys | Where-Object { $_ -match '\.iso$' })
        $payloadRels = @()
        if ($onKey -contains 'LinuxIso' -or @($managedIsos | Where-Object { $_ -like 'ISO/Linux/*' }).Count -gt 0) { $payloadRels += 'payload/linux' }
        if ($onKey -contains 'WindowsIso' -or @($managedIsos | Where-Object { $_ -match '^ISO/Windows[^/]*\.iso$' }).Count -gt 0) { $payloadRels += 'payload/windows' }
        $payloadRels = @($payloadRels | Where-Object { $_ -ne $mainPayload }) + @($mainPayload)
        foreach ($rel in $payloadRels) {
            Copy-Item -Path (Join-Path (Join-Path $kitRoot $rel) '*') -Destination $gen -Recurse -Force
        }
        # Assistant universel (même page que pour créer la clé) à côté de chaque post-installation
        $page = Join-Path $kitRoot 'web/alchemist.html'
        foreach ($sub in @('postinstall', 'linux')) {
            if ((Test-Path -LiteralPath $page) -and (Test-Path -LiteralPath (Join-Path $gen $sub))) { Copy-Item -LiteralPath $page -Destination (Join-Path $gen $sub) -Force }
        }
        # Scripts Linux : fins de ligne LF, même si la copie du kit les a converties en CRLF
        # (Git pour Windows, archive décompressée par un outil Windows) ; bash échouerait sinon
        # (filtre par extension : sous Windows PowerShell 5.1, -Include est ignoré avec -LiteralPath)
        foreach ($sh in @(Get-ChildItem -LiteralPath $gen -Recurse -File | Where-Object { $_.Extension -eq '.sh' })) {
            $texte = [IO.File]::ReadAllText($sh.FullName)
            if ($texte.Contains("`r")) { [IO.File]::WriteAllText($sh.FullName, $texte.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false))) }
        }
        $tz = 'Greenwich Standard Time'
        if ($config.ContainsKey('TimeZone')) { $tz = $config.TimeZone }
        # Chaque post-installation reçoit le format de son système (clé double système)
        $tzWindows = ConvertTo-KitTimeZone -Id $tz -To Windows
        if (-not $tzWindows) { $tzWindows = 'Greenwich Standard Time' }
        $tzLinux = ConvertTo-KitTimeZone -Id $tz -To Iana
        if (Test-Path -LiteralPath (Join-Path $gen 'postinstall')) {
            # Windows : version embarquée et catalogue de la post-installation
            [IO.File]::WriteAllText((Join-Path $gen 'postinstall/VERSION'), "$kitVersion`n", (New-Object Text.UTF8Encoding($false)))
            [void](New-KitCatalogue -Items $allItems -KeyRoot $keyRoot -Destination (Join-Path $gen 'postinstall/catalogue.json') -ProfileName $Profil -TimeZone $tzWindows -DevDrive ($config.ContainsKey('DevDrive') -and [bool]$config.DevDrive))
        }
        if (Test-Path -LiteralPath (Join-Path $gen 'linux')) {
            # Linux : profil d'usage lu par le script de post-installation
            $conf = @("KIT_VERSION=$kitVersion", "KIT_PROFIL=$Profil", "KIT_USAGE=$($config.Usage)", "KIT_LANGUE=$Langue", "KIT_TZ=$tzLinux")
            [IO.File]::WriteAllText((Join-Path $gen 'linux/kit.conf'), (($conf -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
        }

        # Jetons des modèles (nom de l'ISO, langue, clavier, fuseau) remplacés dans les fichiers texte
        $isoItem = @($allItems | Where-Object { $_.Type -eq 'WindowsIso' -and [string]$_['FidoWin'] -ne '10' }) | Select-Object -First 1
        $iso10Item = @($allItems | Where-Object { $_.Type -eq 'WindowsIso' -and [string]$_['FidoWin'] -eq '10' }) | Select-Object -First 1
        $tokens = @{
            '{{ISO_NAME}}'     = $(if ($isoItem) { [string]$isoItem.FileName } else { '' })
            '{{ISO_NAME_W10}}' = $(if ($iso10Item) { [string]$iso10Item.FileName } else { 'Windows10_x64.iso' })
            '{{UI_LANG}}'      = $(if ($langInfo) { $langInfo.UILang } else { 'fr-FR' })
            '{{INPUT_LOCALE}}' = $(if ($langInfo) { $langInfo.InputLocale } else { '040c:0000040c' })
            '{{TIMEZONE}}'     = $tzWindows
            '{{KIT_VERSION}}'  = $kitVersion
        }
        foreach ($tf in @(Get-ChildItem -LiteralPath $gen -Recurse -File | Where-Object { $_.Extension -in @('.xml', '.json', '.txt', '.md') })) {
            $content = [IO.File]::ReadAllText($tf.FullName)
            if ($content -notmatch '\{\{[A-Z0-9_]+\}\}') { continue }
            foreach ($k in $tokens.Keys) { $content = $content.Replace($k, $tokens[$k]) }
            $bom = ($tf.Extension -eq '.txt')
            [IO.File]::WriteAllText($tf.FullName, $content, (New-Object Text.UTF8Encoding($bom)))
        }

        # ventoy.json : on ne remplace jamais un fichier de configuration Ventoy personnel
        $ventoyJson = 'ventoy/ventoy.json'
        if ((Test-Path -LiteralPath (Join-Path $gen 'ventoy/ventoy.json')) -and (Test-Path -LiteralPath (Join-Path $keyRoot 'ventoy/ventoy.json')) -and -not $manifest.ContainsKey($ventoyJson)) {
            Remove-Item -LiteralPath (Join-Path $gen 'ventoy/ventoy.json') -Force
            Write-KitLog -Level WARN -Message "Un ventoy.json personnel existe : il est conservé. Pour proposer l'installation hors ligne, ajoutez-y le bloc « auto_install » de payload\ventoy\ventoy.json."
        }
        $res = Sync-KitStage -StageDir $gen -KeyRoot $keyRoot -TargetDir '' -Manifest $manifest -ObsoleteScope @('postinstall/', 'ventoy/script/', 'linux/')
        Write-KitManifest -KeyRoot $keyRoot -Manifest $manifest
        if ($res.Conflicts.Count -gt 0) {
            Add-KitResult -Name 'Post-installation' -Status 'ÉCHEC' -Detail ("Conflit(s) : {0}" -f ($res.Conflicts -join ', '))
        }
        else {
            Add-KitResult -Name 'Post-installation' -Status 'OK' -Detail ((@(Get-ChildItem -LiteralPath $keyRoot -Directory | Where-Object { $_.Name -in @('postinstall', 'linux', 'ventoy') } | ForEach-Object Name) -join ', ') + ', LISEZMOI')
        }
    }
    catch {
        Add-KitResult -Name 'Post-installation' -Status 'ÉCHEC' -Detail $_.Exception.Message
    }

    Sync-KitVolume -Root $keyRoot
    $freeAfter = Get-KitFreeSpace -Root $keyRoot
    $exitCode = Show-KitReport -FreeBeforeBytes $freeBefore -FreeAfterBytes $freeAfter
}
catch {
    Write-KitLog -Level ERROR -Message $_.Exception.Message
    Write-KitLog -Level ERROR -Message ("Emplacement : {0}" -f $_.InvocationInfo.PositionMessage)
    if ($phase -eq 'critical') { $exitCode = 3 } else { $exitCode = 2 }
    try { if ($freeBefore -ge 0) { $freeAfter = Get-KitFreeSpace -Root $keyRoot } } catch { $freeAfter = -1 }
    [void](Show-KitReport -FreeBeforeBytes $freeBefore -FreeAfterBytes $freeAfter -DryRun:$DryRun)
}
finally {
    if ($buildLock) {
        Set-KitKeepAwake -Enabled $false -Confirm:$false
        try { $buildLock.ReleaseMutex() } catch { Write-Verbose 'Verrou déjà libéré.' }
        $buildLock.Dispose()
    }
}
exit $exitCode
