#
# Ventoy.psm1 — Installation / mise à jour de Ventoy sur une clé (OPTIONNEL), Windows et Linux
#
# Ventoy officiel : dernière release STABLE de github.com/ventoy/Ventoy, SHA256 publié vérifié.
# Ligne de commande officielle :
#   Windows : Ventoy2Disk.exe VTOYCLI /I|/U /PhyDrive:N [/GPT] [/NOSB] [/FS:…]   (cli_done.txt : 0 = succès)
#   Linux   : Ventoy2Disk.sh -I|-u [-g] [-S] /dev/sdX                          (code de sortie 0 = succès)
#
# GARDE-FOUS (l'installation EFFACE le disque) :
#   - disque USB/SD uniquement, jamais le disque de démarrage/système, ni celui du kit ;
#   - taille entre 4 Go et 2 To ;
#   - confirmation explicite obligatoire : « EFFACER-<identifiant> » (numéro de disque sous Windows,
#     nom du périphérique sous Linux, ex. EFFACER-sdb) ;
#   - droits administrateur / root requis ; sauvegarde proposée en amont (Build-Kit -SauvegardeVers).
# La MISE À JOUR conserve les données de la clé.
#
Set-StrictMode -Version Latest

$script:VentoyRepo = 'ventoy/Ventoy'

function Test-KitAdmin {
    <#
    .SYNOPSIS
        Vrai si le processus a les droits administrateur (Windows) ou root (Linux).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (Test-KitWindows) {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return ((& id -u) -eq '0')
}

function Get-KitUsbDisk {
    <#
    .SYNOPSIS
        Disques USB/SD éligibles (jamais disque de démarrage ou système), avec leur état Ventoy.
    .OUTPUTS
        Objets : Id (numéro Windows ou /dev/sdX), Number, Name, Model, SizeGB, Size, Letters (lettres
        ou points de montage), IsVentoy, IsReadOnly, IsOffline.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    if (Test-KitWindows) {
        $systemDisk = $null
        try { $systemDisk = (Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop).DiskNumber } catch { Write-Verbose 'Disque système non déterminé.' }
        $list = foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue)) {
            if ($d.BusType -notin @('USB', 'SD', 'MMC')) { continue }
            if ($d.IsBoot -or $d.IsSystem -or $d.Number -eq $systemDisk) { continue }
            $vols = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue)
            [pscustomobject]@{
                Id       = [string]$d.Number
                Number   = [int]$d.Number
                Name     = [string]$d.Number
                Model    = [string]$d.FriendlyName
                SizeGB   = [math]::Round($d.Size / 1GB, 1)
                Size     = [double]$d.Size
                Letters  = @($vols | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
                IsVentoy = [bool](@($vols | Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' }).Count -gt 0)
                IsReadOnly = [bool]$d.IsReadOnly
                IsOffline  = [bool]$d.IsOffline
            }
        }
        return @($list | Where-Object { $null -ne $_ })
    }
    # Linux : lsblk ; on écarte tout disque portant / , /boot , /boot/efi , /home ou le swap
    $blocks = @(Get-KitLinuxBlock)
    $critical = @('/', '/boot', '/boot/efi', '/home', '[SWAP]')
    $list = foreach ($d in @($blocks | Where-Object { $_.type -eq 'disk' })) {
        $tran = [string]$d.tran
        if ($tran -notin @('usb', 'mmc') -and -not ($d.rm -eq $true -or $d.rm -eq '1')) { continue }
        $children = @($blocks | Where-Object { $_.ParentDisk -and $_.ParentDisk.name -eq $d.name })
        if (@($children | Where-Object { $_.mountpoint -in $critical }).Count -gt 0) { continue }
        [pscustomobject]@{
            Id       = [string]$d.path
            Number   = -1
            Name     = [string]$d.name
            Model    = ([string]$d.model).Trim()
            SizeGB   = [math]::Round([double]$d.size / 1GB, 1)
            Size     = [double]$d.size
            Letters  = @($children | Where-Object { $_.mountpoint } | ForEach-Object { [string]$_.mountpoint })
            IsVentoy = [bool](@($children | Where-Object { $_.label -eq 'VTOYEFI' }).Count -gt 0)
            IsReadOnly = $false
            IsOffline  = $false
        }
    }
    return @($list | Where-Object { $null -ne $_ })
}

function Assert-KitVentoyTarget {
    <#
    .SYNOPSIS
        Vérifie qu'un disque peut recevoir Ventoy ; lève une exception explicite sinon.
    .PARAMETER Disk
        Numéro de disque (Windows) ou chemin /dev/sdX / nom sdX (Linux).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Disk,
        [string] $KitRoot = ''
    )
    $id = $Disk
    if (-not (Test-KitWindows) -and $id -notmatch '^/dev/') { $id = "/dev/$id" }
    $target = @(Get-KitUsbDisk | Where-Object { $_.Id -eq $id }) | Select-Object -First 1
    if (-not $target) { throw "Disque $Disk refusé : ce n'est pas une clé USB/SD éligible (disque système, interne ou introuvable)." }
    if ($target.Size -lt 4GB) { throw "Disque $Disk trop petit ($($target.SizeGB) Go, minimum 4 Go)." }
    if ($target.Size -gt 2TB) { throw "Disque $Disk trop grand ($($target.SizeGB) Go) : par sécurité, le kit se limite aux clés de 2 To maximum." }
    if ($KitRoot) {
        $full = [IO.Path]::GetFullPath($KitRoot)
        foreach ($l in $target.Letters) {
            $prefix = $(if (Test-KitWindows) { "$($l):\" } else { $l.TrimEnd('/') + '/' })
            if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Le kit est lancé depuis ce même disque ($l). Copiez le dossier du kit ailleurs avant d'installer Ventoy sur la clé."
            }
        }
    }
    return $target
}

function Save-KitVentoy {
    <#
    .SYNOPSIS
        Télécharge la dernière release stable officielle de Ventoy pour le système courant
        (SHA256 vérifié) et la décompresse.
    .OUTPUTS
        Objet : Version, Exe (Ventoy2Disk.exe ou Ventoy2Disk.sh).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $ToolsDir)
    $win = Test-KitWindows
    $pattern = $(if ($win) { '^ventoy-[\d.]+-windows\.zip$' } else { '^ventoy-[\d.]+-linux\.tar\.gz$' })
    $tool = $(if ($win) { 'Ventoy2Disk.exe' } else { 'Ventoy2Disk.sh' })
    $rel = Get-KitGitHubRelease -Repo $script:VentoyRepo -AssetPattern $pattern
    if (-not $rel.Sha256) { throw 'Empreinte SHA256 de Ventoy non publiée : téléchargement refusé.' }
    if (-not (Test-Path -LiteralPath $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
    $archive = Join-Path $ToolsDir $rel.FileName
    $dir = Join-Path $ToolsDir ("ventoy-{0}" -f $rel.Version)
    $exe = @(Get-ChildItem -LiteralPath $dir -Filter $tool -Recurse -File -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $exe) {
        Write-KitLog -Message ("Ventoy {0} : téléchargement de la release officielle…" -f $rel.Version)
        Invoke-KitHttpDownload -Url $rel.Url -Destination $archive -ExpectedLength $rel.Length -SourceTag $rel.Sha256
        if ((Get-KitSha256 -Path $archive) -ne $rel.Sha256) { Remove-Item -LiteralPath $archive -Force; throw 'Ventoy : SHA256 différent de celui publié. Fichier refusé.' }
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if ($win) { Expand-Archive -LiteralPath $archive -DestinationPath $dir -Force }
        else { & tar -xzf $archive -C $dir; if ($LASTEXITCODE -ne 0) { throw 'Décompression de l''archive Ventoy impossible.' } }
        $exe = @(Get-ChildItem -LiteralPath $dir -Filter $tool -Recurse -File) | Select-Object -First 1
        if (-not $exe) { throw "$tool introuvable dans l'archive Ventoy." }
        Write-KitLog -Level OK -Message ("Ventoy {0} vérifié (SHA256 officiel)." -f $rel.Version)
    }
    return [pscustomobject]@{ Version = $rel.Version; Exe = $exe.FullName }
}

function Invoke-KitVentoy2Disk {
    <#
    .SYNOPSIS
        Lance Ventoy2Disk en ligne de commande (installation ou mise à jour) et suit le résultat.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [ValidateSet('Install', 'Update')] [string] $Mode,
        [Parameter(Mandatory)] [string] $Disk,
        [switch] $Gpt,
        [switch] $NoSecureBoot,
        [ValidateSet('exFAT', 'NTFS', 'FAT32')] [string] $FileSystem = 'exFAT',
        [string] $Label = 'Ventoy',
        # Au-delà, Ventoy2Disk est considéré bloqué (fenêtre d'erreur invisible, disque verrouillé)
        [int] $TimeoutMin = 20
    )
    $dir = Split-Path -Parent $Exe
    if (Test-KitWindows) {
        foreach ($f in 'cli_done.txt', 'cli_percent.txt', 'cli_log.txt') { Remove-Item -LiteralPath (Join-Path $dir $f) -Force -ErrorAction SilentlyContinue }
        $argList = @('VTOYCLI', $(if ($Mode -eq 'Install') { '/I' } else { '/U' }), "/PhyDrive:$Disk")
        if ($Mode -eq 'Install') {
            if ($Gpt) { $argList += '/GPT' }
            if ($NoSecureBoot) { $argList += '/NOSB' }
            $argList += "/FS:$($FileSystem.ToUpperInvariant())"
        }
        if (-not $PSCmdlet.ShouldProcess("Disque $Disk", "Ventoy2Disk $($argList -join ' ')")) { return }
        Write-KitLog -Level STEP -Message ("Ventoy2Disk {0}" -f ($argList -join ' '))
        $p = Start-Process -FilePath $Exe -ArgumentList $argList -WorkingDirectory $dir -PassThru
        $last = -1
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            if ($sw.Elapsed.TotalMinutes -ge $TimeoutMin) {
                try { $p.Kill() } catch { Write-Verbose 'Ventoy2Disk déjà terminé.' }
                throw ("Ventoy2Disk ne répond plus après {0} min (disque verrouillé par un autre programme ?). Fermez les fenêtres ouvertes sur la clé, débranchez-la, rebranchez-la et relancez." -f $TimeoutMin)
            }
            Start-Sleep -Seconds 2
            $pf = Join-Path $dir 'cli_percent.txt'
            if (Test-Path -LiteralPath $pf) {
                $pct = 0; [void][int]::TryParse(((Get-Content -LiteralPath $pf -Raw -ErrorAction SilentlyContinue) -replace '\D', ''), [ref]$pct)
                if ($pct -ge $last + 10) { $last = $pct; Write-KitLog -Message ("Ventoy : {0} %" -f $pct) }
            }
        }
        $done = Join-Path $dir 'cli_done.txt'
        $result = ''
        if (Test-Path -LiteralPath $done) { $result = (Get-Content -LiteralPath $done -Raw).Trim() }
        if ($result -ne '0') {
            $log = Join-Path $dir 'cli_log.txt'
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 15 | ForEach-Object { Write-KitLog -Level WARN -Message "Ventoy : $_" } }
            throw ("Ventoy2Disk a échoué (cli_done.txt = « {0} »)." -f $result)
        }
    }
    else {
        $dev = $(if ($Disk -match '^/dev/') { $Disk } else { "/dev/$Disk" })
        $argList = @($(if ($Mode -eq 'Install') { '-I' } else { '-u' }))
        if ($Mode -eq 'Install') {
            if ($Gpt) { $argList += '-g' }
            if ($NoSecureBoot) { $argList += '-S' }
            $argList += @('-L', $Label)
        }
        $argList += $dev
        if (-not $PSCmdlet.ShouldProcess($dev, "Ventoy2Disk.sh $($argList -join ' ')")) { return }
        Write-KitLog -Level STEP -Message ("Ventoy2Disk.sh {0}" -f ($argList -join ' '))
        # Démontage préalable des partitions de la clé (requis par Ventoy)
        foreach ($m in @(Get-KitLinuxBlock | Where-Object { $_.ParentDisk -and $_.ParentDisk.path -eq $dev -and $_.mountpoint })) { & /usr/bin/umount $m.path 2>$null }
        # Les confirmations interactives (« Continue? (y/n) ») sont validées : la confirmation
        # explicite EFFACER-<disque> a déjà été exigée par le kit.
        Push-Location $dir
        try {
            $out = "y`ny`ny`n" | & bash ./Ventoy2Disk.sh @argList 2>&1
            $code = $LASTEXITCODE
        }
        finally { Pop-Location }
        foreach ($l in @($out | Select-Object -Last 12)) { Write-KitLog -Message "Ventoy : $l" }
        if ($code -ne 0) { throw "Ventoy2Disk.sh a échoué (code $code)." }
    }
    Write-KitLog -Level OK -Message ("Ventoy : {0} terminée ({1})." -f $(if ($Mode -eq 'Install') { 'installation' } else { 'mise à jour' }), $Disk)
}

function Initialize-KitUsbDisk {
    <#
    .SYNOPSIS
        Windows : remet en ligne et en écriture un disque USB avant l'installation de Ventoy
        (disques « hors ligne » ou « en lecture seule » après un usage sur un autre poste,
        une stratégie SAN ou un outil de clonage). Droits administrateur requis.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [int] $Number)
    $d = Get-Disk -Number $Number -ErrorAction Stop
    if ($d.IsOffline -and $PSCmdlet.ShouldProcess("Disque $Number", 'Mise en ligne')) {
        Write-KitLog -Message "Disque $Number hors ligne : mise en ligne."
        Set-Disk -Number $Number -IsOffline $false -ErrorAction Stop
    }
    if ($d.IsReadOnly -and $PSCmdlet.ShouldProcess("Disque $Number", 'Retrait de la lecture seule')) {
        Write-KitLog -Message "Disque $Number en lecture seule : retrait de l'attribut."
        try { Set-Disk -Number $Number -IsReadOnly $false -ErrorAction Stop }
        catch { throw "Le disque $Number est protégé en écriture (petit interrupteur « Lock » sur la clé ou la carte SD ?) : $($_.Exception.Message)" }
        if ((Get-Disk -Number $Number).IsReadOnly) { throw "Le disque $Number reste protégé en écriture : vérifiez l'interrupteur « Lock » de la clé ou de la carte SD." }
    }
}

function Clear-KitUsbDisk {
    <#
    .SYNOPSIS
        Windows : efface la table de partitions d'un disque USB (équivalent de « diskpart clean »).
        Utilisé quand Ventoy2Disk refuse une ancienne clé (ISO écrite en mode DD, partitions
        verrouillées, table de partitions abîmée). Droits administrateur requis.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)] [int] $Number)
    if (-not $PSCmdlet.ShouldProcess("Disque $Number", 'Effacement de la table de partitions')) { return }
    Write-KitLog -Level WARN -Message "Disque $Number : effacement de la table de partitions avant une nouvelle tentative."
    # Volumes démontés d'abord : un Explorateur ouvert sur la clé ne bloque plus l'effacement
    foreach ($v in @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne [char]0 })) {
        try { $v | Remove-PartitionAccessPath -AccessPath ('{0}:\' -f $v.DriveLetter) -ErrorAction Stop } catch { Write-Verbose "Lettre $($v.DriveLetter) conservée." }
    }
    try { Clear-Disk -Number $Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop }
    catch {
        # Disque « RAW » (jamais initialisé) : rien à effacer, Ventoy saura l'utiliser
        if ((Get-Disk -Number $Number).PartitionStyle -ne 'RAW') { throw "Effacement du disque $Number impossible : $($_.Exception.Message)" }
    }
    try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { Write-Verbose 'Rafraîchissement du stockage indisponible.' }
    Start-Sleep -Seconds 3
}

function Install-KitVentoy {
    <#
    .SYNOPSIS
        Installe Ventoy sur un disque de façon fiable, y compris sur une ancienne clé :
        disque remis en ligne / en écriture, puis en cas d'échec, effacement de la table de
        partitions et seconde tentative (Windows). La confirmation d'effacement a déjà été exigée.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string] $Disk,
        [switch] $Gpt,
        [switch] $NoSecureBoot,
        [ValidateSet('exFAT', 'NTFS', 'FAT32')] [string] $FileSystem = 'exFAT',
        [string] $Label = 'Ventoy'
    )
    if (-not $PSCmdlet.ShouldProcess("Disque $Disk", 'Installation de Ventoy (effacement)')) { return }
    $common = @{ Exe = $Exe; Mode = 'Install'; Disk = $Disk; Gpt = $Gpt; NoSecureBoot = $NoSecureBoot; FileSystem = $FileSystem; Label = $Label; Confirm = $false }
    if (-not (Test-KitWindows)) { Invoke-KitVentoy2Disk @common; return }
    Initialize-KitUsbDisk -Number ([int]$Disk) -Confirm:$false
    try { Invoke-KitVentoy2Disk @common }
    catch {
        Write-KitLog -Level WARN -Message ("Première tentative refusée ({0}). Ancienne clé : nettoyage puis nouvel essai." -f $_.Exception.Message)
        # Le numéro désigne-t-il toujours une clé USB éligible ? (clé rebranchée et renumérotée entre-temps)
        [void](Assert-KitVentoyTarget -Disk $Disk)
        Clear-KitUsbDisk -Number ([int]$Disk) -Confirm:$false
        Initialize-KitUsbDisk -Number ([int]$Disk) -Confirm:$false
        Invoke-KitVentoy2Disk @common
    }
}

function Wait-KitVentoyVolume {
    <#
    .SYNOPSIS
        Attend la partition de données « Ventoy » du disque et retourne sa racine (E:\ ou point de
        montage Linux, monté si nécessaire).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Disk,
        [string] $Label = 'Ventoy',
        [int] $TimeoutSec = 120
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if (Test-KitWindows) {
            try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { Write-Verbose 'Rafraîchissement du stockage indisponible.' }
            $part = @(Get-Partition -DiskNumber ([int]$Disk) -ErrorAction SilentlyContinue | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq $Label }) | Select-Object -First 1
            if ($part) {
                if (-not $part.DriveLetter -or $part.DriveLetter -eq [char]0) {
                    $part | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue
                    $part = Get-Partition -DiskNumber ([int]$Disk) -PartitionNumber $part.PartitionNumber
                }
                if ($part.DriveLetter -and $part.DriveLetter -ne [char]0) {
                    $root = ('{0}:\' -f $part.DriveLetter)
                    if ((New-Object System.IO.DriveInfo($root)).IsReady) { return $root }
                }
            }
        }
        else {
            $dev = $(if ($Disk -match '^/dev/') { $Disk } else { "/dev/$Disk" })
            & udevadm settle 2>$null
            $p = @(Get-KitLinuxBlock | Where-Object { $_.ParentDisk -and $_.ParentDisk.path -eq $dev -and $_.label -eq $Label }) | Select-Object -First 1
            if ($p) {
                if ($p.mountpoint) { return ($p.mountpoint.TrimEnd('/') + '/') }
                # Montage pour l'utilisateur qui a lancé sudo (fichiers accessibles ensuite sans root)
                $mnt = "/mnt/alchemist-$($p.name)"
                New-Item -ItemType Directory -Path $mnt -Force | Out-Null
                $opts = 'rw'
                if ($env:SUDO_UID) { $opts = "rw,uid=$($env:SUDO_UID),gid=$($env:SUDO_GID)" }
                & /usr/bin/mount -o $opts $p.path $mnt
                if ($LASTEXITCODE -eq 0) { return ($mnt + '/') }
            }
        }
        Start-Sleep -Seconds 3
    }
    throw "La partition « $Label » du disque $Disk n'est pas apparue (débranchez/rebranchez la clé puis relancez sans -InstallerVentoy)."
}

Export-ModuleMember -Function Test-KitAdmin, Get-KitUsbDisk, Assert-KitVentoyTarget, Save-KitVentoy, Invoke-KitVentoy2Disk,
    Initialize-KitUsbDisk, Clear-KitUsbDisk, Install-KitVentoy, Wait-KitVentoyVolume
