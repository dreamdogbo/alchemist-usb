#
# Profile.psm1 — Chargement des profils (types de clé), avec héritage
#
# Un profil (config/profils/<nom>.psd1) décrit un SYSTÈME (Windows / Linux) et un USAGE
# (Bureautique / Developpement). Il peut hériter d'un autre profil :
#   Herite       = 'ubuntu-bureautique'   # reprend tous les réglages et éléments du profil parent
#   Items        = @( ... )               # éléments AJOUTÉS (ou remplaçant un élément de même nom)
#   Retirer      = @('Nom1', 'Nom2')      # éléments du parent à retirer
#   ParDefaut    = @('Nom1')              # éléments du parent à cocher par défaut
#   NonParDefaut = @('Nom2')              # éléments du parent à décocher par défaut
#
Set-StrictMode -Version Latest

function Copy-KitHashtable {
    <#
    .SYNOPSIS
        Copie profonde d'un hashtable de profil (les éléments sont modifiés par la suite).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [hashtable] $Source)
    $copy = @{}
    foreach ($k in $Source.Keys) {
        $v = $Source[$k]
        if ($v -is [hashtable]) { $copy[$k] = Copy-KitHashtable -Source $v }
        elseif ($v -is [array]) { $copy[$k] = @($v | ForEach-Object { if ($_ -is [hashtable]) { Copy-KitHashtable -Source $_ } else { $_ } }) }
        else { $copy[$k] = $v }
    }
    return $copy
}

function Get-KitProfile {
    <#
    .SYNOPSIS
        Charge un profil et résout son héritage (au plus 5 niveaux).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $Name,
        [int] $Depth = 0
    )
    if ($Depth -gt 5) { throw "Héritage de profils trop profond (boucle ?) : $Name" }
    $path = Join-Path $Directory "$Name.psd1"
    if (-not (Test-Path -LiteralPath $path)) { throw "Profil « $Name » introuvable dans $Directory." }
    $data = Import-PowerShellDataFile -Path $path
    if (-not $data.ContainsKey('Herite') -or -not $data.Herite) { return (Copy-KitHashtable -Source $data) }

    $merged = Get-KitProfile -Directory $Directory -Name $data.Herite -Depth ($Depth + 1)
    foreach ($k in $data.Keys) {
        if ($k -in @('Items', 'Herite', 'Retirer', 'ParDefaut', 'NonParDefaut')) { continue }
        $merged[$k] = $data[$k]
    }
    $items = New-Object System.Collections.Generic.List[hashtable]
    $remove = @(); if ($data.ContainsKey('Retirer')) { $remove = @($data.Retirer) }
    $added = @(); if ($data.ContainsKey('Items')) { $added = @($data.Items | ForEach-Object { Copy-KitHashtable -Source $_ }) }
    $addedNames = @($added | ForEach-Object { $_.Name })
    foreach ($it in @($merged.Items)) {
        if ($it.Name -in $remove -or $it.Name -in $addedNames) { continue }
        if ($data.ContainsKey('ParDefaut') -and $it.Name -in @($data.ParDefaut)) { $it.Default = $true }
        if ($data.ContainsKey('NonParDefaut') -and $it.Name -in @($data.NonParDefaut)) { $it.Default = $false }
        $items.Add($it)
    }
    foreach ($it in $added) { $items.Add($it) }
    $merged.Items = $items.ToArray()
    return $merged
}

function Get-KitProfileList {
    <#
    .SYNOPSIS
        Liste des profils : nom de fichier, nom affiché, système, usage, description, données résolues.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)] [string] $Directory)
    $list = foreach ($f in @(Get-ChildItem -LiteralPath $Directory -Filter '*.psd1' | Sort-Object Name)) {
        $d = Get-KitProfile -Directory $Directory -Name $f.BaseName
        [pscustomobject]@{
            Name        = $f.BaseName
            Nom         = [string]$d['Nom']
            Systeme     = [string]$d['Systeme']
            Usage       = [string]$d['Usage']
            Description = [string]$d['Description']
            Ordre       = [int]$d['Ordre']
            Data        = $d
        }
    }
    return , @($list | Sort-Object Systeme, Ordre, Name)
}

Export-ModuleMember -Function Copy-KitHashtable, Get-KitProfile, Get-KitProfileList
