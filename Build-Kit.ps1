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
.PARAMETER ListerProfils
    Affiche les profils disponibles et quitte.
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
.PARAMETER CachePath
    Dossier de préparation (défaut : cache\ à côté de ce script). Sur le même volume que la
    clé, la mise en place est un simple déplacement.
.PARAMETER LogFile
    Chemin imposé du journal (utilisé par l'assistant graphique pour l'afficher en direct).

.EXAMPLE
    .\Build-Kit.ps1 -DryRun
.EXAMPLE
    .\Build-Kit.ps1 -Profil windows11-bureautique -DriveLetter E
.EXAMPLE
    .\Build-Kit.ps1 -Only Chrome,Firefox -SauvegardeVers D:\Sauvegardes

.NOTES
    Codes de sortie : 0 = OK, 1 = au moins un élément en ÉCHEC, 2 = clé invalide ou erreur
    générale, 3 = source officielle introuvable pour le système ou Office (arrêt).
    Compatible Windows PowerShell 5.1 et PowerShell 7.
#>
[CmdletBinding()]
param(
    [string] $Profil = 'windows11-bureautique',
    [switch] $ListerProfils,
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
    [string] $CachePath,
    [string] $LogFile
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
foreach ($m in @('Report', 'Drive', 'Budget', 'Download', 'Sync', 'Backup')) {
    Import-Module (Join-Path $kitRoot "modules\$m.psm1") -Force -DisableNameChecking
}

# ---------------------------------------------------------------------- profils disponibles
$profileDir = Join-Path $kitRoot 'config\profils'
if ($ListerProfils) {
    foreach ($pf in @(Get-ChildItem -LiteralPath $profileDir -Filter '*.psd1' | Sort-Object Name)) {
        $d = Import-PowerShellDataFile -Path $pf.FullName
        Write-Host ("{0,-28} {1}" -f $pf.BaseName, $d.Description)
    }
    exit 0
}

$exitCode = 0
$freeBefore = -1.0
$freeAfter = -1.0
$phase = 'init'
[void](Initialize-KitLog -LogDirectory (Join-Path $kitRoot 'logs') -LogFile $LogFile)

try {
    Write-KitLog -Level STEP -Message ("Kit Ventoy v{2} — {0}{1}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $(if ($DryRun) { ' — MODE SIMULATION' } else { '' }), $kitVersion)
    Write-KitLog -Message ("PowerShell {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
    Initialize-KitNetwork
    Set-KitSignaturePolicy -Disabled:$SansVerifSignature
    if ($SansVerifSignature) { Write-KitLog -Level WARN -Message 'Vérification des signatures Authenticode DÉSACTIVÉE (les SHA256 publiés restent contrôlés).' }

    # ------------------------------------------------------------------ configuration (profil)
    $profilePath = Join-Path $profileDir "$Profil.psd1"
    if (-not (Test-Path -LiteralPath $profilePath)) {
        $known = (@(Get-ChildItem -LiteralPath $profileDir -Filter '*.psd1') | ForEach-Object BaseName) -join ', '
        throw "Profil « $Profil » introuvable. Profils disponibles : $known"
    }
    $config = Import-PowerShellDataFile -Path $profilePath
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

    # ------------------------------------------------------------------ 1. clé
    $phase = 'drive'
    Write-KitLog -Level STEP -Message '1. Contrôle de la clé'
    if (-not $DriveLetter) {
        # Détection automatique : une seule clé « Ventoy » branchée => on la prend
        $candidates = @(Find-KitVentoyDrive -ExpectedLabel $config.VolumeLabel)
        if ($candidates.Count -eq 0) { throw "Aucune clé « $($config.VolumeLabel) » détectée. Branchez la clé Ventoy (installée avec Ventoy2Disk) ou précisez -DriveLetter." }
        if ($candidates.Count -gt 1) { throw ("Plusieurs clés Ventoy détectées ({0}) : précisez -DriveLetter." -f (($candidates | ForEach-Object Root) -join ', ')) }
        $DriveLetter = $candidates[0].Letter
        Write-KitLog -Message ("Clé Ventoy détectée automatiquement : {0}" -f $candidates[0].Root)
    }
    $drive = Test-KitDrive -DriveLetter ([char]$DriveLetter) -ExpectedLabel $config.VolumeLabel -MinFreeBytes $marginBytes
    $keyRoot = $drive.Root
    $freeBefore = $drive.FreeBytes

    $cacheRoot = $CachePath
    if (-not $cacheRoot) { $cacheRoot = Join-Path $kitRoot 'cache' }
    $cacheRoot = [IO.Path]::GetFullPath($cacheRoot)
    if (-not $DryRun -and -not (Test-Path -LiteralPath $cacheRoot)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
    if ([IO.Path]::GetPathRoot($cacheRoot) -ne $keyRoot) {
        Write-KitLog -Level WARN -Message "Le cache ($cacheRoot) n'est pas sur la clé : la mise en place sera une copie (plus lente)."
    }
    # Outils (Fido, descripteur Office) : hors clé en DryRun
    $toolsDir = Join-Path $cacheRoot '_outils'
    if ($DryRun) { $toolsDir = Join-Path ([IO.Path]::GetTempPath()) 'kit-ventoy-outils' }
    $officeConfig = Join-Path $kitRoot ('config\' + $(if ($config.ContainsKey('OfficeConfig')) { $config.OfficeConfig } else { 'office-config.xml' }))
    $manifest = Read-KitManifest -KeyRoot $keyRoot
    Write-KitLog -Message ("MANIFEST : {0} fichier(s) déjà gérés par le kit" -f $manifest.Count)

    # ------------------------------------------------------------------ 0. sauvegarde (option)
    if ($SauvegardeVers) {
        $phase = 'backup'
        # Le dossier du kit lui-même (s'il est sur la clé) n'est pas une donnée à sauvegarder
        $exclude = @()
        if ([IO.Path]::GetPathRoot($kitRoot) -ieq $keyRoot) { $exclude += (Split-Path -Leaf $kitRoot) }
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

    if (-not $SkipDownload -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget est introuvable. Installez « App Installer » depuis le Microsoft Store, ou utilisez -SkipDownload."
    }

    # ------------------------------------------------------------------ 2. sources
    $phase = 'resolve'
    Write-KitLog -Level STEP -Message '2. Résolution des sources officielles'
    $plans = @()
    $index = 0
    foreach ($it in $items) {
        $plan = New-KitPlan -Item $it -Index $index
        $index++
        try {
            Resolve-KitPlan -Plan $plan -KeyRoot $keyRoot -CacheRoot $cacheRoot -ToolsDir $toolsDir -FidoUrl $config.FidoUrl -Manifest $manifest -WindowsIsoUrl $WindowsIsoUrl -SkipDownload:$SkipDownload
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
    $critical = @($plans | Where-Object { $_.Status -eq 'INTROUVABLE' -and $_.Item.Type -in @('WindowsIso', 'Office') })
    if ($critical.Count -gt 0 -and -not $DryRun) {
        foreach ($c in $plans) {
            if ($c.Status -eq 'INTROUVABLE') { Add-KitResult -Name $c.Name -Status 'ÉCHEC' -Detail $c.Detail }
        }
        $phase = 'critical'
        throw ("Source officielle introuvable pour : {0}. Arrêt avant toute écriture sur la clé." -f (($critical | ForEach-Object Name) -join ', '))
    }

    # ------------------------------------------------------------------ 3. budget
    $phase = 'budget'
    $plans = Select-KitBudget -Plans $plans -FreeBytes (Get-KitFreeSpace -DriveLetter $DriveLetter) -MarginBytes $marginBytes
    Show-KitBudget -Plans $plans -FreeBytes (Get-KitFreeSpace -DriveLetter $DriveLetter) -MarginBytes $marginBytes

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
        $freeAfter = Get-KitFreeSpace -DriveLetter $DriveLetter
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
            $free = Get-KitFreeSpace -DriveLetter $DriveLetter
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
            Add-KitResult -Name $p.Name -Status 'ÉCHEC' -Detail $_.Exception.Message
        }
    }

    # ------------------------------------------------------------------ 6. post-installation, LISEZMOI, Ventoy
    Write-KitLog -Level STEP -Message '4. Post-installation, catalogue, LISEZMOI, modèle Ventoy'
    try {
        $gen = Join-Path $cacheRoot '_kit'
        if (Test-Path -LiteralPath $gen) { Remove-Item -LiteralPath $gen -Recurse -Force }
        New-Item -ItemType Directory -Path $gen -Force | Out-Null
        $payload = Join-Path $kitRoot $(if ($config.ContainsKey('Payload')) { $config.Payload } else { 'payload\windows' })
        Copy-Item -Path (Join-Path $payload '*') -Destination $gen -Recurse -Force
        # Version du kit embarquée sur la clé (affichée par l'assistant du poste)
        [IO.File]::WriteAllText((Join-Path $gen 'postinstall\VERSION'), "$kitVersion`n", (New-Object Text.UTF8Encoding($false)))
        $tz = 'Greenwich Standard Time'
        if ($config.ContainsKey('TimeZone')) { $tz = $config.TimeZone }
        [void](New-KitCatalogue -Items $allItems -KeyRoot $keyRoot -Destination (Join-Path $gen 'postinstall\catalogue.json') -ProfileName $Profil -TimeZone $tz)

        # Jetons des modèles (nom de l'ISO, langue, clavier, fuseau) remplacés dans les fichiers texte
        $isoItem = @($allItems | Where-Object { $_.Type -eq 'WindowsIso' }) | Select-Object -First 1
        $tokens = @{
            '{{ISO_NAME}}'     = $(if ($isoItem) { [string]$isoItem.FileName } else { '' })
            '{{UI_LANG}}'      = $(if ($langInfo) { $langInfo.UILang } else { 'fr-FR' })
            '{{INPUT_LOCALE}}' = $(if ($langInfo) { $langInfo.InputLocale } else { '040c:0000040c' })
            '{{TIMEZONE}}'     = $tz
            '{{KIT_VERSION}}'  = $kitVersion
        }
        foreach ($tf in @(Get-ChildItem -LiteralPath $gen -Recurse -File -Include '*.xml', '*.json', '*.txt')) {
            $content = [IO.File]::ReadAllText($tf.FullName)
            if ($content -notmatch '\{\{[A-Z_]+\}\}') { continue }
            foreach ($k in $tokens.Keys) { $content = $content.Replace($k, $tokens[$k]) }
            $bom = ($tf.Extension -eq '.txt')
            [IO.File]::WriteAllText($tf.FullName, $content, (New-Object Text.UTF8Encoding($bom)))
        }

        # ventoy.json : on ne remplace jamais un fichier de configuration Ventoy personnel
        $ventoyJson = 'ventoy/ventoy.json'
        if ((Test-Path -LiteralPath (Join-Path $keyRoot 'ventoy\ventoy.json')) -and -not $manifest.ContainsKey($ventoyJson)) {
            Remove-Item -LiteralPath (Join-Path $gen 'ventoy\ventoy.json') -Force
            Write-KitLog -Level WARN -Message "Un ventoy.json personnel existe : il est conservé. Pour proposer l'installation hors ligne, ajoutez-y le bloc « auto_install » de payload\ventoy\ventoy.json."
        }
        $res = Sync-KitStage -StageDir $gen -KeyRoot $keyRoot -TargetDir '' -Manifest $manifest -ObsoleteScope @('postinstall/', 'ventoy/script/')
        Write-KitManifest -KeyRoot $keyRoot -Manifest $manifest
        if ($res.Conflicts.Count -gt 0) {
            Add-KitResult -Name 'Post-installation' -Status 'ÉCHEC' -Detail ("Conflit(s) : {0}" -f ($res.Conflicts -join ', '))
        }
        else {
            Add-KitResult -Name 'Post-installation' -Status 'OK' -Detail 'postinstall\, catalogue.json, LISEZMOI.txt, ventoy\'
        }
    }
    catch {
        Add-KitResult -Name 'Post-installation' -Status 'ÉCHEC' -Detail $_.Exception.Message
    }

    $freeAfter = Get-KitFreeSpace -DriveLetter $DriveLetter
    $exitCode = Show-KitReport -FreeBeforeBytes $freeBefore -FreeAfterBytes $freeAfter
}
catch {
    Write-KitLog -Level ERROR -Message $_.Exception.Message
    Write-KitLog -Level ERROR -Message ("Emplacement : {0}" -f $_.InvocationInfo.PositionMessage)
    if ($phase -eq 'critical') { $exitCode = 3 } else { $exitCode = 2 }
    try { if ($freeBefore -ge 0) { $freeAfter = Get-KitFreeSpace -DriveLetter $DriveLetter } } catch { $freeAfter = -1 }
    [void](Show-KitReport -FreeBeforeBytes $freeBefore -FreeAfterBytes $freeAfter -DryRun:$DryRun)
}
exit $exitCode
