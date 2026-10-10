#
# Backup.psm1 — Sauvegarde des données présentes sur la clé avant sa préparation
#
# Par défaut, seuls les fichiers PERSONNELS sont sauvegardés (tout ce qui n'est pas listé dans
# /MANIFEST.sha256, hors dossiers système). Avec -Complete, toute la clé est copiée.
# La sauvegarde est faite dans <Destination>\Sauvegarde-<libellé>-AAAAMMJJ-HHMMSS\ avec un fichier
# SAUVEGARDE.sha256 permettant de vérifier la copie.
#
Set-StrictMode -Version Latest

$script:SystemDirs = @('System Volume Information', '$RECYCLE.BIN')

function Get-KitBackupList {
    <#
    .SYNOPSIS
        Liste des fichiers de la clé à sauvegarder (personnels, ou tous avec -Complete).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest,
        [string[]] $ExcludeDirs = @(),
        [switch] $Complete
    )
    $excluded = @($script:SystemDirs + $ExcludeDirs)
    $files = foreach ($top in @(Get-ChildItem -LiteralPath $KeyRoot -Force -ErrorAction SilentlyContinue)) {
        if ($top.PSIsContainer) {
            if ($top.Name -in $excluded) { continue }
            Get-ChildItem -LiteralPath $top.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
        }
        else { $top }
    }
    $list = foreach ($f in @($files)) {
        $rel = ConvertTo-KitRelPath -Root $KeyRoot -FullPath $f.FullName
        if ($Complete -or -not $Manifest.ContainsKey($rel)) {
            if (-not $Complete -and $rel -ieq 'MANIFEST.sha256') { continue }
            [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Length = [double]$f.Length }
        }
    }
    return , @($list)
}

function Backup-KitDrive {
    <#
    .SYNOPSIS
        Sauvegarde les données de la clé vers un dossier (hors clé), avec contrôle SHA256.
    .OUTPUTS
        Objet : Folder, Files, Bytes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [string] $Destination,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest,
        [string[]] $ExcludeDirs = @(),
        [switch] $Complete
    )
    $destFull = [IO.Path]::GetFullPath($Destination)
    if ([IO.Path]::GetPathRoot($destFull) -ieq $KeyRoot) {
        throw "La sauvegarde ne peut pas être faite sur la clé elle-même ($destFull). Choisissez un autre disque."
    }
    $list = Get-KitBackupList -KeyRoot $KeyRoot -Manifest $Manifest -ExcludeDirs $ExcludeDirs -Complete:$Complete
    $total = 0.0
    foreach ($f in $list) { $total += $f.Length }
    $kind = 'fichiers personnels'
    if ($Complete) { $kind = 'clé complète' }
    Write-KitLog -Level STEP -Message ("Sauvegarde ({0}) : {1} fichier(s), {2}" -f $kind, $list.Count, (Format-KitSize $total))
    if ($list.Count -eq 0) {
        Write-KitLog -Message 'Rien à sauvegarder.'
        return [pscustomobject]@{ Folder = ''; Files = 0; Bytes = 0.0 }
    }

    if (-not (Test-Path -LiteralPath $destFull)) { New-Item -ItemType Directory -Path $destFull -Force | Out-Null }
    $free = [double](New-Object IO.DriveInfo([IO.Path]::GetPathRoot($destFull))).AvailableFreeSpace
    if ($free -lt $total + 100MB) {
        throw ("Place insuffisante pour la sauvegarde sur {0} : {1} libres, {2} nécessaires." -f $destFull, (Format-KitSize $free), (Format-KitSize $total))
    }
    $label = (New-Object IO.DriveInfo($KeyRoot)).VolumeLabel
    $folder = Join-Path $destFull ("Sauvegarde-{0}-{1}" -f $label, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $sums = New-Object System.Collections.Generic.List[string]
    $i = 0
    foreach ($f in $list) {
        $i++
        $target = Join-Path $folder (ConvertTo-KitLocalPath $f.Rel)
        $dir = Split-Path -Parent $target
        if ($PSCmdlet.ShouldProcess($f.Full, 'Sauvegarder')) {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Write-Progress -Activity 'Sauvegarde de la clé' -Status $f.Rel -PercentComplete ([int](100 * $i / $list.Count))
            Copy-Item -LiteralPath $f.Full -Destination $target -Force
            $sums.Add(("{0} *{1}" -f (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant(), $f.Rel))
        }
    }
    Write-Progress -Activity 'Sauvegarde de la clé' -Completed
    [IO.File]::WriteAllText((Join-Path $folder 'SAUVEGARDE.sha256'), (($sums -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-KitLog -Level OK -Message ("Sauvegarde terminée : {0}" -f $folder)
    return [pscustomobject]@{ Folder = $folder; Files = $list.Count; Bytes = $total }
}

Export-ModuleMember -Function Get-KitBackupList, Backup-KitDrive
