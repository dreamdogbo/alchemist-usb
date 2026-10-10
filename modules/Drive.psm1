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

function Find-KitVentoyDrive {
    <#
    .SYNOPSIS
        Liste les volumes montés dont le libellé est celui d'une clé Ventoy (détection automatique).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string] $ExpectedLabel = 'Ventoy')
    if (Test-KitWindows) {
        $found = foreach ($d in [IO.DriveInfo]::GetDrives()) {
            try {
                if ($d.IsReady -and $d.VolumeLabel -ceq $ExpectedLabel) {
                    [pscustomobject]@{
                        Letter = $d.Name.Substring(0, 1); Root = $d.Name; Label = $d.VolumeLabel
                        TotalGB = [math]::Round($d.TotalSize / 1GB, 1); FreeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
                        Removable = ($d.DriveType -eq [IO.DriveType]::Removable); Device = ''
                    }
                }
            }
            catch { Write-Verbose "Lecteur $($d.Name) illisible : $($_.Exception.Message)" }
        }
        return , @($found)
    }
    $found = foreach ($b in @(Get-KitLinuxBlock)) {
        if ($b.type -eq 'part' -and $b.label -ceq $ExpectedLabel -and $b.mountpoint) {
            $info = New-Object System.IO.DriveInfo($b.mountpoint)
            [pscustomobject]@{
                Letter = $null; Root = ($b.mountpoint.TrimEnd('/') + '/'); Label = $b.label
                TotalGB = [math]::Round([double]$b.size / 1GB, 1); FreeGB = [math]::Round($info.AvailableFreeSpace / 1GB, 1)
                Removable = $true; Device = $b.path
            }
        }
    }
    return , @($found)
}

function Test-KitDrive {
    <#
    .SYNOPSIS
        Vérifie que la clé est bien la clé Ventoy attendue (lettre sous Windows, chemin sous Linux).
    .DESCRIPTION
        Contrôles bloquants : le volume existe, est prêt, porte exactement le libellé attendu
        (« Ventoy ») et dispose d'au moins MinFreeBytes. Lève une exception claire sinon.
    #>
    [CmdletBinding()]
    param(
        [char] $DriveLetter,
        [string] $Root,
        [string] $ExpectedLabel = 'Ventoy',
        [double] $MinFreeBytes = 0
    )
    if (-not $Root) { $Root = Get-KitDriveRoot -DriveLetter $DriveLetter }
    if (-not (Test-Path -LiteralPath $Root)) {
        throw "La clé $Root est introuvable. Branchez la clé Ventoy ou indiquez-la avec -DriveLetter (Windows) / -KeyPath (Linux)."
    }
    $info = New-Object System.IO.DriveInfo($Root)
    if (-not $info.IsReady) { throw "Le volume $Root n'est pas prêt (clé débranchée ou illisible)." }

    $label = ''
    $fs = $info.DriveFormat
    if (Test-KitWindows) {
        $label = $info.VolumeLabel
        try {
            $part = Get-Partition -DriveLetter $Root.Substring(0, 1) -ErrorAction Stop
            $vtoy = @(Get-Partition -DiskNumber $part.DiskNumber -ErrorAction Stop | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' })
            if ($vtoy.Count -gt 0) { Write-KitLog -Message 'Partition VTOYEFI détectée : clé Ventoy confirmée.' }
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
            $disk = $part.ParentDisk
            if ($disk -and @($blocks | Where-Object { $_.ParentDisk -and $_.ParentDisk.name -eq $disk.name -and $_.label -eq 'VTOYEFI' }).Count -gt 0) {
                Write-KitLog -Message 'Partition VTOYEFI détectée : clé Ventoy confirmée.'
            }
        }
    }
    if ($label -cne $ExpectedLabel) {
        throw ("Le volume {0} a pour libellé « {1} » au lieu de « {2} ». Ce n'est pas la clé Ventoy attendue : arrêt par sécurité." -f $Root, $label, $ExpectedLabel)
    }
    $free = [double]$info.AvailableFreeSpace
    Write-KitLog -Message ("Clé {0} : libellé « {1} », {2}, taille {3}, libre {4}" -f $Root, $label, $fs, (Format-KitSize $info.TotalSize), (Format-KitSize $free))
    if ($free -lt $MinFreeBytes) {
        throw ("Espace libre insuffisant sur {0} : {1} disponibles, {2} minimum requis (marge)." -f $Root, (Format-KitSize $free), (Format-KitSize $MinFreeBytes))
    }
    return [pscustomobject]@{ Root = $Root; Label = $label; FileSystem = $fs; TotalBytes = [double]$info.TotalSize; FreeBytes = $free }
}

Export-ModuleMember -Function Test-KitWindows, Get-KitDriveRoot, Get-KitLinuxBlock, Get-KitFreeSpace, Find-KitVentoyDrive, Test-KitDrive
