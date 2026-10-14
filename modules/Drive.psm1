#
# Drive.psm1 — Contrôles de la clé Ventoy et mesure de l'espace libre (Windows et Linux)
#
# Windows : la clé est désignée par sa lettre (E:\).
# Linux   : la clé est désignée par son point de montage (/media/<utilisateur>/Ventoy/), détecté
#           avec lsblk (libellé de volume).
# Ce module ne fait QUE lire : aucune commande de partitionnement ni de formatage.
#
Set-StrictMode -Version Latest

function Test-KitWindows {
    <#
    .SYNOPSIS
        Vrai sous Windows (PowerShell 5.1 ou 7).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return ($PSVersionTable.PSEdition -eq 'Desktop' -or [Environment]::OSVersion.Platform -eq 'Win32NT')
}

function Get-KitDriveRoot {
    <#
    .SYNOPSIS
        Retourne la racine « X:\ » d'une lettre de lecteur (Windows).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [char] $DriveLetter)
    return ('{0}:\' -f ([string]$DriveLetter).ToUpperInvariant())
}

function Get-KitLinuxBlock {
    <#
    .SYNOPSIS
        Périphériques de stockage sous Linux (lsblk en JSON, tailles en octets), à plat,
        chaque entrée portant son disque parent (ParentDisk).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $json = & lsblk -J -b -o NAME,PATH,TYPE,SIZE,LABEL,FSTYPE,MOUNTPOINT,TRAN,MODEL,RM 2>$null | Out-String
    if (-not $json.Trim()) { return , @() }
    $flat = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    foreach ($n in @(($json | ConvertFrom-Json).blockdevices)) { $stack.Push(@($n, $null)) }
    while ($stack.Count -gt 0) {
        $pair = $stack.Pop(); $n = $pair[0]; $parent = $pair[1]
        $n | Add-Member -NotePropertyName ParentDisk -NotePropertyValue $parent -Force
        $flat.Add($n)
        $next = $parent
        if ($n.type -eq 'disk') { $next = $n }
        if ($n.PSObject.Properties['children'] -and $n.children) { foreach ($c in @($n.children)) { $stack.Push(@($c, $next)) } }
    }
    return , $flat.ToArray()
}

function Get-KitFreeSpace {
    <#
    .SYNOPSIS
        Espace libre réel (octets) du volume, relu à chaque appel (lettre ou chemin).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [char] $DriveLetter,
        [string] $Root
    )
    if (-not $Root) { $Root = Get-KitDriveRoot -DriveLetter $DriveLetter }
    $info = New-Object System.IO.DriveInfo($Root)
    return [double]$info.AvailableFreeSpace
}

function Get-KitVentoyDiskNumber {
    <#
    .SYNOPSIS
        Numéros des disques portant une partition VTOYEFI (Windows) : ce sont des clés Ventoy,
        quel que soit le libellé de leur partition de données.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param()
    try { return , @(Get-Volume -FileSystemLabel 'VTOYEFI' -ErrorAction Stop | Get-Partition -ErrorAction Stop | ForEach-Object { [int]$_.DiskNumber } | Select-Object -Unique) }
    catch { Write-Verbose 'Aucune partition VTOYEFI visible.'; return , @() }
}

function Test-KitLinuxVentoyPart {
    <#
    .SYNOPSIS
        Vrai si la partition Linux est la partition de données d'un disque Ventoy (première
        partition d'un disque qui porte aussi une partition VTOYEFI).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] $Part, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Blocks)
    if (-not $Part.ParentDisk -or $Part.label -eq 'VTOYEFI') { return $false }
    $siblings = @($Blocks | Where-Object { $_.type -eq 'part' -and $_.ParentDisk -and $_.ParentDisk.name -eq $Part.ParentDisk.name } | Sort-Object { [string]$_.name })
    if (@($siblings | Where-Object { $_.label -eq 'VTOYEFI' }).Count -eq 0) { return $false }
    return ($siblings.Count -gt 0 -and $siblings[0].name -eq $Part.name)
}

function Find-KitVentoyDrive {
    <#
    .SYNOPSIS
        Liste les volumes montés qui sont des clés Ventoy (détection automatique).
    .DESCRIPTION
        Une clé est retenue si sa partition porte le libellé attendu (« Ventoy »), ou si elle est la
        partition de données d'un disque qui porte une partition VTOYEFI (clé déjà utilisée dont le
        libellé a été changé, ou affiché en majuscules en FAT32).
        Sous Windows, les lecteurs réseau, CD et lecteurs de cartes sans carte sont ignorés : leur
        interrogation peut bloquer la fenêtre plusieurs dizaines de secondes.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string] $ExpectedLabel = 'Ventoy')
    if (Test-KitWindows) {
        $ventoyDisks = @(Get-KitVentoyDiskNumber)
        $found = foreach ($d in [IO.DriveInfo]::GetDrives()) {
            if ($d.DriveType -ne [IO.DriveType]::Removable -and $d.DriveType -ne [IO.DriveType]::Fixed) { continue }
            try {
                if (-not $d.IsReady) { continue }
                $byPartition = $false
                if ($d.VolumeLabel -cne $ExpectedLabel) {
                    if ($ventoyDisks.Count -eq 0 -or $d.VolumeLabel -eq 'VTOYEFI') { continue }
                    $p = Get-Partition -DriveLetter $d.Name.Substring(0, 1) -ErrorAction SilentlyContinue
                    if (-not ($p -and [int]$p.DiskNumber -in $ventoyDisks -and $p.PartitionNumber -eq 1)) { continue }
                    $byPartition = $true
                }
                [pscustomobject]@{
                    Letter = $d.Name.Substring(0, 1); Root = $d.Name; Label = $d.VolumeLabel
                    TotalGB = [math]::Round($d.TotalSize / 1GB, 1); FreeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
                    Removable = ($d.DriveType -eq [IO.DriveType]::Removable); Device = ''; FileSystem = $d.DriveFormat
                    ByPartition = $byPartition
                }
            }
            catch { Write-Verbose "Lecteur $($d.Name) illisible : $($_.Exception.Message)" }
        }
        return , @($found)
    }
    $blocks = @(Get-KitLinuxBlock)
    $found = foreach ($b in $blocks) {
        if ($b.type -ne 'part' -or -not $b.mountpoint) { continue }
        $byPartition = $false
        if ($b.label -cne $ExpectedLabel) {
            if (-not (Test-KitLinuxVentoyPart -Part $b -Blocks $blocks)) { continue }
            $byPartition = $true
        }
        $info = New-Object System.IO.DriveInfo($b.mountpoint)
        [pscustomobject]@{
            Letter = $null; Root = ($b.mountpoint.TrimEnd('/') + '/'); Label = [string]$b.label
            TotalGB = [math]::Round([double]$b.size / 1GB, 1); FreeGB = [math]::Round($info.AvailableFreeSpace / 1GB, 1)
            Removable = $true; Device = $b.path; FileSystem = [string]$b.fstype
            ByPartition = $byPartition
        }
    }
    return , @($found)
}

function Test-KitDrive {
    <#
    .SYNOPSIS
        Vérifie que la clé est bien la clé Ventoy attendue (lettre sous Windows, chemin sous Linux).
    .DESCRIPTION
        Contrôles bloquants : le volume existe, est prêt (attente jusqu'à WaitSec secondes : une
        clé tout juste branchée ou formatée par Ventoy n'est pas lisible immédiatement), est une clé
        Ventoy — libellé attendu (« Ventoy ») ou partition VTOYEFI sur le même disque — et dispose
        d'au moins MinFreeBytes. Lève une exception claire sinon.
    #>
    [CmdletBinding()]
    param(
        [char] $DriveLetter,
        [string] $Root,
        [string] $ExpectedLabel = 'Ventoy',
        [double] $MinFreeBytes = 0,
        [int] $WaitSec = 30
    )
    if (-not $Root) { $Root = Get-KitDriveRoot -DriveLetter $DriveLetter }
    $info = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if (Test-Path -LiteralPath $Root) {
            $info = New-Object System.IO.DriveInfo($Root)
            if ($info.IsReady) { break }
        }
        if ($sw.Elapsed.TotalSeconds -ge $WaitSec) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $info) {
        throw "La clé $Root est introuvable. Branchez la clé Ventoy ou indiquez-la avec -DriveLetter (Windows) / -KeyPath (Linux)."
    }
    if (-not $info.IsReady) { throw "Le volume $Root n'est pas prêt (clé débranchée ou illisible). Débranchez et rebranchez la clé, puis relancez." }

    $label = ''
    $fs = $info.DriveFormat
    $vtoyConfirmed = $false
    if (Test-KitWindows) {
        $label = $info.VolumeLabel
        try {
            $part = Get-Partition -DriveLetter $Root.Substring(0, 1) -ErrorAction Stop
            $vtoy = @(Get-Partition -DiskNumber $part.DiskNumber -ErrorAction Stop | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' })
            if ($vtoy.Count -gt 0) {
                Write-KitLog -Message 'Partition VTOYEFI détectée : clé Ventoy confirmée.'
                $vtoyConfirmed = ($part.PartitionNumber -eq 1)
            }
            else { Write-KitLog -Level WARN -Message 'Partition VTOYEFI non visible (normal sur certains systèmes). Le libellé « Ventoy » suffit.' }
        }
        catch { Write-KitLog -Level WARN -Message ("Lecture des partitions impossible ({0}). Contrôle VTOYEFI ignoré." -f $_.Exception.Message) }
    }
    else {
        $mount = $Root.TrimEnd('/'); if (-not $mount) { $mount = '/' }
        $blocks = @(Get-KitLinuxBlock)
        $part = @($blocks | Where-Object { $_.mountpoint -eq $mount }) | Select-Object -First 1
        if ($part) {
            $label = [string]$part.label; $fs = [string]$part.fstype
            if (Test-KitLinuxVentoyPart -Part $part -Blocks $blocks) {
                Write-KitLog -Message 'Partition VTOYEFI détectée : clé Ventoy confirmée.'
                $vtoyConfirmed = $true
            }
        }
    }
    if ($label -cne $ExpectedLabel) {
        if (-not $vtoyConfirmed) {
            throw ("Le volume {0} a pour libellé « {1} » au lieu de « {2} » et ne porte pas de partition VTOYEFI. Ce n'est pas une clé Ventoy : arrêt par sécurité. Pour une clé neuve ou d'un autre usage, cochez « Clé neuve : installer Ventoy »." -f $Root, $label, $ExpectedLabel)
        }
        Write-KitLog -Level WARN -Message ("Libellé « {0} » au lieu de « {1} », mais la partition VTOYEFI du même disque confirme une clé Ventoy." -f $label, $ExpectedLabel)
    }
    $free = [double]$info.AvailableFreeSpace
    Write-KitLog -Message ("Clé {0} : libellé « {1} », {2}, taille {3}, libre {4}" -f $Root, $label, $fs, (Format-KitSize $info.TotalSize), (Format-KitSize $free))
    if ($free -lt $MinFreeBytes) {
        throw ("Espace libre insuffisant sur {0} : {1} disponibles, {2} minimum requis (marge)." -f $Root, (Format-KitSize $free), (Format-KitSize $MinFreeBytes))
    }
    return [pscustomobject]@{ Root = $Root; Label = $label; FileSystem = $fs; TotalBytes = [double]$info.TotalSize; FreeBytes = $free }
}

function Sync-KitVolume {
    <#
    .SYNOPSIS
        Vide le cache d'écriture du volume de la clé : les fichiers sont réellement sur la clé
        quand le kit annonce « terminé » (sinon un retrait immédiat peut corrompre l'ISO).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    try {
        if (Test-KitWindows) { Write-VolumeCache -DriveLetter $Root.Substring(0, 1) -ErrorAction Stop }
        else { & sync }
        Write-KitLog -Message 'Écritures en attente vidées sur la clé.'
    }
    # Sans droits administrateur, Windows refuse le vidage explicite (les clés USB sont par défaut en
    # « suppression rapide », sans cache d'écriture) : simple rappel, pas un avertissement
    catch { Write-KitLog -Message ("Vidage du cache d'écriture non disponible ({0}) : utilisez « Retirer le périphérique en toute sécurité » avant de débrancher la clé." -f $_.Exception.Message) }
}

Export-ModuleMember -Function Test-KitWindows, Get-KitDriveRoot, Get-KitLinuxBlock, Get-KitFreeSpace, Get-KitVentoyDiskNumber,
    Test-KitLinuxVentoyPart, Find-KitVentoyDrive, Test-KitDrive, Sync-KitVolume
