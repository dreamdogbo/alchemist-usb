#
# Sync.psm1 — Mise en place sur la clé, remplacement des anciennes versions, MANIFEST.sha256
#
# Règles de sécurité :
#  - Seuls les fichiers listés dans /MANIFEST.sha256 appartiennent au kit. Ce sont les SEULS
#    que le kit remplace ou supprime.
#  - Un fichier déjà présent sur la clé mais absent du MANIFEST est un fichier personnel :
#    il n'est jamais écrasé (l'élément concerné est alors signalé en conflit).
#  - La zone de préparation (cache) est sur le même volume : la mise en place est un simple
#    déplacement (instantané, sans doubler l'espace occupé).
#  - Un fichier identique (même SHA256) déjà en place n'est ni recopié ni déplacé.
#
Set-StrictMode -Version Latest

$script:ManifestName = 'MANIFEST.sha256'

function ConvertTo-KitRelPath {
    <#
    .SYNOPSIS
        Chemin relatif à la racine de la clé, avec des « / » (format du MANIFEST).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $FullPath
    )
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $f = [IO.Path]::GetFullPath($FullPath)
    if (-not $f.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { throw "$f n'est pas sous $r" }
    return $f.Substring($r.Length).Replace('\', '/')
}

function Read-KitManifest {
    <#
    .SYNOPSIS
        Lit /MANIFEST.sha256 (format « sha256sum » : « <empreinte> *<chemin> »).
    .OUTPUTS
        Hashtable (insensible à la casse) chemin relatif -> SHA256.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string] $KeyRoot)
    $map = @{}
    $path = Join-Path $KeyRoot $script:ManifestName
    if (Test-Path -LiteralPath $path) {
        foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
            if ($line -match '^([0-9a-fA-F]{64}) [ *](.+)$') { $map[$Matches[2].Trim()] = $Matches[1].ToLowerInvariant() }
        }
    }
    return $map
}

function Write-KitManifest {
    <#
    .SYNOPSIS
        Réécrit /MANIFEST.sha256 (trié, sans les fichiers disparus), de façon atomique.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest
    )
    $lines = foreach ($k in ($Manifest.Keys | Sort-Object)) {
        if (Test-Path -LiteralPath (Join-Path $KeyRoot $k)) { "{0} *{1}" -f $Manifest[$k], $k }
    }
    $path = Join-Path $KeyRoot $script:ManifestName
    $tmp = "$path.tmp"
    # UTF-8 sans BOM et fins de ligne LF : compatible « sha256sum -c »
    [IO.File]::WriteAllText($tmp, ((@($lines) -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Get-KitManagedSize {
    <#
    .SYNOPSIS
        Taille totale des fichiers gérés (présents dans le MANIFEST) sous un préfixe.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest,
        [Parameter(Mandatory)] [string] $Prefix
    )
    $sum = 0.0
    foreach ($k in @($Manifest.Keys)) {
        if ($k.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $p = Join-Path $KeyRoot $k
            if (Test-Path -LiteralPath $p) { $sum += (Get-Item -LiteralPath $p).Length }
        }
    }
    return $sum
}

function Remove-KitEmptyDirectory {
    <#
    .SYNOPSIS
        Supprime les dossiers vides sous un dossier (du plus profond au moins profond).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $IncludeRoot
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Path -Recurse -Directory -Force | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($d in $dirs) {
        if (@(Get-ChildItem -LiteralPath $d.FullName -Force).Count -eq 0 -and $PSCmdlet.ShouldProcess($d.FullName, 'Supprimer dossier vide')) {
            Remove-Item -LiteralPath $d.FullName -Force
        }
    }
    if ($IncludeRoot -and @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0 -and $PSCmdlet.ShouldProcess($Path, 'Supprimer dossier vide')) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Sync-KitStage {
    <#
    .SYNOPSIS
        Met en place sur la clé le contenu d'une zone de préparation.
    .DESCRIPTION
        1. Pour chaque fichier préparé : calcul SHA256 ; s'il est identique au fichier géré
           déjà en place, rien n'est fait ; sinon il remplace l'ancien (déplacement).
           Si la destination existe mais n'est PAS gérée par le kit : conflit, on n'y touche pas.
        2. Les anciens fichiers gérés situés sous ObsoleteScope et qui ne font plus partie de
           la nouvelle version sont supprimés (pas de cumul de versions).
        3. Le MANIFEST (en mémoire) est mis à jour ; l'appelant l'écrit sur la clé.
    .OUTPUTS
        Objet : Moved, Unchanged, Removed, Conflicts (liste), Bytes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $StageDir,
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $TargetDir,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest,
        [string[]] $ObsoleteScope = @(),
        [switch] $KeepStage
    )
    $targetRoot = $KeyRoot
    if ($TargetDir) { $targetRoot = Join-Path $KeyRoot ($TargetDir.Replace('/', '\')) }
    $result = [pscustomobject]@{ Moved = 0; Unchanged = 0; Removed = 0; Conflicts = @(); Bytes = 0.0 }
    $newSet = @{}

    $files = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File -Force |
            Where-Object { $_.Name -notlike '*.part' -and $_.Name -notlike '*.part.src' })
    foreach ($f in $files) {
        $relInStage = ConvertTo-KitRelPath -Root $StageDir -FullPath $f.FullName
        $dest = Join-Path $targetRoot ($relInStage.Replace('/', '\'))
        $rel = ConvertTo-KitRelPath -Root $KeyRoot -FullPath $dest
        $len = $f.Length
        if ($len -gt 1GB) { Write-KitLog -Message ("SHA256 de {0} ({1})…" -f $rel, (Format-KitSize $len)) }
        $sha = Get-KitSha256 -Path $f.FullName
        $newSet[$rel] = $true

        if (Test-Path -LiteralPath $dest) {
            if (-not $Manifest.ContainsKey($rel)) {
                $result.Conflicts += $rel
                Write-KitLog -Level WARN -Message "Conflit : $rel existe déjà sur la clé et n'appartient pas au kit. Il n'est PAS remplacé."
                continue
            }
            if ($Manifest[$rel] -eq $sha) {
                $result.Unchanged++
                if (-not $KeepStage -and $PSCmdlet.ShouldProcess($f.FullName, 'Supprimer copie identique')) { Remove-Item -LiteralPath $f.FullName -Force }
                continue
            }
            if ($PSCmdlet.ShouldProcess($dest, 'Remplacer')) { Remove-Item -LiteralPath $dest -Force }
        }
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        if ($PSCmdlet.ShouldProcess($dest, 'Mettre en place')) {
            if ($KeepStage) { Copy-Item -LiteralPath $f.FullName -Destination $dest -Force }
            else { Move-Item -LiteralPath $f.FullName -Destination $dest -Force }
            $Manifest[$rel] = $sha
            $result.Moved++
            $result.Bytes += $len
        }
    }

    # Anciennes versions gérées : supprimées si elles ne font plus partie du nouvel ensemble
    foreach ($scope in $ObsoleteScope) {
        foreach ($k in @($Manifest.Keys)) {
            if ($k.StartsWith($scope, [StringComparison]::OrdinalIgnoreCase) -and -not $newSet.ContainsKey($k)) {
                $p = Join-Path $KeyRoot ($k.Replace('/', '\'))
                if ((Test-Path -LiteralPath $p) -and $PSCmdlet.ShouldProcess($p, 'Supprimer ancienne version')) {
                    Remove-Item -LiteralPath $p -Force
                    $result.Removed++
                }
                $Manifest.Remove($k)
            }
        }
        $scopeDir = Join-Path $KeyRoot ($scope.TrimEnd('/').Replace('/', '\'))
        if (Test-Path -LiteralPath $scopeDir -PathType Container) { Remove-KitEmptyDirectory -Path $scopeDir }
    }

    if (-not $KeepStage) { Remove-KitEmptyDirectory -Path $StageDir -IncludeRoot }
    Write-KitLog -Message ("Mise en place : {0} fichier(s) écrit(s), {1} identique(s), {2} ancien(s) supprimé(s), {3} conflit(s)" -f
        $result.Moved, $result.Unchanged, $result.Removed, $result.Conflicts.Count)
    return $result
}

function New-KitCatalogue {
    <#
    .SYNOPSIS
        Construit catalogue.json pour Install-Poste.ps1 à partir de la config et de la clé.
    .DESCRIPTION
        Un logiciel absent de la clé reste dans le catalogue (Installer = null) : sur le poste,
        il sera installé via winget si Internet est disponible.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object[]] $Items,
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [string] $Destination,
        [string] $ProfileName = '',
        [string] $TimeZone = 'Greenwich Standard Time'
    )
    $entries = foreach ($item in $Items) {
        if ($item.Type -in @('WindowsIso', 'LinuxIso')) { continue }
        $src = Get-KitKeySource -KeyRoot $KeyRoot -Item $item
        $installer = $null
        if ($item.Type -eq 'Office') {
            if ($src -and (Test-Path -LiteralPath (Join-Path (Join-Path $KeyRoot $item.TargetDir) 'setup.exe'))) { $installer = 'setup.exe' }
        }
        elseif ($src -and -not (Get-KitValue $item 'Extract' $false)) {
            $name = [string](Get-KitValue $src 'Installer' '')
            if ($name -and (Test-Path -LiteralPath (Join-Path (Join-Path $KeyRoot $item.TargetDir) $name))) { $installer = $name }
        }
        # Outil portable : programme à lancer directement depuis la clé
        $launcher = $null
        $pattern = [string](Get-KitValue $item 'Launcher' '')
        if ($pattern) {
            $appDir = Join-Path (Join-Path $KeyRoot $item.TargetDir) 'app'
            $exe = @(Get-ChildItem -LiteralPath $appDir -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue) | Sort-Object Name -Descending | Select-Object -First 1
            if ($exe) { $launcher = 'app\' + $exe.FullName.Substring($appDir.Length).TrimStart('\') }
        }
        [ordered]@{
            Name         = $item.Name
            Category     = [string](Get-KitValue $item 'Category' 'Logiciel')
            Mode         = [string](Get-KitValue $item 'Mode' 'Auto')
            Type         = $item.Type
            Folder       = $item.TargetDir.Replace('/', '\')
            Installer    = $installer
            Launcher     = $launcher
            Version      = [string](Get-KitValue $src 'Version' '')
            SilentArgs   = [string](Get-KitValue $item 'SilentArgs' '')
            SuccessCodes = @(Get-KitValue $item 'SuccessCodes' @(0))
            Detection    = [string](Get-KitValue $item 'Detection' '')
            WingetId     = [string](Get-KitValue $item 'WingetId' '')
            ProductId    = [string](Get-KitValue $item 'ProductId' '')
            PostAction   = [string](Get-KitValue $item 'PostAction' '')
            Order        = [int](Get-KitValue $item 'Order' 99)
        }
    }
    $doc = [ordered]@{
        Generated = (Get-Date).ToString('s')
        Profile   = $ProfileName
        Settings  = [ordered]@{ TimeZone = $TimeZone }
        Items     = @($entries | Sort-Object { $_.Order })
    }
    $json = $doc | ConvertTo-Json -Depth 5
    if ($PSCmdlet.ShouldProcess($Destination, 'Écrire catalogue.json')) {
        [IO.File]::WriteAllText($Destination, $json, (New-Object Text.UTF8Encoding($true)))
    }
    return $Destination
}

Export-ModuleMember -Function ConvertTo-KitRelPath, Read-KitManifest, Write-KitManifest, Get-KitManagedSize,
    Remove-KitEmptyDirectory, Sync-KitStage, New-KitCatalogue
