#
# Ventoy.psm1 — Installation / mise à jour de Ventoy sur une clé (OPTIONNEL)
#
# Ventoy officiel : dernière release STABLE de github.com/ventoy/Ventoy, SHA256 publié vérifié.
# Ligne de commande officielle : Ventoy2Disk.exe VTOYCLI /I|/U /PhyDrive:N [options]
#   (https://www.ventoy.net/en/doc_windows_cli.html) ; résultat dans cli_done.txt (0 = succès).
#
# GARDE-FOUS (l'installation EFFACE le disque) :
#   - disque USB/SD uniquement, jamais le disque de démarrage, système, ni celui du kit ou de Windows ;
#   - taille entre 4 Go et 2 To ;
#   - confirmation explicite obligatoire : « EFFACER-<numéro du disque> » ;
#   - droits administrateur requis ; sauvegarde proposée en amont (Build-Kit -SauvegardeVers).
# La MISE À JOUR (/U) conserve les données de la clé.
#
Set-StrictMode -Version Latest

$script:VentoyRepo = 'ventoy/Ventoy'
$script:VentoyAsset = '^ventoy-[\d.]+-windows\.zip$'

function Test-KitAdmin {
    <#
    .SYNOPSIS
        Vrai si le processus courant a les droits administrateur.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KitUsbDisk {
    <#
    .SYNOPSIS
        Liste les disques USB/SD éligibles (jamais disque de démarrage ou système), avec leur état Ventoy.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $systemDisk = $null
    try { $systemDisk = (Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop).DiskNumber } catch { Write-Verbose 'Disque système non déterminé.' }
    $list = foreach ($d in @(Get-Disk -ErrorAction SilentlyContinue)) {
        if ($d.BusType -notin @('USB', 'SD', 'MMC')) { continue }
        if ($d.IsBoot -or $d.IsSystem -or $d.Number -eq $systemDisk) { continue }
        $vols = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue)
        $letters = @($vols | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
        [pscustomobject]@{
            Number   = [int]$d.Number
            Model    = [string]$d.FriendlyName
            SizeGB   = [math]::Round($d.Size / 1GB, 1)
            Size     = [double]$d.Size
            Letters  = $letters
            IsVentoy = [bool](@($vols | Where-Object { $_.FileSystemLabel -eq 'VTOYEFI' }).Count -gt 0)
            Style    = [string]$d.PartitionStyle
        }
    }
    return , @($list)
}

function Assert-KitVentoyTarget {
    <#
    .SYNOPSIS
        Vérifie qu'un disque peut recevoir Ventoy ; lève une exception explicite sinon.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $DiskNumber,
        [string] $KitRoot = ''
    )
    $disk = @(Get-KitUsbDisk | Where-Object { $_.Number -eq $DiskNumber }) | Select-Object -First 1
    if (-not $disk) { throw "Disque $DiskNumber refusé : ce n'est pas une clé USB/SD éligible (disque système, interne ou introuvable)." }
    if ($disk.Size -lt 4GB) { throw "Disque $DiskNumber trop petit ($($disk.SizeGB) Go, minimum 4 Go)." }
    if ($disk.Size -gt 2TB) { throw "Disque $DiskNumber trop grand ($($disk.SizeGB) Go) : par sécurité, le kit se limite aux clés de 2 To maximum." }
    if ($KitRoot) {
        $kitLetter = ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($KitRoot))).Substring(0, 1)
        if ($disk.Letters -contains $kitLetter) {
            throw "Le kit est lancé depuis ce même disque ($kitLetter`:). Copiez le dossier du kit sur le PC avant d'installer Ventoy sur la clé."
        }
    }
    return $disk
}

function Save-KitVentoy {
    <#
    .SYNOPSIS
        Télécharge la dernière release stable officielle de Ventoy (SHA256 vérifié) et la décompresse.
    .OUTPUTS
        Objet : Version, Exe (chemin de Ventoy2Disk.exe).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $ToolsDir)
    $rel = Get-KitGitHubRelease -Repo $script:VentoyRepo -AssetPattern $script:VentoyAsset
    if (-not $rel.Sha256) { throw 'Empreinte SHA256 de Ventoy non publiée : téléchargement refusé.' }
    if (-not (Test-Path -LiteralPath $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
    $zip = Join-Path $ToolsDir $rel.FileName
    $dir = Join-Path $ToolsDir ("ventoy-{0}" -f $rel.Version)
    $exe = @(Get-ChildItem -LiteralPath $dir -Filter 'Ventoy2Disk.exe' -Recurse -File -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $exe) {
        Write-KitLog -Message ("Ventoy {0} : téléchargement de la release officielle…" -f $rel.Version)
        Invoke-KitHttpDownload -Url $rel.Url -Destination $zip -ExpectedLength $rel.Length -SourceTag $rel.Sha256
        if ((Get-KitSha256 -Path $zip) -ne $rel.Sha256) { Remove-Item -LiteralPath $zip -Force; throw 'Ventoy : SHA256 différent de celui publié. Fichier refusé.' }
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
        $exe = @(Get-ChildItem -LiteralPath $dir -Filter 'Ventoy2Disk.exe' -Recurse -File) | Select-Object -First 1
        if (-not $exe) { throw 'Ventoy2Disk.exe introuvable dans l''archive Ventoy.' }
        $sig = Test-KitSignature -Path $exe.FullName
        Write-KitLog -Level OK -Message ("Ventoy {0} vérifié (SHA256 officiel ; {1})." -f $rel.Version, $sig)
    }
    return [pscustomobject]@{ Version = $rel.Version; Exe = $exe.FullName }
}

function Invoke-KitVentoy2Disk {
    <#
    .SYNOPSIS
        Lance Ventoy2Disk en ligne de commande (installation ou mise à jour) et suit la progression.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [ValidateSet('Install', 'Update')] [string] $Mode,
        [Parameter(Mandatory)] [int] $DiskNumber,
        [switch] $Gpt,
        [switch] $NoSecureBoot,
        [ValidateSet('exFAT', 'NTFS', 'FAT32')] [string] $FileSystem = 'exFAT'
    )
    $dir = Split-Path -Parent $Exe
    foreach ($f in 'cli_done.txt', 'cli_percent.txt', 'cli_log.txt') { Remove-Item -LiteralPath (Join-Path $dir $f) -Force -ErrorAction SilentlyContinue }
    $argList = @('VTOYCLI', $(if ($Mode -eq 'Install') { '/I' } else { '/U' }), "/PhyDrive:$DiskNumber")
    if ($Mode -eq 'Install') {
        if ($Gpt) { $argList += '/GPT' }
        if ($NoSecureBoot) { $argList += '/NOSB' }
        $argList += "/FS:$($FileSystem.ToUpperInvariant())"
    }
    if (-not $PSCmdlet.ShouldProcess("Disque $DiskNumber", "Ventoy2Disk $($argList -join ' ')")) { return }
    Write-KitLog -Level STEP -Message ("Ventoy2Disk {0}" -f ($argList -join ' '))
    $p = Start-Process -FilePath $Exe -ArgumentList $argList -WorkingDirectory $dir -PassThru
    $last = -1
    while (-not $p.HasExited) {
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
    Write-KitLog -Level OK -Message ("Ventoy : {0} terminée sur le disque {1}." -f $(if ($Mode -eq 'Install') { 'installation' } else { 'mise à jour' }), $DiskNumber)
}

function Wait-KitVentoyVolume {
    <#
    .SYNOPSIS
        Attend l'apparition de la partition de données « Ventoy » du disque et retourne sa lettre.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [int] $DiskNumber,
        [string] $Label = 'Ventoy',
        [int] $TimeoutSec = 90
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch { Write-Verbose 'Rafraîchissement du stockage indisponible.' }
        $part = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq $Label }) | Select-Object -First 1
        if ($part) {
            if (-not $part.DriveLetter -or $part.DriveLetter -eq [char]0) {
                $part | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue
                $part = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $part.PartitionNumber
            }
            if ($part.DriveLetter -and $part.DriveLetter -ne [char]0) { return [string]$part.DriveLetter }
        }
        Start-Sleep -Seconds 3
    }
    throw "La partition « $Label » du disque $DiskNumber n'est pas apparue (débranchez/rebranchez la clé puis relancez sans -InstallerVentoy)."
}

Export-ModuleMember -Function Test-KitAdmin, Get-KitUsbDisk, Assert-KitVentoyTarget, Save-KitVentoy, Invoke-KitVentoy2Disk, Wait-KitVentoyVolume
