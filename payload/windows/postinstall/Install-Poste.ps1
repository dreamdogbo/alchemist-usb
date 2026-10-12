<#
.SYNOPSIS
    Post-installation d'un poste bureautique Windows 11 depuis la clé Ventoy, SANS Internet.

.DESCRIPTION
    - S'élève automatiquement en administrateur (et se relance sous Windows PowerShell 5.1).
    - Journal complet dans C:\PostInstall\.
    - Crée un point de restauration avant toute modification.
    - Lit catalogue.json et installe, en silencieux, chaque logiciel depuis la clé
      (dossier \Logiciels\). Ce qui est déjà installé est ignoré.
      Repli winget seulement si Internet est disponible ET que l'installeur local est absent
      ou a échoué.
    - Installe Office (Microsoft 365 Apps) depuis \Bureautique\Office365 (sauf -SansOffice).
    - Réglages : extensions de fichiers visibles, pas de mise en veille sur secteur,
      fuseau « Greenwich Standard Time », renommage optionnel, Acrobat Reader par défaut
      pour les PDF, recherche Windows Update si Internet est disponible.
    - Bilan final des échecs.

.PARAMETER SansOffice
    N'installe pas Office.
.PARAMETER NomPoste
    Nouveau nom du poste (15 caractères max : lettres, chiffres, tiret). Redémarrage requis.
.PARAMETER SansReglages
    N'applique pas les réglages système (installe uniquement les logiciels).
.PARAMETER Logiciels
    N'installe que les éléments nommés (noms du catalogue, ex. -Logiciels Chrome,VLC).
    Un outil en mode « Manuel » (CrystalDiskInfo, HWiNFO…) n'est installé que s'il est nommé ici.
.PARAMETER AvecOutils
    Installe aussi les outils technicien installables (mode « Manuel »).
.PARAMETER Journal
    Chemin imposé du journal (utilisé par l'assistant graphique pour l'afficher en direct).
.PARAMETER Etat
    N'installe rien : écrit en JSON l'état de chaque élément du catalogue (déjà installé,
    présent sur la clé…). Utilisé par l'assistant graphique.
.PARAMETER AttendreFin
    Usage interne : garde la fenêtre ouverte à la fin (fenêtre ouverte par l'auto-élévation).

.EXAMPLE
    .\Install-Poste.ps1
.EXAMPLE
    .\Install-Poste.ps1 -NomPoste MAIRIE-PC012 -SansOffice
.EXAMPLE
    .\Install-Poste.ps1 -Logiciels Chrome,Firefox,VLC -SansReglages

.NOTES
    Code de sortie : nombre d'éléments en échec (0 = tout est bon).
    Interface graphique : Assistant-Poste.ps1 (ouverte par Lancer.bat).
#>
[CmdletBinding()]
param(
    [switch] $SansOffice,
    [string] $NomPoste,
    [switch] $SansReglages,
    [string[]] $Logiciels,
    [switch] $AvecOutils,
    [string] $Journal,
    [switch] $Etat,
    [switch] $AttendreFin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------- auto-élévation
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Etat -and (-not $isAdmin -or $PSVersionTable.PSEdition -eq 'Core')) {
    # Relance en administrateur, sous Windows PowerShell 5.1 (Checkpoint-Computer, etc.)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($SansOffice) { $argList += '-SansOffice' }
    if ($SansReglages) { $argList += '-SansReglages' }
    if ($NomPoste) { $argList += @('-NomPoste', $NomPoste) }
    if ($AvecOutils) { $argList += '-AvecOutils' }
    if ($Logiciels) { $argList += @('-Logiciels', (($Logiciels | ForEach-Object { $_ -split ',' }) -join ',')) }
    if ($Journal) { $argList += @('-Journal', ('"{0}"' -f $Journal)) }
    $argList += '-AttendreFin'
    $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        if ($isAdmin) { Start-Process -FilePath $ps51 -ArgumentList $argList -Wait }
        else { Start-Process -FilePath $ps51 -ArgumentList $argList -Verb RunAs }
        exit 0
    }
    catch {
        Write-Host "Les droits administrateur sont nécessaires. Relancez et acceptez la demande d'élévation." -ForegroundColor Red
        exit 1
    }
}

# --------------------------------------------------------------------------- initialisation
$KeyRoot = Split-Path -Parent $PSScriptRoot
$LogDir = 'C:\PostInstall'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $LogDir "PostInstall-$stamp.log"
if (-not $Etat) { Start-Transcript -LiteralPath $transcript -Force | Out-Null }

$script:Bilan = New-Object System.Collections.Generic.List[object]

function Write-Etape {
    <#
    .SYNOPSIS
        Affiche une ligne horodatée en couleur (le transcript l'enregistre).
    #>
    param([string] $Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERREUR', 'ETAPE')] [string] $Niveau = 'INFO')
    $color = @{ INFO = 'Gray'; OK = 'Green'; WARN = 'Yellow'; ERREUR = 'Red'; ETAPE = 'Cyan' }[$Niveau]
    $ligne = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Niveau, $Message
    Write-Host $ligne -ForegroundColor $color
    # Journal suivi en direct par l'assistant graphique
    if ($Journal) { try { Add-Content -LiteralPath $Journal -Value $ligne -Encoding UTF8 } catch { Write-Verbose 'Journal indisponible.' } }
}

function Add-Bilan {
    <#
    .SYNOPSIS
        Ajoute une ligne au bilan final.
    #>
    param([string] $Nom, [ValidateSet('OK', 'DÉJÀ INSTALLÉ', 'ÉCHEC', 'IGNORÉ')] [string] $Statut, [string] $Detail = '')
    $script:Bilan.Add([pscustomobject]@{ Element = $Nom; Statut = $Statut; Detail = $Detail })
    $niveau = switch ($Statut) { 'OK' { 'OK' } 'DÉJÀ INSTALLÉ' { 'OK' } 'ÉCHEC' { 'ERREUR' } default { 'WARN' } }
    Write-Etape -Niveau $niveau -Message ("{0} : {1} {2}" -f $Nom, $Statut, $Detail)
}

function Get-Prop {
    <#
    .SYNOPSIS
        Lit une propriété d'objet sans erreur si elle est absente (compatible StrictMode).
    #>
    param($Objet, [string] $Nom, $Defaut = $null)
    if ($null -eq $Objet) { return $Defaut }
    $p = $Objet.PSObject.Properties[$Nom]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Defaut
}

function Test-Internet {
    <#
    .SYNOPSIS
        Vrai si le poste accède à Internet (sonde officielle Microsoft, 5 s max).
    #>
    try {
        $req = [Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $req.Timeout = 5000
        $resp = $req.GetResponse(); $resp.Close()
        return $true
    }
    catch { return $false }
}

function Get-NomInstalle {
    <#
    .SYNOPSIS
        Liste des DisplayName des programmes installés (machine 64/32 bits et utilisateur).
    #>
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $names = foreach ($p in $paths) {
        Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | ForEach-Object { Get-Prop $_ 'DisplayName' } | Where-Object { $_ }
    }
    return @($names)
}

function Test-DejaInstalle {
    <#
    .SYNOPSIS
        Applique la règle de détection du catalogue (reg:, appx:, c2r:).
    #>
    param([Parameter(Mandatory)] $Entree)
    $d = [string](Get-Prop $Entree 'Detection' '')
    if (-not $d) { return $false }
    $valeur = $d.Substring($d.IndexOf(':') + 1)
    switch -Wildcard ($d) {
        'reg:*' { return [bool](@(Get-NomInstalle) -match $valeur) }
        'appx:*' {
            # Sans droits administrateur, ces commandes échouent : repli sur l'utilisateur courant
            $prov = @()
            try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $valeur }) } catch { Write-Verbose 'AppX provisionnés illisibles (droits).' }
            $inst = @()
            try { $inst = @(Get-AppxPackage -AllUsers -Name $valeur -ErrorAction Stop) }
            catch { $inst = @(Get-AppxPackage -Name $valeur -ErrorAction SilentlyContinue) }
            return ($prov.Count + $inst.Count) -gt 0
        }
        'c2r:*' {
            $cfg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
            return ([string](Get-Prop $cfg 'ProductReleaseIds' '')) -match [regex]::Escape($valeur)
        }
        'file:*' { return (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($valeur))) }
    }
    return $false
}

function Invoke-Installeur {
    <#
    .SYNOPSIS
        Lance un installeur local en silencieux et retourne son code de sortie.
    #>
    param([Parameter(Mandatory)] [string] $Fichier, [string] $Arguments = '', [string] $Nom = 'installeur', [string] $Dossier)
    $ext = [IO.Path]::GetExtension($Fichier).ToLowerInvariant()
    if ($ext -eq '.zip') {
        # Outil en ligne de commande portable (ex. Trivy) : décompressé dans %ProgramFiles%\Alchemist\<nom>,
        # dossier ajouté au PATH de la machine
        $cible = Join-Path (Join-Path $env:ProgramFiles 'Alchemist') $Nom
        Expand-Archive -LiteralPath $Fichier -DestinationPath $cible -Force
        $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if (@($path -split ';') -notcontains $cible) {
            [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ';' + $cible), 'Machine')
        }
        return 0
    }
    if ($ext -eq '.msi') {
        $msiLog = Join-Path $LogDir "$Nom-msi.log"
        $all = ('/i "{0}" {1} /l*v "{2}"' -f $Fichier, $Arguments, $msiLog)
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $all -Wait -PassThru
    }
    else {
        $sp = @{ FilePath = $Fichier; Wait = $true; PassThru = $true }
        if ($Arguments) { $sp['ArgumentList'] = $Arguments }
        if ($Dossier) { $sp['WorkingDirectory'] = $Dossier }
        $p = Start-Process @sp
    }
    return [int]$p.ExitCode
}

function Invoke-PostAction {
    <#
    .SYNOPSIS
        Configuration complémentaire après installation (champ PostAction du catalogue).
    .DESCRIPTION
        ClamAVConfig : crée freshclam.conf et clamd.conf à partir des modèles fournis par ClamAV
        (ligne « Example » retirée), puis télécharge les signatures si Internet est disponible.
        Microsoft Defender reste la protection en temps réel ; ClamAV sert à l'analyse à la demande.
    #>
    param([string] $Action)
    switch ($Action) {
        'ClamAVConfig' {
            $dir = Join-Path $env:ProgramFiles 'ClamAV'
            foreach ($conf in 'freshclam', 'clamd') {
                $target = Join-Path $dir "$conf.conf"
                $sample = Join-Path $dir "conf_examples\$conf.conf.sample"
                if (-not (Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $sample)) {
                    (Get-Content -LiteralPath $sample) | Where-Object { $_ -notmatch '^\s*Example\s*$' } | Set-Content -LiteralPath $target -Encoding ASCII
                }
            }
            $fresh = Join-Path $dir 'freshclam.exe'
            if ($script:Internet -and (Test-Path -LiteralPath $fresh)) {
                Write-Etape -Message 'ClamAV : téléchargement des signatures antivirus…'
                & $fresh | Out-Host
                return "configuré, signatures à jour (code $LASTEXITCODE)"
            }
            return 'configuré ; signatures à télécharger dès qu''Internet sera disponible (freshclam.exe)'
        }
        'WSLFeatures' {
            # WSL 2 (requis par Podman et Docker Desktop) : fonctionnalités Windows, effectives après redémarrage
            foreach ($feature in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
                & dism.exe /Online /Enable-Feature /FeatureName:$feature /All /NoRestart | Out-Null
            }
            return 'fonctionnalités WSL 2 activées (redémarrage requis) ; distribution Ubuntu : « wsl --install -d Ubuntu » avec Internet'
        }
        default { return '' }
    }
}

function Install-ViaWinget {
    <#
    .SYNOPSIS
        Repli : installation en ligne via winget (si Internet et winget sont disponibles).
    #>
    param([Parameter(Mandatory)] [string] $WingetId)
    if (-not $script:Internet) { return $false }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { Write-Etape -Niveau WARN -Message 'winget indisponible sur ce poste.'; return $false }
    Write-Etape -Message "Repli en ligne : winget install $WingetId"
    & $winget.Source install --id $WingetId --exact --silent --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    # 0 = succès ; -1978335189 = déjà installé / aucune mise à jour applicable
    return ($LASTEXITCODE -in @(0, -1978335189))
}

function Get-SystemeLinuxDemarrage {
    <#
    .SYNOPSIS
        Systèmes Linux présents dans les entrées de démarrage UEFI (double démarrage).
    #>
    $noms = foreach ($ligne in @(& bcdedit.exe /enum firmware 2>$null)) {
        if ([string]$ligne -match '^\s*description\s+(.+)$' -and $Matches[1] -match '(?i)ubuntu|debian|fedora|mint|linux|grub|shim|opensuse|arch') { $Matches[1].Trim() }
    }
    return @($noms | Select-Object -Unique)
}

function Install-DevDrive {
    <#
    .SYNOPSIS
        Crée un Dev Drive (ReFS) dans un VHDX dynamique sur C:, remonté à chaque démarrage.
    .DESCRIPTION
        Profil développement (réglage DevDrive du profil). Taille maximale selon C: : 128 Go (disque
        < 512 Go), 256 Go (< 1 To), 512 Go au-delà, limitée à la moitié de l'espace libre (50 Go minimum).
        Le VHDX ne consomme que l'espace réellement écrit. Caches npm, pip et NuGet redirigés.
        Retourne @{ Statut ; Detail } pour le bilan (IGNORÉ si un prérequis manque).
    #>
    $vhdx = Join-Path $env:SystemDrive 'DevDrive\DevDrive.vhdx'
    if (Test-Path -LiteralPath $vhdx) { return @{ Statut = 'DÉJÀ INSTALLÉ'; Detail = $vhdx } }
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int](Get-Prop $cv 'CurrentBuildNumber' 0); $ubr = [int](Get-Prop $cv 'UBR' 0)
    if ($build -lt 22621 -or ($build -eq 22621 -and $ubr -lt 2338)) {
        return @{ Statut = 'IGNORÉ'; Detail = "Windows 11 22621.2338 ou plus récent requis (poste : $build.$ubr) : mettre à jour puis relancer" }
    }
    $ramGo = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    if ($ramGo -lt 8) { return @{ Statut = 'IGNORÉ'; Detail = "8 Go de RAM minimum (poste : $ramGo Go)" } }
    $c = Get-Volume -DriveLetter $env:SystemDrive.Substring(0, 1)
    $libreGo = [math]::Floor($c.SizeRemaining / 1GB)
    # 512 Go et 1 To « fabricant » = 476 et 931 Go vus par Windows
    $maxGo = 512
    if ($c.Size / 1GB -lt 476) { $maxGo = 128 } elseif ($c.Size / 1GB -lt 931) { $maxGo = 256 }
    $maxGo = [int][math]::Min($maxGo, [math]::Floor($libreGo / 2))
    if ($maxGo -lt 50) { return @{ Statut = 'IGNORÉ'; Detail = "espace libre insuffisant sur C: ($libreGo Go ; 100 Go nécessaires)" } }
    $prises = @(Get-CimInstance -ClassName Win32_LogicalDisk | ForEach-Object { ([string]$_.DeviceID).Substring(0, 1) })
    $lettre = @(68..90 | ForEach-Object { [string][char]$_ } | Where-Object { $_ -notin $prises }) | Select-Object -First 1
    if (-not $lettre) { return @{ Statut = 'IGNORÉ'; Detail = 'aucune lettre de lecteur libre' } }

    New-Item -ItemType Directory -Path (Split-Path -Parent $vhdx) -Force | Out-Null
    $script = Join-Path $env:TEMP 'alchemist-devdrive.txt'
    @("create vdisk file=`"$vhdx`" maximum=$($maxGo * 1024) type=expandable", 'attach vdisk', 'convert gpt',
        'create partition primary', "assign letter=$lettre") | Set-Content -LiteralPath $script -Encoding ASCII
    & diskpart.exe /s $script | Out-Null
    $code = $LASTEXITCODE
    Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) { throw "diskpart a échoué (code $code)" }
    try { Format-Volume -DriveLetter $lettre -DevDrive -NewFileSystemLabel 'DevDrive' -Confirm:$false -ErrorAction Stop | Out-Null }
    catch {
        & format.com "$($lettre):" /DevDrv /Q /V:DevDrive /Y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "formatage Dev Drive impossible : $($_.Exception.Message)" }
    }

    # Le VHDX est rattaché à chaque démarrage (même lettre, mémorisée par Windows)
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -ExecutionPolicy Bypass -Command `"Mount-DiskImage -ImagePath '{0}' -ErrorAction SilentlyContinue`"" -f $vhdx)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'Alchemist - Dev Drive' -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Force | Out-Null

    # Dépôts et caches de paquets sur le Dev Drive (recommandations Microsoft)
    $racine = "$($lettre):\"
    $caches = [ordered]@{ npm_config_cache = 'Caches\npm'; PIP_CACHE_DIR = 'Caches\pip'; NUGET_PACKAGES = 'Caches\nuget' }
    New-Item -ItemType Directory -Path (Join-Path $racine 'Projets') -Force | Out-Null
    foreach ($nom in $caches.Keys) {
        $dossier = Join-Path $racine $caches[$nom]
        New-Item -ItemType Directory -Path $dossier -Force | Out-Null
        [Environment]::SetEnvironmentVariable($nom, $dossier, 'Machine')
    }
    return @{ Statut = 'OK'; Detail = ("{0}: ReFS, VHDX dynamique {1} Go max ({2}) ; dossier Projets, caches npm/pip/NuGet" -f $lettre, $maxGo, $vhdx) }
}

if ($Etat) {
    # Mode lecture seule pour l'assistant graphique : état de chaque élément, en JSON
    $cat = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'catalogue.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $etats = foreach ($e in @($cat.Items)) {
        $dossier = Join-Path $KeyRoot ([string]$e.Folder)
        $inst = [string](Get-Prop $e 'Installer' '')
        $launcher = [string](Get-Prop $e 'Launcher' '')
        [ordered]@{
            Name      = [string]$e.Name
            Category  = [string](Get-Prop $e 'Category' 'Logiciel')
            Mode      = [string](Get-Prop $e 'Mode' 'Auto')
            Version   = [string](Get-Prop $e 'Version' '')
            Installed = [bool](Test-DejaInstalle -Entree $e)
            OnKey     = [bool](($inst -and (Test-Path -LiteralPath (Join-Path $dossier $inst))) -or ($launcher -and (Test-Path -LiteralPath (Join-Path $dossier $launcher))))
            Launcher  = $(if ($launcher) { Join-Path $dossier $launcher } else { '' })
            WingetId  = [string](Get-Prop $e 'WingetId' '')
        }
    }
    [ordered]@{ Internet = (Test-Internet); Items = @($etats) } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

try {
    Write-Etape -Niveau ETAPE -Message "Post-installation du poste $env:COMPUTERNAME — clé : $KeyRoot"
    $catPath = Join-Path $PSScriptRoot 'catalogue.json'
    if (-not (Test-Path -LiteralPath $catPath)) { throw "catalogue.json introuvable à côté du script ($catPath)." }
    $catalogue = Get-Content -LiteralPath $catPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Internet = Test-Internet
    Write-Etape -Message ("Internet : {0}" -f $(if ($script:Internet) { 'disponible (repli winget possible)' } else { 'absent — installation 100 % depuis la clé' }))

    # ----------------------------------------------------------------------- point de restauration
    if (-not $SansReglages) {
        Write-Etape -Niveau ETAPE -Message 'Point de restauration'
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\"
            # Autorise un point même si un autre a été créé il y a moins de 24 h
            New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
            Checkpoint-Computer -Description 'Alchemist - avant post-installation' -RestorePointType 'MODIFY_SETTINGS'
            Add-Bilan -Nom 'Point de restauration' -Statut 'OK'
        }
        catch { Add-Bilan -Nom 'Point de restauration' -Statut 'ÉCHEC' -Detail $_.Exception.Message }
    }

    # ----------------------------------------------------------------------- logiciels
    Write-Etape -Niveau ETAPE -Message 'Installation des logiciels'
    $choix = @($Logiciels | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($e in @($catalogue.Items | Sort-Object { [int](Get-Prop $_ 'Order' 99) })) {
        $nom = [string]$e.Name
        try {
            $mode = [string](Get-Prop $e 'Mode' 'Auto')
            $nomme = $choix -contains $nom
            # Sélection : liste explicite (-Logiciels) sinon tous les éléments « Auto »
            if ($choix.Count -gt 0 -and -not $nomme) { continue }
            if ($choix.Count -eq 0 -and $mode -eq 'Manuel' -and -not $AvecOutils) { continue }
            if ($e.Type -eq 'Office' -and $SansOffice) { Add-Bilan -Nom $nom -Statut 'IGNORÉ' -Detail '(-SansOffice)'; continue }
            if (Get-Prop $e 'Launcher' $null) {
                Add-Bilan -Nom $nom -Statut 'IGNORÉ' -Detail ("outil portable, à lancer depuis la clé : {0}\{1}" -f $e.Folder, $e.Launcher)
                continue
            }
            if (Test-DejaInstalle -Entree $e) { Add-Bilan -Nom $nom -Statut 'DÉJÀ INSTALLÉ'; continue }

            $dossier = Join-Path $KeyRoot ([string]$e.Folder)
            $installer = [string](Get-Prop $e 'Installer' '')
            $fichier = $null
            if ($installer) { $fichier = Join-Path $dossier $installer }
            $codesOk = @(Get-Prop $e 'SuccessCodes' @(0) | ForEach-Object { [int]$_ })
            $ok = $false; $detail = ''

            if ($fichier -and (Test-Path -LiteralPath $fichier)) {
                Write-Etape -Message ("{0} {1} : installation depuis la clé…" -f $nom, (Get-Prop $e 'Version' ''))
                if ($e.Type -eq 'Office') {
                    $code = Invoke-Installeur -Fichier $fichier -Arguments ('/configure "{0}"' -f (Join-Path $dossier 'config.xml')) -Nom $nom -Dossier $dossier
                    $codesOk = @(0)
                }
                else {
                    $arguments = ([string](Get-Prop $e 'SilentArgs' '')).Replace('{DIR}', $dossier.TrimEnd('\'))
                    $code = Invoke-Installeur -Fichier $fichier -Arguments $arguments -Nom $nom -Dossier $dossier
                }
                if ($code -in $codesOk) { $ok = $true; $detail = "depuis la clé (code $code)"; if ($code -in @(3010, 1641)) { $detail += ', redémarrage requis' } }
                else { $detail = "installeur local en échec (code $code)" }
            }
            else { $detail = 'installeur absent de la clé' }

            if (-not $ok) {
                $wid = [string](Get-Prop $e 'WingetId' '')
                if ($e.Type -eq 'Office' -and $script:Internet -and (Test-Path -LiteralPath (Join-Path $dossier 'setup.exe'))) {
                    # Office : AllowCdnFallback dans config.xml complète depuis Internet
                    $code = Invoke-Installeur -Fichier (Join-Path $dossier 'setup.exe') -Arguments ('/configure "{0}"' -f (Join-Path $dossier 'config.xml')) -Nom $nom -Dossier $dossier
                    if ($code -eq 0) { $ok = $true; $detail += ' ; installé avec le complément en ligne' }
                }
                elseif ($wid -and (Install-ViaWinget -WingetId $wid)) { $ok = $true; $detail += ' ; installé en ligne via winget' }
                elseif (-not $script:Internet) { $detail += ' ; pas d''Internet pour le repli winget' }
            }
            if ($ok) {
                $post = [string](Get-Prop $e 'PostAction' '')
                if ($post) {
                    try { $info = Invoke-PostAction -Action $post; if ($info) { $detail += " ; $info" } }
                    catch { $detail += " ; configuration complémentaire en échec : $($_.Exception.Message)" }
                }
                Add-Bilan -Nom $nom -Statut 'OK' -Detail $detail
            }
            else { Add-Bilan -Nom $nom -Statut 'ÉCHEC' -Detail $detail }
        }
        catch { Add-Bilan -Nom $nom -Statut 'ÉCHEC' -Detail $_.Exception.Message }
    }

    # ----------------------------------------------------------------------- réglages
    if (-not $SansReglages) {
        Write-Etape -Niveau ETAPE -Message 'Réglages du poste'

        # Extensions de fichiers visibles : utilisateur actuel + profil par défaut (futurs comptes)
        try {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord
            $hive = 'HKU\KitDefaultUser'
            & reg.exe load $hive "$env:SystemDrive\Users\Default\NTUSER.DAT" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                & reg.exe add "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
                [gc]::Collect(); Start-Sleep -Seconds 1
                & reg.exe unload $hive | Out-Null
            }
            Add-Bilan -Nom 'Extensions de fichiers visibles' -Statut 'OK'
        }
        catch { Add-Bilan -Nom 'Extensions de fichiers visibles' -Statut 'ÉCHEC' -Detail $_.Exception.Message }

        # Pas de mise en veille ni de veille prolongée sur secteur
        try {
            & powercfg.exe /change standby-timeout-ac 0
            & powercfg.exe /change hibernate-timeout-ac 0
            Add-Bilan -Nom 'Pas de veille sur secteur' -Statut 'OK'
        }
        catch { Add-Bilan -Nom 'Pas de veille sur secteur' -Statut 'ÉCHEC' -Detail $_.Exception.Message }

        # Fuseau horaire
        $tzId = 'Greenwich Standard Time'
        $settings = Get-Prop $catalogue 'Settings' $null
        if ($settings) { $tzId = [string](Get-Prop $settings 'TimeZone' $tzId) }
        try {
            Set-TimeZone -Id $tzId
            Add-Bilan -Nom "Fuseau $tzId" -Statut 'OK'
        }
        catch { Add-Bilan -Nom "Fuseau $tzId" -Statut 'ÉCHEC' -Detail $_.Exception.Message }

        # Double démarrage avec Linux : horloge en UTC, démarrage rapide et veille prolongée désactivés
        # (sinon le NTFS reste « hiberné » : Linux ne peut pas l'écrire sans risque)
        try {
            $linux = @(Get-SystemeLinuxDemarrage)
            if ($linux.Count -gt 0) {
                New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -PropertyType DWord -Value 1 -Force | Out-Null
                & powercfg.exe /hibernate off
                Add-Bilan -Nom 'Double démarrage' -Statut 'OK' -Detail ("{0} détecté : horloge UTC, démarrage rapide désactivé" -f ($linux -join ', '))
            }
        }
        catch { Add-Bilan -Nom 'Double démarrage' -Statut 'ÉCHEC' -Detail $_.Exception.Message }

        # Dev Drive (profil développement)
        if ($settings -and [bool](Get-Prop $settings 'DevDrive' $false)) {
            try { $dd = Install-DevDrive; Add-Bilan -Nom 'Dev Drive' -Statut $dd.Statut -Detail $dd.Detail }
            catch { Add-Bilan -Nom 'Dev Drive' -Statut 'ÉCHEC' -Detail $_.Exception.Message }
        }

        # Acrobat Reader par défaut pour les PDF (méthode entreprise officielle :
        # fichier d'associations par défaut, appliqué à chaque ouverture de session)
        try {
            $progId = @('Acrobat.Document.DC', 'AcroExch.Document.DC') | Where-Object { Test-Path -LiteralPath ("Registry::HKEY_CLASSES_ROOT\{0}" -f $_) } | Select-Object -First 1
            if (-not $progId) { Add-Bilan -Nom 'PDF -> Acrobat Reader' -Statut 'IGNORÉ' -Detail 'Acrobat Reader non installé' }
            else {
                $assocDir = Join-Path $env:ProgramData 'KitPoste'
                if (-not (Test-Path -LiteralPath $assocDir)) { New-Item -ItemType Directory -Path $assocDir -Force | Out-Null }
                $assoc = Join-Path $assocDir 'AssociationsParDefaut.xml'
                $xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier=".pdf" ProgId="$progId" ApplicationName="Adobe Acrobat" />
</DefaultAssociations>
"@
                [IO.File]::WriteAllText($assoc, $xml, (New-Object Text.UTF8Encoding($false)))
                & dism.exe /Online /Import-DefaultAppAssociations:"$assoc" | Out-Null
                $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
                if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force | Out-Null }
                New-ItemProperty -Path $pol -Name 'DefaultAssociationsConfiguration' -Value $assoc -PropertyType String -Force | Out-Null
                Add-Bilan -Nom 'PDF -> Acrobat Reader' -Statut 'OK' -Detail "($progId, effectif à la prochaine ouverture de session)"
            }
        }
        catch { Add-Bilan -Nom 'PDF -> Acrobat Reader' -Statut 'ÉCHEC' -Detail $_.Exception.Message }

        # Renommage optionnel
        if ($NomPoste) {
            try {
                if ($NomPoste -notmatch '^(?![0-9]+$)[A-Za-z0-9-]{1,15}$') { throw "Nom invalide « $NomPoste » (1 à 15 caractères : lettres, chiffres, tiret ; pas uniquement des chiffres)." }
                if ($NomPoste -ieq $env:COMPUTERNAME) { Add-Bilan -Nom 'Renommage' -Statut 'IGNORÉ' -Detail 'Le poste porte déjà ce nom' }
                else {
                    Rename-Computer -NewName $NomPoste -Force
                    Add-Bilan -Nom 'Renommage' -Statut 'OK' -Detail "$env:COMPUTERNAME -> $NomPoste (redémarrage requis)"
                }
            }
            catch { Add-Bilan -Nom 'Renommage' -Statut 'ÉCHEC' -Detail $_.Exception.Message }
        }

        # Windows Update (uniquement si Internet)
        if ($script:Internet) {
            try {
                Write-Etape -Message 'Recherche des mises à jour Windows (quelques minutes)…'
                $session = New-Object -ComObject Microsoft.Update.Session
                $res = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0 and Type=''Software''')
                & "$env:WINDIR\System32\UsoClient.exe" StartInteractiveScan 2>$null
                Add-Bilan -Nom 'Windows Update' -Statut 'OK' -Detail ("{0} mise(s) à jour disponible(s), installation lancée par Windows Update" -f $res.Updates.Count)
            }
            catch { Add-Bilan -Nom 'Windows Update' -Statut 'ÉCHEC' -Detail $_.Exception.Message }
        }
        else { Add-Bilan -Nom 'Windows Update' -Statut 'IGNORÉ' -Detail 'pas d''Internet' }
    }
}
catch {
    Add-Bilan -Nom 'Post-installation' -Statut 'ÉCHEC' -Detail $_.Exception.Message
}

# --------------------------------------------------------------------------- bilan
Write-Etape -Niveau ETAPE -Message '================ BILAN ================'
$script:Bilan | Format-Table -AutoSize -Wrap | Out-Host
$echecs = @($script:Bilan | Where-Object Statut -eq 'ÉCHEC')
if ($echecs.Count -eq 0) { Write-Etape -Niveau OK -Message 'Aucun échec. Pensez à redémarrer le poste.' }
else { Write-Etape -Niveau ERREUR -Message ("{0} échec(s) : {1}" -f $echecs.Count, (($echecs | ForEach-Object Element) -join ', ')) }
Write-Etape -Message "Journal : $transcript"
Stop-Transcript | Out-Null
if ($AttendreFin) { [void](Read-Host 'Appuyez sur Entrée pour fermer') }
exit $echecs.Count
