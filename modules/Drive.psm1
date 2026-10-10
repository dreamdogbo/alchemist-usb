#
# Drive.psm1 — Contrôles de la clé Ventoy et mesure de l'espace libre
#
# IMPORTANT : ce module ne fait QUE lire. Aucune commande de partitionnement,
# de formatage ni d'installation Ventoy n'est utilisée dans ce kit.
#
Set-StrictMode -Version Latest

function Get-KitDriveRoot {
    <#
    .SYNOPSIS
        Retourne la racine « X:\ » d'une lettre de lecteur.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [char] $DriveLetter)
    return ('{0}:\' -f ([string]$DriveLetter).ToUpperInvariant())
}

function Get-KitFreeSpace {
    <#
    .SYNOPSIS
        Retourne l'espace libre réel (octets) du volume, relu à chaque appel.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)] [char] $DriveLetter)
    $info = New-Object System.IO.DriveInfo((Get-KitDriveRoot -DriveLetter $DriveLetter))
    return [double]$info.AvailableFreeSpace
}

function Test-KitDrive {
    <#
    .SYNOPSIS
        Vérifie que la clé est bien la clé Ventoy attendue.
    .DESCRIPTION
        Contrôles bloquants : le lecteur existe, il est prêt, son libellé est exactement
        celui attendu (« Ventoy »), il reste au moins MinFreeBytes.
        Contrôles informatifs : type amovible, présence de la partition VTOYEFI.
        Lève une exception (message clair) si un contrôle bloquant échoue.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [char] $DriveLetter,
        [string] $ExpectedLabel = 'Ventoy',
        [double] $MinFreeBytes = 0
    )
    $root = Get-KitDriveRoot -DriveLetter $DriveLetter
    $info = New-Object System.IO.DriveInfo($root)

    if (-not (Test-Path -LiteralPath $root)) {
        throw "Le lecteur $root n'existe pas. Branchez la clé Ventoy ou indiquez la bonne lettre avec -DriveLetter."
    }
    if (-not $info.IsReady) {
        throw "Le lecteur $root n'est pas prêt (clé débranchée ou illisible)."
    }
    if ($info.VolumeLabel -cne $ExpectedLabel) {
        throw ("Le lecteur {0} a pour libellé « {1} » au lieu de « {2} ». Ce n'est pas la clé Ventoy attendue : arrêt par sécurité." -f $root, $info.VolumeLabel, $ExpectedLabel)
    }
    if ($info.DriveType -ne [System.IO.DriveType]::Removable) {
        Write-KitLog -Level WARN -Message ("{0} n'est pas signalé comme amovible (type {1}). Certains SSD USB apparaissent ainsi : on continue." -f $root, $info.DriveType)
    }

    # Contrôle informatif : partition VTOYEFI sur le même disque (lecture seule)
    try {
        $part = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        $vtoy = @(Get-Partition -DiskNumber $part.DiskNumber -ErrorAction Stop |
                Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' })
        if ($vtoy.Count -gt 0) { Write-KitLog -Message 'Partition VTOYEFI détectée : clé Ventoy confirmée.' }
        else { Write-KitLog -Level WARN -Message 'Partition VTOYEFI non visible (normal sur certains systèmes). Le libellé « Ventoy » suffit.' }
    }
    catch {
        Write-KitLog -Level WARN -Message ("Lecture des partitions impossible ({0}). Contrôle VTOYEFI ignoré." -f $_.Exception.Message)
    }

    $free = [double]$info.AvailableFreeSpace
    Write-KitLog -Message ("Clé {0} : libellé « {1} », {2}, taille {3}, libre {4}" -f $root, $info.VolumeLabel, $info.DriveFormat,
        (Format-KitSize $info.TotalSize), (Format-KitSize $free))
    if ($free -lt $MinFreeBytes) {
        throw ("Espace libre insuffisant sur {0} : {1} disponibles, {2} minimum requis (marge)." -f $root, (Format-KitSize $free), (Format-KitSize $MinFreeBytes))
    }
    return [pscustomobject]@{
        Root        = $root
        Label       = $info.VolumeLabel
        FileSystem  = $info.DriveFormat
        TotalBytes  = [double]$info.TotalSize
        FreeBytes   = $free
    }
}

function Find-KitVentoyDrive {
    <#
    .SYNOPSIS
        Liste les volumes prêts dont le libellé est celui d'une clé Ventoy (détection automatique).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string] $ExpectedLabel = 'Ventoy')
    $found = foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if ($d.IsReady -and $d.VolumeLabel -ceq $ExpectedLabel) {
                [pscustomobject]@{
                    Letter    = $d.Name.Substring(0, 1)
                    Root      = $d.Name
                    Label     = $d.VolumeLabel
                    TotalGB   = [math]::Round($d.TotalSize / 1GB, 1)
                    FreeGB    = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
                    Removable = ($d.DriveType -eq [IO.DriveType]::Removable)
                }
            }
        }
        catch { Write-Verbose "Lecteur $($d.Name) illisible : $($_.Exception.Message)" }
    }
    return , @($found)
}

Export-ModuleMember -Function Get-KitDriveRoot, Get-KitFreeSpace, Test-KitDrive, Find-KitVentoyDrive
