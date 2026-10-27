<#
.SYNOPSIS
    Assistant universel Alchemist : préparer une clé Ventoy depuis Windows OU Linux, avec la même
    interface (page web locale ouverte dans le navigateur).

.DESCRIPTION
    Système (Windows / Linux) → usage → contenu → clé (existante, ou neuve : Ventoy installé) →
    préparation suivie en direct. Le travail est fait par Build-Kit.ps1, comme en ligne de commande.
    La page n'est accessible que depuis ce poste (127.0.0.1, jeton aléatoire) ; l'assistant s'arrête
    tout seul quelques minutes après la fermeture de la page (jamais pendant une préparation).
    Droits administrateur / root demandés uniquement pour installer Ventoy sur une clé neuve
    (Windows : UAC ; Linux : pkexec).

    Windows : Creer-Cle.bat (fenêtre classique : Creer-Cle.bat -Classique).
    Linux   : bash creer-cle.sh  (fenêtres zenity : bash creer-cle.sh --zenity).

.PARAMETER SansNavigateur
    N'ouvre pas le navigateur ; l'adresse est affichée (tests, ou navigateur à ouvrir à la main).
.PARAMETER Port
    Port local imposé (tests). Défaut : port libre choisi par le système.
.PARAMETER Jeton
    Jeton imposé (tests). Défaut : jeton aléatoire.
.PARAMETER Simuler
    Tests : les préparations sont lancées en simulation (-DryRun), quelles que soient les options.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Simuler', Justification = 'Lu dans la route /api/lancer')]
[CmdletBinding()]
param(
    [switch] $SansNavigateur,
    [int] $Port = 0,
    [string] $Jeton = '',
    [switch] $Simuler
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$kitRoot = $PSScriptRoot
foreach ($m in @('Report', 'Drive', 'Download', 'Ventoy', 'Profile')) { Import-Module (Join-Path $kitRoot "modules/$m.psm1") -Force -DisableNameChecking }
Import-Module (Join-Path $kitRoot 'payload/windows/postinstall/WebUi.psm1') -Force -DisableNameChecking

$win = Test-KitWindows
$hote = $(if ($win) { 'Windows' } else { 'Linux' })
$version = ''
$vf = Join-Path $kitRoot 'VERSION'
if (Test-Path -LiteralPath $vf) { $version = (Get-Content -LiteralPath $vf -TotalCount 1).Trim() }
$logDir = Join-Path $kitRoot 'logs'
$psExe = $(if ($win) { Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe' } else { (Get-Process -Id $PID).Path })
[void](Initialize-KitLog -LogDirectory $logDir -Prefix 'assistant-web')

# Éléments qu'une préparation depuis Linux laisse à la post-installation (winget, Office, sans empreinte)
function Test-SurLePoste {
    param($Item)
    if ($win) { return $false }
    if ($Item.Type -in @('Winget', 'Office')) { return $true }
    if ($Item.Type -eq 'Url') { return (@($Item.Files | Where-Object { -not (Get-KitValue $_ 'Sha256' '') }).Count -gt 0) }
    return $false
}

# Linux : clé Ventoy branchée mais pas montée => montée pour l'utilisateur (comme le gestionnaire de fichiers)
function Mount-VentoyLinux {
    if ($win -or -not (Get-Command udisksctl -ErrorAction SilentlyContinue)) { return }
    $blocks = @(Get-KitLinuxBlock)
    foreach ($b in $blocks) {
        if ($b.type -eq 'part' -and -not $b.mountpoint -and ($b.label -eq 'Ventoy' -or (Test-KitLinuxVentoyPart -Part $b -Blocks $blocks))) {
            & udisksctl mount -b $b.path 2>&1 | Out-Null
        }
    }
}

$routes = @{
    'GET /api/etat'     = {
        [ordered]@{ mode = 'creer'; hote = $hote; version = $version; admin = (Test-KitAdmin); travail = (Get-KitWebJobState -From 0) }
    }
    'GET /api/profils'  = {
        $list = foreach ($p in (Get-KitProfileList -Directory (Join-Path $kitRoot 'config/profils'))) {
            $d = $p.Data
            $langs = @()
            if ($d.ContainsKey('Langues')) { $langs = @($d.Langues.Keys | Sort-Object | ForEach-Object { [ordered]@{ Code = $_; Label = [string]$d.Langues[$_].Label } }) }
            [ordered]@{
                Profil = $p.Name; Nom = $p.Nom; Systeme = $p.Systeme; Usage = $p.Usage; Description = $p.Description
                LangueDefaut = [string]$d['LangueDefaut']; Langues = $langs
                Items = @($d.Items | ForEach-Object {
                        [ordered]@{
                            Name = $_.Name; Category = [string]$_['Category']; Type = $_.Type; Mode = [string]$_['Mode']
                            Default = -not ($_.ContainsKey('Default') -and -not $_.Default); SizeMB = [int]$_['EstimatedSizeMB']
                            Compat = @(Get-KitValue $_ 'Compat' @()); SurLePoste = (Test-SurLePoste $_)
                        }
                    })
            }
        }
        [ordered]@{ profils = @($list) }
    }
    'GET /api/cles'     = {
        Mount-VentoyLinux
        $ventoy = @(Find-KitVentoyDrive | ForEach-Object { [ordered]@{ Root = $_.Root; Label = $_.Label; FileSystem = $_.FileSystem; FreeGB = $_.FreeGB; TotalGB = $_.TotalGB } })
        $disques = @(Get-KitUsbDisk | ForEach-Object { [ordered]@{ Id = $_.Id; Model = $_.Model; SizeGB = $_.SizeGB; IsVentoy = $_.IsVentoy; Letters = @($_.Letters) } })
        [ordered]@{ ventoy = $ventoy; disques = $disques; admin = (Test-KitAdmin) }
    }
    'POST /api/lancer'  = {
        param($d)
        if (Test-KitWebJobActive) { throw 'Une préparation est déjà en cours.' }
        $profil = [string](Get-KitWebValue $d 'profil' '')
        if ($profil -notmatch '^[a-z0-9-]+$' -or -not (Test-Path -LiteralPath (Join-Path $kitRoot "config/profils/$profil.psd1"))) { throw "Profil inconnu : $profil" }
        $elements = @(Get-KitWebValue $d 'elements' @() | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^[A-Za-z0-9_+.-]+$' })
        if ($elements.Count -eq 0) { throw 'Aucun élément choisi.' }
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $log = Join-Path $logDir ('assistant-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $engine = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $kitRoot 'Build-Kit.ps1'), '-Profil', $profil, '-Only', ($elements -join ','), '-LogFile', $log)
        $langue = [string](Get-KitWebValue $d 'langue' '')
        if ($langue) { if ($langue -notmatch '^[a-z]{2}$') { throw 'Langue invalide.' }; $engine += @('-Langue', $langue) }
        if ((Get-KitWebValue $d 'simulation' $false) -or $Simuler) { $engine += '-DryRun' }
        $iso = [string](Get-KitWebValue $d 'isoUrl' '')
        if ($iso) {
            $u = $null
            if (-not [uri]::TryCreate($iso, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -ne 'https' -or $u.Host -notmatch '(^|\.)microsoft\.com$') { throw 'Le lien de l''ISO doit être une adresse https://…microsoft.com.' }
            $engine += @('-WindowsIsoUrl', $iso)
        }
        $elevate = $false
        if ([string](Get-KitWebValue $d 'cle.mode' '') -eq 'neuve') {
            if ([string](Get-KitWebValue $d 'cle.confirmation' '') -cne 'EFFACER') { throw 'Confirmation d''effacement manquante (tapez EFFACER).' }
            # Disque revérifié côté serveur : seule une clé USB/SD éligible est acceptée
            $target = Assert-KitVentoyTarget -Disk ([string](Get-KitWebValue $d 'cle.disque' '')) -KitRoot $kitRoot
            $name = Split-Path -Leaf $target.Id
            $engine += @('-InstallerVentoy', '-Disque', $target.Id, '-ConfirmerEffacement', "EFFACER-$name")
            $elevate = -not (Test-KitAdmin)
        }
        else {
            $root = [string](Get-KitWebValue $d 'cle.racine' '')
            if (-not $root) { throw 'Aucune clé choisie.' }
            $engine += @('-KeyPath', $root)
        }
        $quote = { param($a) if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
        if ($win) {
            # Windows PowerShell 5.1 : arguments passés en une chaîne (chemins avec espaces protégés)
            Start-KitWebJob -FilePath $psExe -ArgumentList @($engine | ForEach-Object { & $quote $_ }) -LogPath $log -Elevate:$elevate -Confirm:$false
        }
        elseif ($elevate) {
            if (-not (Get-Command pkexec -ErrorAction SilentlyContinue)) { throw 'pkexec est introuvable : relancez l''assistant avec sudo pour installer Ventoy.' }
            # pkexec : environnement minimal ; SUDO_UID/GID => la clé est montée pour l'utilisateur
            $envArgs = @('env', "PATH=$env:PATH", "HOME=$env:HOME", "SUDO_UID=$(& id -u)", "SUDO_GID=$(& id -g)", "SUDO_USER=$(& id -un)")
            Start-KitWebJob -FilePath 'pkexec' -ArgumentList ($envArgs + @($psExe) + $engine) -LogPath $log -Confirm:$false
        }
        else { Start-KitWebJob -FilePath $psExe -ArgumentList $engine -LogPath $log -Confirm:$false }
        [ordered]@{ ok = $true; journal = $log }
    }
    'POST /api/ouvrir'  = {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        if ($win) { Start-Process -FilePath 'explorer.exe' -ArgumentList @($logDir) } else { Start-Process -FilePath 'xdg-open' -ArgumentList @($logDir) }
        [ordered]@{ ok = $true }
    }
}

$html = Join-Path $kitRoot 'web/alchemist.html'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Invoke-KitWebUi -HtmlPath $html -Routes $routes -NoBrowser:$SansNavigateur -Port $Port -Token $Jeton -UrlFile (Join-Path $logDir 'assistant-ouvert.url')
