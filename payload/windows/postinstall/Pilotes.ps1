<#
.SYNOPSIS
    Ouvre la source de pilotes adaptée au poste (liens officiels validés, ou SDIO depuis la clé).

.DESCRIPTION
    - Fabricant : détecté automatiquement (Dell, HP, Lenovo, ASUS, Acer, MSI, Surface) → page
      officielle de pilotes (liste dans pilotes.json, aucun pilote stocké dans le dépôt).
    - SDIO : Snappy Driver Installer Origin lancé depuis la clé s'il y est (fonctionne hors ligne
      avec des packs de pilotes, ou en ligne).
    - Windows : mises à jour facultatives (pilotes proposés par Windows Update).

.PARAMETER Source
    Auto (défaut : SDIO si présent et pas d'Internet, sinon page du fabricant), Fabricant, SDIO,
    Windows, Liste (affiche tous les liens).

.EXAMPLE
    .\Pilotes.ps1
.EXAMPLE
    .\Pilotes.ps1 -Source Liste
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Fabricant', 'SDIO', 'Windows', 'Liste')] [string] $Source = 'Auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$data = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pilotes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$keyRoot = Split-Path -Parent $PSScriptRoot
$sdio = @(Get-ChildItem -LiteralPath (Join-Path $keyRoot 'Logiciels\SDIO\app') -Filter 'SDIO_x64*.exe' -Recurse -File -ErrorAction SilentlyContinue) | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$maker = ''
if ($cs) { $maker = [string]$cs.Manufacturer }
$fab = @($data.Fabricants | Where-Object { $maker -match $_.Motif }) | Select-Object -First 1

$online = $false
try { $r = [Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt'); $r.Timeout = 4000; $r.GetResponse().Close(); $online = $true } catch { $online = $false }

if ($Source -eq 'Auto') {
    if ($sdio -and -not $online) { $Source = 'SDIO' }
    elseif ($fab) { $Source = 'Fabricant' }
    elseif ($sdio) { $Source = 'SDIO' }
    else { $Source = 'Windows' }
}

switch ($Source) {
    'SDIO' {
        if (-not $sdio) { throw 'SDIO n''est pas sur la clé (Logiciels\SDIO).' }
        Start-Process -FilePath $sdio.FullName -WorkingDirectory $sdio.DirectoryName
    }
    'Fabricant' {
        if (-not $fab) { throw "Fabricant non reconnu (« $maker ») : utilisez -Source Liste." }
        Write-Host ("Fabricant : {0} — outil recommandé : {1}" -f $fab.Nom, $fab.Outil)
        Start-Process $fab.Url
    }
    'Windows' { Start-Process $data.Windows.Url }
    'Liste' {
        Write-Host "PC : $maker $(if ($cs) { $cs.Model })"
        Write-Host "`nFabricants :"; $data.Fabricants | ForEach-Object { Write-Host ("  {0,-18} {1}" -f $_.Nom, $_.Url) }
        Write-Host "`nComposants :"; $data.Composants | ForEach-Object { Write-Host ("  {0,-38} {1}" -f $_.Nom, $_.Url) }
        Write-Host "`nWindows : $($data.Windows.Url)"
    }
}
