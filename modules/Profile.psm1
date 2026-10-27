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

function ConvertTo-KitTimeZone {
    <#
    .SYNOPSIS
        Convertit un fuseau horaire entre l'identifiant Windows (« Romance Standard Time ») et
        l'identifiant IANA de Linux (« Europe/Paris »). Clé double système : chaque système reçoit
        le format qu'il comprend (un fuseau invalide fait échouer l'installation automatique de Windows).
    .OUTPUTS
        L'identifiant converti, ou '' s'il est inconnu (fuseau laissé au choix du système).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('Windows', 'Iana')] [string] $To
    )
    if (-not $Id) { return '' }
    $isIana = ($Id -match '/' -or $Id -eq 'UTC' -or $Id -like 'Etc/*')
    if ($To -eq 'Iana' -and $isIana) { return $Id }
    if ($To -eq 'Windows' -and -not $isIana) { return $Id }
    # Table de secours (Windows PowerShell 5.1 n'a pas la conversion .NET) : fuseaux courants
    $table = @{
        'Greenwich Standard Time' = 'Africa/Abidjan'; 'GMT Standard Time' = 'Europe/London'; 'UTC' = 'Etc/UTC'
        'Romance Standard Time' = 'Europe/Paris'; 'W. Europe Standard Time' = 'Europe/Berlin'
        'W. Central Africa Standard Time' = 'Africa/Lagos'; 'Morocco Standard Time' = 'Africa/Casablanca'
        'E. Africa Standard Time' = 'Africa/Nairobi'; 'South Africa Standard Time' = 'Africa/Johannesburg'
        'Eastern Standard Time' = 'America/New_York'; 'Pacific Standard Time' = 'America/Los_Angeles'
        'Central Standard Time' = 'America/Chicago'; 'E. South America Standard Time' = 'America/Sao_Paulo'
        'SA Pacific Standard Time' = 'America/Bogota'; 'Canada Central Standard Time' = 'America/Regina'
    }
    $converted = ''
    try {
        if ($To -eq 'Iana') { [void][TimeZoneInfo]::TryConvertWindowsIdToIanaId($Id, [ref]$converted) }
        else { [void][TimeZoneInfo]::TryConvertIanaIdToWindowsId($Id, [ref]$converted) }
    }
    catch { $converted = '' }
    if ($converted) { return [string]$converted }
    if ($To -eq 'Iana') {
        if ($table.ContainsKey($Id)) { return $table[$Id] }
        return ''
    }
    foreach ($k in $table.Keys) { if ($table[$k] -eq $Id) { return $k } }
    if ($Id -eq 'Etc/UTC') { return 'UTC' }
    return ''
}

Export-ModuleMember -Function Copy-KitHashtable, Get-KitProfile, Get-KitProfileList, ConvertTo-KitTimeZone
