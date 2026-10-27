<#
.SYNOPSIS
    Tests du moteur Alchemist, sans réseau ni clé USB : profils, langues, budget, mise en place sur
    la clé (MANIFEST, fichiers personnels), catalogue de la post-installation, détection Ventoy.

.DESCRIPTION
    Fonctionne sous Windows (PowerShell 5.1 ou 7) et sous Linux (PowerShell 7). Aucun module à
    installer : chaque test est un bloc qui lève une exception en cas d'échec.
    La « clé » est un dossier temporaire : rien n'est écrit ailleurs.

.EXAMPLE
    pwsh ./tests/moteur/Test-Moteur.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tests\moteur\Test-Moteur.ps1

.NOTES
    Code de sortie : nombre de tests en échec (0 = tout est passé).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($m in @('Report', 'Drive', 'Budget', 'Download', 'Sync', 'Backup', 'Ventoy', 'Profile')) {
    Import-Module (Join-Path $kitRoot "modules/$m.psm1") -Force -DisableNameChecking
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('alchemist-tests-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
[void](Initialize-KitLog -LogDirectory (Join-Path $work 'logs'))
$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]

function Invoke-Essai {
    <#
    .SYNOPSIS
        Exécute un test et note son résultat.
    #>
    param([Parameter(Mandatory)] [string] $Nom, [Parameter(Mandatory)] [scriptblock] $Corps)
    try {
        $null = & $Corps
        $script:Passed++
        Write-Host ("  OK     {0}" -f $Nom) -ForegroundColor Green
    }
    catch {
        $script:Failed.Add($Nom)
        Write-Host ("  ÉCHEC  {0}`n         {1}" -f $Nom, $_.Exception.Message) -ForegroundColor Red
    }
}

function Assert-Vrai {
    <#
    .SYNOPSIS
        Lève une exception si la condition est fausse.
    #>
    param([Parameter(Mandatory)] [AllowNull()] $Condition, [Parameter(Mandatory)] [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Initialize-CleFactice {
    <#
    .SYNOPSIS
        Dossier vide jouant le rôle de la racine de la clé.
    #>
    $d = Join-Path $work ('cle-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Write-Fichier {
    <#
    .SYNOPSIS
        Écrit un petit fichier texte (dossiers créés au besoin).
    #>
    param([string] $Chemin, [string] $Texte)
    $dir = Split-Path -Parent $Chemin
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Chemin, $Texte)
}

$profileDir = Join-Path $kitRoot 'config/profils'
$profils = Get-KitProfileList -Directory $profileDir   # déjà un tableau (ne pas emboîter avec @())

# =============================================================================== profils
Write-Host "`n== Profils" -ForegroundColor Cyan

Invoke-Essai 'Quatre profils : Windows et Linux, bureautique et développement' {
    foreach ($s in 'Windows', 'Linux') {
        foreach ($u in 'Bureautique', 'Developpement') {
            Assert-Vrai (@($profils | Where-Object { $_.Systeme -eq $s -and $_.Usage -eq $u }).Count -eq 1) "profil $s / $u absent ou en double"
        }
    }
}

foreach ($p in $profils) {
    Invoke-Essai ("{0} : éléments complets et cohérents" -f $p.Name) {
        $items = @($p.Data.Items)
        Assert-Vrai ($items.Count -gt 0) 'aucun élément'
        $noms = @($items | ForEach-Object { $_.Name })
        $doublons = @($noms | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
        Assert-Vrai ($doublons.Count -eq 0) ("noms en double : {0}" -f ($doublons -join ', '))
        foreach ($it in $items) {
            foreach ($champ in 'Name', 'Type', 'TargetDir', 'Priority') { Assert-Vrai ($it.ContainsKey($champ)) "$($it['Name']) : champ $champ manquant" }
            Assert-Vrai ($it.Name -match '^[A-Za-z0-9_+.-]+$') "$($it.Name) : nom invalide (utilisé comme nom de dossier et par -Only)"
            Assert-Vrai ($it.TargetDir -notmatch '\\') "$($it.Name) : TargetDir doit utiliser « / »"
            switch ($it.Type) {
                'Winget' { Assert-Vrai ([string]$it['WingetId']) "$($it.Name) : WingetId manquant" }
                'GitHub' { Assert-Vrai ($it['Repo'] -and $it['AssetPattern']) "$($it.Name) : Repo / AssetPattern manquant" ; [void][regex]$it.AssetPattern }
                'Url' { Assert-Vrai (@($it['Files']).Count -gt 0) "$($it.Name) : Files vide"; foreach ($f in @($it.Files)) { Assert-Vrai ([string]$f.Url -match '^https://') "$($it.Name) : URL non HTTPS" } }
                'WindowsIso' { foreach ($c in 'FidoWin', 'FidoRel', 'FidoEd', 'FidoArch', 'FileName') { Assert-Vrai ($it.ContainsKey($c)) "$($it.Name) : $c manquant" } }
                'LinuxIso' { Assert-Vrai ($it['Distro'] -in @('Ubuntu', 'Debian', 'Mint', 'Fedora')) "$($it.Name) : Distro inconnue" }
                'Office' { Assert-Vrai ($it['ProductId'] -and $it['ChannelCabUrl'] -and $it['WingetId']) "$($it.Name) : ProductId / ChannelCabUrl / WingetId (repli en ligne) manquant" }
                default { throw "$($it.Name) : type inconnu $($it.Type)" }
            }
            if ($it.ContainsKey('Detection') -and $it.Detection) {
                Assert-Vrai ($it.Detection -match '^(reg|appx|c2r|file):.+') "$($it.Name) : règle de détection invalide « $($it.Detection) »"
                if ($it.Detection -like 'reg:*') { [void][regex]$it.Detection.Substring(4) }
            }
        }
        $defaut = @($items | Where-Object { -not ($_.ContainsKey('Default') -and -not $_.Default) })
        Assert-Vrai ($defaut.Count -gt 0) 'aucun élément coché par défaut'
        Assert-Vrai ($p.Data.Payload -and (Test-Path -LiteralPath (Join-Path $kitRoot $p.Data.Payload))) 'dossier Payload introuvable'
    }

    Invoke-Essai ("{0} : chaque langue est complète" -f $p.Name) {
        if (-not $p.Data.ContainsKey('Langues')) { return }
        Assert-Vrai ($p.Data.Langues.ContainsKey($p.Data.LangueDefaut)) 'LangueDefaut absente de Langues'
        foreach ($code in $p.Data.Langues.Keys) {
            foreach ($c in 'Label', 'FidoLang', 'Office', 'UILang', 'InputLocale', 'IsoSuffix') {
                Assert-Vrai ($p.Data.Langues[$code].ContainsKey($c)) "langue $code : $c manquant"
            }
            Assert-Vrai ($p.Data.Langues[$code].InputLocale -match '^[0-9a-f]{4}:[0-9a-f]{8}$') "langue $code : InputLocale invalide"
        }
    }
}

Invoke-Essai 'Héritage : le profil développement reprend le profil bureautique sans le modifier' {
    $bur = Get-KitProfile -Directory $profileDir -Name 'windows11-bureautique'
    $dev = Get-KitProfile -Directory $profileDir -Name 'windows11-developpement'
    $nb = @($bur.Items | ForEach-Object Name)
    $nd = @($dev.Items | ForEach-Object Name)
    Assert-Vrai (@($nb | Where-Object { $_ -notin $nd }).Count -le 5) 'trop d''éléments du parent perdus'
    Assert-Vrai ($nd.Count -gt $nb.Count) 'aucun élément ajouté par le profil développement'
    $dev.Items[0].Name = 'modifie'
    Assert-Vrai ((Get-KitProfile -Directory $profileDir -Name 'windows11-bureautique').Items[0].Name -ne 'modifie') 'copie superficielle : le parent est modifié'
}

Invoke-Essai 'Build-Kit -ListerElements : JSON valide pour chaque profil' {
    $ps = (Get-Process -Id $PID).Path
    foreach ($p in $profils) {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kitRoot 'Build-Kit.ps1') -Profil $p.Name -ListerElements
        Assert-Vrai ($LASTEXITCODE -eq 0) "$($p.Name) : code $LASTEXITCODE"
        $j = ($out | Out-String) | ConvertFrom-Json
        Assert-Vrai ($j.Profil -eq $p.Name -and @($j.Items).Count -eq @($p.Data.Items).Count) "$($p.Name) : contenu inattendu"
    }
}

Invoke-Essai 'Build-Kit : nom d''élément inconnu refusé avant toute action' {
    $ps = (Get-Process -Id $PID).Path
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kitRoot 'Build-Kit.ps1') -Systeme Linux -Usage Bureautique -Only 'Ubuntu,Inexistant' -KeyPath $work -LogFile (Join-Path $work 'inconnu.log') 2>&1 | Out-String
    Assert-Vrai ($LASTEXITCODE -eq 2) "code $LASTEXITCODE au lieu de 2"
    Assert-Vrai ($out -match 'Inexistant') 'le nom fautif n''est pas cité'
}

# =============================================================================== langues de l'interface
Write-Host "`n== Fichiers de langue" -ForegroundColor Cyan
foreach ($dir in @('lang', 'payload/windows/postinstall/lang')) {
    Invoke-Essai ("{0} : mêmes clés en français et en anglais" -f $dir) {
        $fr = Import-PowerShellDataFile (Join-Path $kitRoot "$dir/fr.psd1")
        $en = Import-PowerShellDataFile (Join-Path $kitRoot "$dir/en.psd1")
        $manque = @($fr.Keys | Where-Object { -not $en.ContainsKey($_) }) + @($en.Keys | Where-Object { -not $fr.ContainsKey($_) })
        Assert-Vrai ($manque.Count -eq 0) ("clés manquantes : {0}" -f ($manque -join ', '))
        foreach ($k in $fr.Keys) {
            $nf = ([regex]::Matches([string]$fr[$k], '\{\d+\}')).Count
            $ne = ([regex]::Matches([string]$en[$k], '\{\d+\}')).Count
            Assert-Vrai ($nf -eq $ne) "$k : nombre de paramètres {n} différent (fr $nf, en $ne)"
        }
    }
}

# =============================================================================== payload
Write-Host "`n== Contenu copié sur la clé" -ForegroundColor Cyan
Invoke-Essai 'Scripts Linux en LF, avec shebang bash' {
    foreach ($sh in @(Get-ChildItem -LiteralPath $kitRoot -Recurse -File -Filter '*.sh' | Where-Object FullName -notmatch '[\\/](cache|logs|\.git)[\\/]')) {
        $t = [IO.File]::ReadAllText($sh.FullName)
        Assert-Vrai (-not $t.Contains("`r")) "$($sh.Name) : fins de ligne CRLF (bash échouera)"
        Assert-Vrai ($t.StartsWith('#!/usr/bin/env bash')) "$($sh.Name) : shebang manquant"
    }
}
Invoke-Essai 'Lanceurs Windows (.bat) en CRLF : cmd.exe gère mal les étiquettes en LF' {
    foreach ($b in @(Get-ChildItem -LiteralPath $kitRoot -Recurse -File | Where-Object { $_.Extension -eq '.bat' -and $_.FullName -notmatch '[\\/](cache|logs|\.git)[\\/]' })) {
        $t = [IO.File]::ReadAllText($b.FullName)
        Assert-Vrai ($t.Contains("`r`n") -and -not ($t -replace "`r`n", '').Contains("`n")) "$($b.Name) : fins de ligne LF"
    }
}
Invoke-Essai 'Modèles : tous les jetons {{…}} sont connus du moteur' {
    $connus = @('{{ISO_NAME}}', '{{ISO_NAME_W10}}', '{{UI_LANG}}', '{{INPUT_LOCALE}}', '{{TIMEZONE}}', '{{KIT_VERSION}}')
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $kitRoot 'payload') -Recurse -File | Where-Object { $_.Extension -in @('.xml', '.json', '.txt', '.md') })) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName), '\{\{[A-Z0-9_]+\}\}')) {
            Assert-Vrai ($m.Value -in $connus) "$($f.Name) : jeton inconnu $($m.Value)"
        }
    }
}
Invoke-Essai 'Fichiers XML et JSON de la clé bien formés' {
    # (filtre par extension : sous Windows PowerShell 5.1, -Include est ignoré avec -LiteralPath)
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $kitRoot 'payload'), (Join-Path $kitRoot 'config') -Recurse -File | Where-Object { $_.Extension -in @('.xml', '.json') })) {
        $t = [IO.File]::ReadAllText($f.FullName)
        if ($f.Extension -eq '.xml') { [void]([xml]$t) } else { [void]($t | ConvertFrom-Json) }
    }
}

# =============================================================================== utilitaires
Write-Host "`n== Empreintes et versions" -ForegroundColor Cyan
Invoke-Essai 'Find-KitChecksum : formats GNU, binaire et BSD' {
    $h = 'a' * 64
    $txt = "$h  ubuntu-24.04.3-desktop-amd64.iso`n$('b' * 64) *ubuntu-24.04.3-live-server-amd64.iso`r`nSHA256 (Fedora-Workstation-Live-43-1.6.x86_64.iso) = $('C' * 64)"
    $r = Find-KitChecksum -Text $txt -Pattern '^ubuntu-[\d.]+-desktop-amd64\.iso$'
    Assert-Vrai ($r -and $r.Sha256 -eq $h) 'format GNU'
    Assert-Vrai ((Find-KitChecksum -Text $txt -Pattern 'live-server').Sha256 -eq ('b' * 64)) 'format binaire (*)'
    Assert-Vrai ((Find-KitChecksum -Text $txt -Pattern '^Fedora-').Sha256 -eq ('c' * 64)) 'format BSD (minuscules)'
    Assert-Vrai ($null -eq (Find-KitChecksum -Text $txt -Pattern 'debian')) 'absent : $null attendu'
}
Invoke-Essai 'Manifeste winget : installeurs, valeurs générales héritées, sous-blocs ignorés' {
    $y = @(
        'PackageIdentifier: Editeur.Logiciel', 'Scope: machine', 'InstallerType: wix', 'InstallerSwitches:', '  Silent: /S', 'Installers:',
        '- Architecture: x64', '  InstallerUrl: https://exemple.org/l-x64.msi', ('  InstallerSha256: ' + ('A' * 64)),
        '  AppsAndFeaturesEntries:', '  - ProductCode: x', '    UpgradeCode: y', '  InstallerSwitches:', '    Custom: z',
        '- Architecture: x86', '  InstallerType: nullsoft', '  Scope: user', '  InstallerUrl: https://exemple.org/l-x86.exe', ('  InstallerSha256: ' + ('B' * 64)),
        'ManifestType: installer'
    ) -join "`n"
    $r = ConvertFrom-KitWingetInstallerYaml -Yaml $y
    Assert-Vrai (@($r).Count -eq 2) "installeurs lus : $(@($r).Count)"
    Assert-Vrai ($r[0].InstallerType -eq 'wix' -and $r[0].Scope -eq 'machine' -and $r[0].InstallerSha256 -eq ('A' * 64)) 'valeurs générales non héritées'
    Assert-Vrai ($r[1].InstallerType -eq 'nullsoft' -and $r[1].Scope -eq 'user') 'valeurs propres à l''installeur écrasées'
    Assert-Vrai (-not $r[0].ContainsKey('ProductCode')) 'sous-bloc lu comme installeur'
}
Invoke-Essai 'Format-KitSize lisible' {
    Assert-Vrai ((Format-KitSize (1.5 * 1GB)) -match '1[.,]5') (Format-KitSize (1.5 * 1GB))
}

# =============================================================================== budget
Write-Host "`n== Budget d'espace" -ForegroundColor Cyan
Invoke-Essai 'Priorités : le plus important d''abord, le reste ignoré faute de place, rien d''écrit en trop' {
    $mk = { param($n, $prio, $mo, $st) $p = New-KitPlan -Item @{ Name = $n; Priority = $prio; EstimatedSizeMB = $mo } -Index 0; $p.Status = $st; $p }
    $plans = @(
        (& $mk 'Gros' 7 6000 'A_TELECHARGER'), (& $mk 'Systeme' 1 5000 'A_TELECHARGER'),
        (& $mk 'Petit' 4 100 'A_TELECHARGER'), (& $mk 'Present' 2 3000 'A_JOUR'),
        (& $mk 'Poste' 3 900 'EN_LIGNE'), (& $mk 'Perdu' 3 10 'INTROUVABLE')
    )
    $r = Select-KitBudget -Plans $plans -FreeBytes (8GB) -MarginBytes (1GB)   # déjà un tableau
    $d = @{}; foreach ($p in $r) { $d[$p.Name] = $p.Decision }
    Assert-Vrai ($d.Systeme -eq 'ACCEPTÉ' -and $d.Petit -eq 'ACCEPTÉ') 'éléments prioritaires refusés'
    Assert-Vrai ($d.Gros -eq 'IGNORÉ') 'dépassement : Gros aurait dû être ignoré'
    Assert-Vrai ($d.Present -eq 'À JOUR' -and $d.Poste -eq 'IGNORÉ' -and $d.Perdu -eq 'ÉCHEC') 'statuts mal traduits'
    Assert-Vrai ($r[0].Name -eq 'Systeme') 'tri par priorité'
    $besoin = 0.0; foreach ($p in $r) { if ($p.Decision -eq 'ACCEPTÉ') { $besoin += Get-KitPlanNeed -Plan $p } }
    Assert-Vrai ($besoin -le 7GB) 'le total accepté dépasse l''espace disponible'
}
Invoke-Essai 'Téléchargement partiel déduit du besoin' {
    $p = New-KitPlan -Item @{ Name = 'Iso'; Priority = 1; EstimatedSizeMB = 1000 } -Index 0
    $p.Status = 'A_TELECHARGER'; $p.PartialBytes = 400MB
    Assert-Vrai ((Get-KitPlanNeed -Plan $p) -eq 600MB) 'besoin = taille − partiel'
}

# =============================================================================== mise en place sur la clé
Write-Host "`n== Mise en place sur la clé (MANIFEST)" -ForegroundColor Cyan
Invoke-Essai 'Première mise en place, puis relance sans rien réécrire, MANIFEST relu à l''identique' {
    $cle = Initialize-CleFactice; $stage = Join-Path $work 'stage1'
    Write-Fichier (Join-Path $stage 'a.txt') 'A'; Write-Fichier (Join-Path $stage 'sous/b.txt') 'B'
    $man = @{}
    $r = Sync-KitStage -StageDir $stage -KeyRoot $cle -TargetDir 'Logiciels/X' -Manifest $man -ObsoleteScope @('Logiciels/X/')
    Write-KitManifest -KeyRoot $cle -Manifest $man
    Assert-Vrai ($r.Moved -eq 2 -and $r.Conflicts.Count -eq 0) "écrits : $($r.Moved)"
    Assert-Vrai (Test-Path -LiteralPath (Join-Path $cle 'Logiciels/X/sous/b.txt')) 'fichier absent de la clé'
    Assert-Vrai (-not (Test-Path -LiteralPath $stage)) 'zone de préparation non vidée'
    $relu = Read-KitManifest -KeyRoot $cle
    Assert-Vrai ($relu.Count -eq 2 -and $relu['Logiciels/X/sous/b.txt'] -eq (Get-KitSha256 -Path (Join-Path $cle 'Logiciels/X/sous/b.txt'))) 'MANIFEST relu différent'
    $brut = [IO.File]::ReadAllText((Join-Path $cle 'MANIFEST.sha256'))
    Assert-Vrai (-not $brut.Contains("`r") -and $brut -match '^[0-9a-f]{64} \*Logiciels/X/a\.txt') 'MANIFEST hors format sha256sum'
    Write-Fichier (Join-Path $stage 'a.txt') 'A'; Write-Fichier (Join-Path $stage 'sous/b.txt') 'B'
    $r2 = Sync-KitStage -StageDir $stage -KeyRoot $cle -TargetDir 'Logiciels/X' -Manifest $relu -ObsoleteScope @('Logiciels/X/')
    Assert-Vrai ($r2.Moved -eq 0 -and $r2.Unchanged -eq 2 -and $r2.Removed -eq 0) 'relance : fichiers identiques réécrits'
}
Invoke-Essai 'Nouvelle version : l''ancienne est supprimée, jamais les fichiers personnels' {
    $cle = Initialize-CleFactice; $man = @{}
    $stage = Join-Path $work 'stage2'
    Write-Fichier (Join-Path $stage 'app-1.0.exe') 'v1'
    [void](Sync-KitStage -StageDir $stage -KeyRoot $cle -TargetDir 'Logiciels/App' -Manifest $man -ObsoleteScope @('Logiciels/App/'))
    Write-Fichier (Join-Path $cle 'Logiciels/App/mes-notes.txt') 'personnel'
    Write-Fichier (Join-Path $cle 'Photos/vacances.jpg') 'personnel'
    Write-Fichier (Join-Path $stage 'app-2.0.exe') 'v2'
    $r = Sync-KitStage -StageDir $stage -KeyRoot $cle -TargetDir 'Logiciels/App' -Manifest $man -ObsoleteScope @('Logiciels/App/')
    Assert-Vrai ($r.Removed -eq 1) 'ancienne version conservée'
    Assert-Vrai (-not (Test-Path -LiteralPath (Join-Path $cle 'Logiciels/App/app-1.0.exe'))) 'app-1.0 toujours là'
    Assert-Vrai ((Test-Path -LiteralPath (Join-Path $cle 'Logiciels/App/mes-notes.txt')) -and (Test-Path -LiteralPath (Join-Path $cle 'Photos/vacances.jpg'))) 'fichier personnel supprimé'
}
Invoke-Essai 'Fichier personnel au même nom : conflit signalé, fichier intact' {
    $cle = Initialize-CleFactice; $man = @{}
    Write-Fichier (Join-Path $cle 'postinstall/Lancer.bat') 'mon script'
    $stage = Join-Path $work 'stage3'
    Write-Fichier (Join-Path $stage 'postinstall/Lancer.bat') 'kit'
    $r = Sync-KitStage -StageDir $stage -KeyRoot $cle -TargetDir '' -Manifest $man -ObsoleteScope @('postinstall/')
    Assert-Vrai ($r.Conflicts.Count -eq 1) 'conflit non signalé'
    Assert-Vrai ([IO.File]::ReadAllText((Join-Path $cle 'postinstall/Lancer.bat')) -eq 'mon script') 'fichier personnel écrasé'
}
Invoke-Essai 'Image personnelle : format vérifié, copie contrôlée, jamais inscrite au MANIFEST' {
    $cle = Initialize-CleFactice
    $iso = Join-Path $work 'Win7.iso'; Write-Fichier $iso ('x' * 4096)
    $bad = Join-Path $work 'notes.docx'; Write-Fichier $bad 'x'
    Assert-Vrai ((Copy-KitPersonalIso -Path $bad -KeyRoot $cle).Status -eq 'ÉCHEC') 'format non Ventoy accepté'
    $r = Copy-KitPersonalIso -Path $iso -KeyRoot $cle
    Assert-Vrai ($r.Status -eq 'OK' -and (Test-Path -LiteralPath (Join-Path $cle 'ISO/Personnel/Win7.iso'))) "copie : $($r.Status) $($r.Detail)"
    Assert-Vrai ((Copy-KitPersonalIso -Path $iso -KeyRoot $cle).Status -eq 'À JOUR') 'recopie inutile'
    Assert-Vrai ((Read-KitManifest -KeyRoot $cle).Count -eq 0) 'image inscrite au MANIFEST'
}

# =============================================================================== catalogue
Write-Host "`n== Catalogue de la post-installation Windows" -ForegroundColor Cyan
Invoke-Essai 'Catalogue : chemins Windows, installeurs présents ou repli en ligne, pack Windows 7 exclu' {
    $cle = Initialize-CleFactice
    $items = @(
        @{ Name = 'Present'; Type = 'Winget'; TargetDir = 'Logiciels/Present'; WingetId = 'Edit.Present'; Order = 2 }
        @{ Name = 'Absent'; Type = 'Winget'; TargetDir = 'Logiciels/Absent'; WingetId = 'Edit.Absent'; Order = 1 }
        @{ Name = 'Portable'; Type = 'Winget'; TargetDir = 'Outils/Portable'; WingetId = 'Edit.Portable'; Extract = $true; Launcher = 'outil*.exe' }
        @{ Name = 'Office365'; Type = 'Office'; TargetDir = 'Bureautique/Office365'; WingetId = 'Microsoft.Office' }
        @{ Name = 'Win7'; Type = 'Url'; TargetDir = 'Logiciels/Win7'; Compat = @('7') }
        @{ Name = 'Windows11'; Type = 'WindowsIso'; TargetDir = 'ISO' }
    )
    Write-Fichier (Join-Path $cle 'Logiciels/Present/setup.msi') 'msi'
    Write-Fichier (Join-Path $cle 'Logiciels/Present/Present.source.json') '{"Version":"1.2","Installer":"setup.msi"}'
    Write-Fichier (Join-Path $cle 'Outils/Portable/Portable.source.json') '{"Version":"3"}'
    Write-Fichier (Join-Path $cle 'Outils/Portable/app/bin/outil64.exe') 'exe'
    $dest = Join-Path $work 'catalogue.json'
    [void](New-KitCatalogue -Items $items -KeyRoot $cle -Destination $dest -ProfileName 'test')
    $cat = [IO.File]::ReadAllText($dest) | ConvertFrom-Json
    $par = @{}; foreach ($e in $cat.Items) { $par[$e.Name] = $e }
    Assert-Vrai (-not $par.ContainsKey('Win7') -and -not $par.ContainsKey('Windows11')) 'ISO ou pack Windows 7 dans le catalogue'
    Assert-Vrai ($par.Present.Installer -eq 'setup.msi' -and $par.Present.Version -eq '1.2') 'installeur présent non référencé'
    Assert-Vrai ($null -eq $par.Absent.Installer -and $par.Absent.WingetId -eq 'Edit.Absent') 'élément absent : repli winget manquant'
    Assert-Vrai ($null -eq $par.Office365.Installer -and $par.Office365.WingetId -eq 'Microsoft.Office') 'Office absent : repli winget manquant'
    Assert-Vrai ($par.Portable.Launcher -eq 'app\bin\outil64.exe') "Launcher : « $($par.Portable.Launcher) » (attendu app\bin\outil64.exe)"
    Assert-Vrai ($par.Present.Folder -eq 'Logiciels\Present') 'Folder : séparateur Windows attendu'
    Assert-Vrai ($cat.Items[0].Name -eq 'Absent') 'tri par Order'
}

# =============================================================================== détection Ventoy (Linux, lsblk)
Write-Host "`n== Détection de la clé Ventoy (lsblk)" -ForegroundColor Cyan
Invoke-Essai 'Partition de données reconnue par la partition VTOYEFI voisine, pas les autres disques' {
    $disk = [pscustomobject]@{ name = 'sdb'; type = 'disk' }
    $p1 = [pscustomobject]@{ name = 'sdb1'; type = 'part'; label = 'MACLE'; ParentDisk = $disk }
    $p2 = [pscustomobject]@{ name = 'sdb2'; type = 'part'; label = 'VTOYEFI'; ParentDisk = $disk }
    $autre = [pscustomobject]@{ name = 'sdc'; type = 'disk' }
    $q1 = [pscustomobject]@{ name = 'sdc1'; type = 'part'; label = 'DATA'; ParentDisk = $autre }
    $blocks = @($disk, $p1, $p2, $autre, $q1)
    Assert-Vrai (Test-KitLinuxVentoyPart -Part $p1 -Blocks $blocks) 'sdb1 (renommée) non reconnue'
    Assert-Vrai (-not (Test-KitLinuxVentoyPart -Part $p2 -Blocks $blocks)) 'VTOYEFI prise pour la partition de données'
    Assert-Vrai (-not (Test-KitLinuxVentoyPart -Part $q1 -Blocks $blocks)) 'disque sans VTOYEFI accepté'
}
Invoke-Essai 'Clé absente : message clair, pas de plantage' {
    $absent = Join-Path $work 'pas-de-cle'
    $msg = ''
    try { [void](Test-KitDrive -Root $absent -WaitSec 0) } catch { $msg = $_.Exception.Message }
    Assert-Vrai ($msg -match 'introuvable') "message : $msg"
}

# =============================================================================== bilan
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed.Count -eq 0) { Write-Host ("Tous les tests sont passés ({0})." -f $script:Passed) -ForegroundColor Green }
else { Write-Host ("{0} test(s) en échec sur {1} : {2}" -f $script:Failed.Count, ($script:Passed + $script:Failed.Count), ($script:Failed -join ' ; ')) -ForegroundColor Red }
exit $script:Failed.Count
