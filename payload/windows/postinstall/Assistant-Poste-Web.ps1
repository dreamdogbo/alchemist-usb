<#
.SYNOPSIS
    Assistant universel de post-installation Windows : même interface que l'assistant de création
    de clé et que la post-installation Linux (page web locale ouverte dans le navigateur).

.DESCRIPTION
    Affiche l'état de chaque logiciel du catalogue (déjà installé, sur la clé, en ligne via winget),
    lance Install-Poste.ps1 en administrateur (UAC) avec la sélection, et suit son journal en direct.
    La page n'est accessible que depuis ce poste (127.0.0.1, jeton aléatoire).
    Ouvert par Lancer.bat (fenêtre classique : Lancer.bat -Classique).

.PARAMETER SansNavigateur
    N'ouvre pas le navigateur ; l'adresse est affichée (tests).
.PARAMETER Port
    Port local imposé (tests).
.PARAMETER Jeton
    Jeton imposé (tests).
#>
[CmdletBinding()]
param(
    [switch] $SansNavigateur,
    [int] $Port = 0,
    [string] $Jeton = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module (Join-Path $here 'WebUi.psm1') -Force -DisableNameChecking
$ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps51)) { $ps51 = (Get-Process -Id $PID).Path }
$installScript = Join-Path $here 'Install-Poste.ps1'
$logDir = 'C:\PostInstall'
$version = ''
if (Test-Path -LiteralPath (Join-Path $here 'VERSION')) { $version = (Get-Content -LiteralPath (Join-Path $here 'VERSION') -TotalCount 1).Trim() }
$script:Etat = $null

function Get-Etat {
    <#
    .SYNOPSIS
        État du poste (Install-Poste.ps1 -Etat : mêmes règles de détection que l'installation).
    #>
    $json = & $ps51 -NoProfile -ExecutionPolicy Bypass -File $installScript -Etat 2>$null | Out-String
    if (-not $json.Trim()) { throw 'État du poste illisible (catalogue.json absent de la clé ?).' }
    $script:Etat = $json | ConvertFrom-Json
    return $script:Etat
}

$usage = 'bureautique'
try {
    $cat = Get-Content -LiteralPath (Join-Path $here 'catalogue.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cat.PSObject.Properties['Profile'] -and [string]$cat.Profile -match 'developpement') { $usage = 'developpement' }
}
catch { Write-Verbose 'catalogue.json illisible.' }

$routes = @{
    'GET /api/etat'       = {
        $internet = $null
        if ($script:Etat) { $internet = [bool]$script:Etat.Internet }
        [ordered]@{ mode = 'poste'; hote = 'Windows'; version = $version; usage = $usage; internet = $internet
            options = @('reglages', 'sansOffice', 'nomPoste'); travail = (Get-KitWebJobState -From 0) }
    }
    'GET /api/composants' = {
        $e = Get-Etat
        $list = foreach ($i in @($e.Items)) {
            $outil = [bool]$i.Launcher
            $etat = ''; $classe = ''
            if ($i.Installed) { $etat = 'déjà installé'; $classe = 'ok' }
            elseif ($outil) { $etat = 'outil portable'; $classe = '' }
            elseif ($i.OnKey) { $etat = 'sur la clé'; $classe = 'ok' }
            elseif ($i.WingetId -and $e.Internet) { $etat = 'en ligne (winget)'; $classe = 'alerte' }
            else { $etat = 'indisponible sans Internet'; $classe = 'erreur' }
            $defaut = ($i.Mode -ne 'Manuel' -and -not $i.Installed -and -not $outil)
            [ordered]@{ id = [string]$i.Name; nom = [string]$i.Name; categorie = [string]$i.Category
                description = $(if ($i.Version) { 'version ' + $i.Version } else { '' }); etat = $etat; classe = $classe
                outil = $outil; defautBur = $defaut; defautDev = $defaut }
        }
        [ordered]@{ composants = @($list); usage = $usage }
    }
    'POST /api/lancer'    = {
        param($d)
        if (Test-KitWebJobActive) { throw 'Une installation est déjà en cours.' }
        $sel = @(Get-KitWebValue $d 'elements' @() | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^[A-Za-z0-9_+.-]+$' })
        $reglages = [bool](Get-KitWebValue $d 'options.reglages' $true)
        $nom = [string](Get-KitWebValue $d 'options.nomPoste' '')
        if ($nom -and $nom -notmatch '^(?![0-9]+$)[A-Za-z0-9-]{1,15}$') { throw 'Nom de poste invalide.' }
        if ($sel.Count -eq 0 -and -not $reglages) { throw 'Rien à faire.' }
        $log = Join-Path $logDir ('assistant-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $list = '__aucun__'
        if ($sel.Count -gt 0) { $list = $sel -join ',' }
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $installScript), '-Logiciels', $list, '-Journal', ('"{0}"' -f $log))
        if (-not $reglages) { $a += '-SansReglages' }
        if (Get-KitWebValue $d 'options.sansOffice' $false) { $a += '-SansOffice' }
        if ($nom) { $a += @('-NomPoste', $nom) }
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Start-KitWebJob -FilePath $ps51 -ArgumentList $a -LogPath $log -Elevate:(-not $admin) -Confirm:$false
        [ordered]@{ ok = $true; journal = $log }
    }
    'POST /api/outil'     = {
        param($d)
        if (-not $script:Etat) { [void](Get-Etat) }
        $i = @($script:Etat.Items | Where-Object { $_.Name -eq [string](Get-KitWebValue $d 'id' '') -and $_.Launcher }) | Select-Object -First 1
        if (-not $i -or -not (Test-Path -LiteralPath $i.Launcher)) { throw 'Outil introuvable sur la clé.' }
        Start-Process -FilePath $i.Launcher -WorkingDirectory (Split-Path -Parent $i.Launcher)
        [ordered]@{ ok = $true }
    }
    'POST /api/ouvrir'    = {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($logDir)
        [ordered]@{ ok = $true }
    }
}

# Page : à côté du script sur la clé, sinon dans le dossier web/ du kit (dépôt)
$html = @((Join-Path $here 'alchemist.html'), (Join-Path $here '..\..\..\web\alchemist.html')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $html) { throw 'alchemist.html introuvable à côté de l''assistant.' }
Invoke-KitWebUi -HtmlPath $html -Routes $routes -NoBrowser:$SansNavigateur -Port $Port -Token $Jeton
