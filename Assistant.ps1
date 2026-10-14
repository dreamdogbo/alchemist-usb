<#
.SYNOPSIS
    Assistant graphique (fenêtre Windows) de préparation d'une clé Ventoy.

.DESCRIPTION
    Pour les non-experts : choix du type de clé (profil), détection de la clé Ventoy,
    sélection des logiciels par cases à cocher, options (vérification des signatures,
    sauvegarde des données de la clé, simulation), puis exécution de Build-Kit.ps1 avec
    affichage du journal en direct.
    Aucune logique de préparation n'est dupliquée ici : la fenêtre construit simplement la
    ligne de commande de Build-Kit.ps1, qui reste utilisable seul.

.EXAMPLE
    Double-clic sur Creer-Cle.bat
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Assistant.ps1
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Fonctions internes d''interface graphique')]
[CmdletBinding()]
param(
    # Langue de l'interface (fichier lang\<code>.psd1). Défaut : langue de Windows, sinon fr.
    [string] $Interface,
    # Construit la fenêtre sans l'afficher (test automatique)
    [switch] $TestSansAffichage,
    # Avec -TestSansAffichage : enregistre une capture PNG de la fenêtre (documentation, tests)
    [string] $Capture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
# Une erreur imprévue dans la fenêtre est écrite dans le journal au lieu d'afficher
# la boîte « exception non gérée » de .NET
# Une seule fois par processus : le changement de langue relance l'assistant dans le même
# processus, et Windows refuse de modifier ce mode une fois des fenêtres créées.
if (-not [AppDomain]::CurrentDomain.GetData('AlchemistUiReady')) {
    [AppDomain]::CurrentDomain.SetData('AlchemistUiReady', $true)
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
            param($s, $e)
            [void]$s
            try { Add-LogLine -Line ('[ERROR] ' + $e.Exception.Message) } catch { Write-Verbose $e.Exception.Message }
        })
}

$kitRoot = $PSScriptRoot
Import-Module (Join-Path $kitRoot 'modules\Report.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $kitRoot 'modules\Drive.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $kitRoot 'modules\Ventoy.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $kitRoot 'modules\Profile.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $kitRoot 'payload\windows\postinstall\KitUi.psm1') -Force -DisableNameChecking

$script:Process = $null
$script:LogPath = ''
$script:LogPos = 0L
$script:Profiles = @()
$script:Systems = @()
$script:Usages = @()
$script:SystemCombo = $null
$script:Hint = $null
$script:UsageCombo = $null
$script:TotalLabel = $null
$script:LogBox = $null
$script:Restart = $false
$script:LangCodes = @()
$script:DriveItems = @()
$script:ChkInstallVentoy = $null
$script:ChkUpdateVentoy = $null
$script:PersonalIsos = @()
$script:IsoPersoBox = $null
$script:BtnIsoPersoClear = $null

# --------------------------------------------------------------------------- langue de l'interface
$langDir = Join-Path $kitRoot 'lang'
if (-not $Interface) { $Interface = ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName) }
if (-not (Test-Path -LiteralPath (Join-Path $langDir "$Interface.psd1"))) { $Interface = 'fr' }
$script:Lfr = Import-PowerShellDataFile -Path (Join-Path $langDir 'fr.psd1')
$script:L = Import-PowerShellDataFile -Path (Join-Path $langDir "$Interface.psd1")

function T {
    <#
    .SYNOPSIS
        Texte traduit (repli sur le français si la clé manque dans la langue choisie).
    #>
    param([string] $Key)
    if ($script:L.ContainsKey($Key)) { return $script:L[$Key] }
    if ($script:Lfr.ContainsKey($Key)) { return $script:Lfr[$Key] }
    return $Key
}

# --------------------------------------------------------------------------- utilitaires
function New-Label {
    <#
    .SYNOPSIS
        Crée une étiquette positionnée.
    #>
    param([string] $Text, [int] $X, [int] $Y, [int] $W = 120, [int] $H = 22, [switch] $Bold)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X, $Y); $l.Size = New-Object System.Drawing.Size($W, $H)
    if ($Bold) { $l.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold) }
    return $l
}

function Add-LogLine {
    <#
    .SYNOPSIS
        Ajoute une ligne colorée selon son niveau dans la zone de journal.
    #>
    param([string] $Line)
    $color = [System.Drawing.Color]::Gainsboro
    if ($Line -match '\[(OK)\s*\]') { $color = [System.Drawing.Color]::LightGreen }
    elseif ($Line -match '\[WARN\s*\]') { $color = [System.Drawing.Color]::Khaki }
    elseif ($Line -match '\[ERROR\s*\]') { $color = [System.Drawing.Color]::Salmon }
    elseif ($Line -match '\[STEP\s*\]') { $color = [System.Drawing.Color]::SkyBlue }
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor = $color
    $script:LogBox.AppendText($Line + [Environment]::NewLine)
    $script:LogBox.ScrollToCaret()
}

function Read-NewLogLine {
    <#
    .SYNOPSIS
        Lit les nouvelles lignes du journal de Build-Kit (fichier partagé, lecture incrémentale).
    #>
    if (-not $script:LogPath -or -not (Test-Path -LiteralPath $script:LogPath)) { return }
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($script:LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($fs.Length -le $script:LogPos) { return }
        [void]$fs.Seek($script:LogPos, [IO.SeekOrigin]::Begin)
        $sr = New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        $script:LogPos = $fs.Length
        foreach ($l in ($text -split "`r?`n")) { if ($l) { Add-LogLine -Line $l } }
        # Dernière étape connue affichée dans la barre d'état
        $step = ($text -split "`r?`n" | Where-Object { $_ -match '\[STEP\s*\]|---' } | Select-Object -Last 1)
        if ($step) { $script:Status.Text = ($step -replace '^.*\]\s*', '') }
    }
    catch { Write-Verbose $_.Exception.Message }
    finally { if ($fs) { $fs.Dispose() } }
}

function Get-SelectedProfile {
    <#
    .SYNOPSIS
        Profil correspondant au système et à l'usage choisis dans la fenêtre.
    #>
    if (-not $script:SystemCombo -or $script:SystemCombo.SelectedIndex -lt 0 -or $script:UsageCombo.SelectedIndex -lt 0) { return $null }
    $sys = $script:Systems[$script:SystemCombo.SelectedIndex]
    $use = $script:Usages[$script:UsageCombo.SelectedIndex]
    return (@($script:Profiles | Where-Object { $_.Systeme -eq $sys -and $_.Usage -eq $use }) | Select-Object -First 1)
}

function Update-DriveList {
    <#
    .SYNOPSIS
        Recherche les clés Ventoy branchées et remplit la liste déroulante.
    #>
    $script:DriveCombo.Items.Clear()
    $script:DriveItems = @()
    if ($script:ChkInstallVentoy -and $script:ChkInstallVentoy.Checked) {
        # Clé neuve : disques USB/SD éligibles (jamais le disque système : filtré par Get-KitUsbDisk)
        foreach ($u in @(Get-KitUsbDisk)) {
            $state = if ($u.IsVentoy) { T 'UsbVentoy' } else { T 'UsbNotVentoy' }
            if ($u.IsReadOnly) { $state += ' — ' + (T 'UsbReadOnly') }
            $letters = (@($u.Letters | ForEach-Object { "${_}:" }) -join ' ')
            [void]$script:DriveCombo.Items.Add(((T 'UsbDiskFormat') -f $u.Number, $u.Model, $u.SizeGB, ("$state $letters").Trim()))
            $script:DriveItems += $u
        }
        $script:DriveCombo.ForeColor = (Get-KitUiTheme).Danger
        if ($script:DriveCombo.Items.Count -eq 0) { [void]$script:DriveCombo.Items.Add((T 'NoUsbDisk')) }
        $script:DriveCombo.SelectedIndex = 0
        return
    }
    $script:DriveCombo.ForeColor = [System.Drawing.SystemColors]::WindowText
    $label = 'Ventoy'
    $sel = Get-SelectedProfile
    if ($sel) { $label = $sel.Data.VolumeLabel }
    foreach ($d in @(Find-KitVentoyDrive -ExpectedLabel $label)) {
        [void]$script:DriveCombo.Items.Add(((T 'DriveFormat') -f $d.Root, $d.Label, $d.FreeGB, $d.TotalGB))
        $script:DriveItems += $d
    }
    if ($script:DriveCombo.Items.Count -gt 0) { $script:DriveCombo.SelectedIndex = 0 }
    else { [void]$script:DriveCombo.Items.Add((T 'NoDrive')); $script:DriveCombo.SelectedIndex = 0 }
}

function Update-ItemList {
    <#
    .SYNOPSIS
        Affiche les éléments du profil choisi, groupés par catégorie, cochés par défaut.
    #>
    $script:ItemList.BeginUpdate()
    $script:ItemList.Items.Clear(); $script:ItemList.Groups.Clear()
    $p = Get-SelectedProfile
    if (-not $p) { return }
    $script:ProfileDesc.Text = $p.Data.Description
    if ($script:Hint) { $script:Hint.Text = $(if ($p.Systeme -eq 'Linux') { T 'LinuxHint' } else { T 'FreeSuiteHint' }) }
    # Langues de contenu proposées par le profil (langue de l'interface présélectionnée si possible)
    $script:LangCombo.Items.Clear()
    $script:LangCodes = @()
    if ($p.Data.ContainsKey('Langues')) {
        $script:LangCodes = @($p.Data.Langues.Keys | Sort-Object)
        foreach ($c in $script:LangCodes) { [void]$script:LangCombo.Items.Add(("{0} ({1})" -f $p.Data.Langues[$c].Label, $c)) }
        $pref = $Interface
        if ($script:LangCodes -notcontains $pref) { $pref = $p.Data.LangueDefaut }
        $script:LangCombo.SelectedIndex = [array]::IndexOf($script:LangCodes, $pref)
    }
    $groups = @{}
    foreach ($it in @($p.Data.Items)) {
        $cat = 'Logiciel'; if ($it.ContainsKey('Category')) { $cat = $it.Category }
        if (-not $groups.ContainsKey($cat)) {
            $g = New-Object System.Windows.Forms.ListViewGroup($cat, $cat)
            [void]$script:ItemList.Groups.Add($g); $groups[$cat] = $g
        }
        $mode = 'Auto'; if ($it.ContainsKey('Mode')) { $mode = $it.Mode }
        $size = 0; if ($it.ContainsKey('EstimatedSizeMB')) { $size = [int]$it.EstimatedSizeMB }
        $lvi = New-Object System.Windows.Forms.ListViewItem($it.Name, $groups[$cat])
        [void]$lvi.SubItems.Add($(if ($size -ge 1024) { (T 'UnitGB') -f ($size / 1024) } else { (T 'UnitMB') -f $size }))
        $isSystem = $it.Type -in @('WindowsIso', 'LinuxIso')
        [void]$lvi.SubItems.Add($(if ($isSystem) { (T 'UsageSystem') } elseif ($mode -eq 'Manuel') { (T 'UsageManual') } else { (T 'UsageAuto') }))
        [void]$lvi.SubItems.Add([string]$it.Type)
        [void]$lvi.SubItems.Add((Get-ItemCompat -Item $it -Systeme $p.Systeme))
        $lvi.Checked = -not ($it.ContainsKey('Default') -and -not $it.Default)
        $lvi.Tag = $it
        $lvi.ImageKey = $(if ($isSystem) { 'system' } elseif ($mode -eq 'Manuel') { 'tool' } else { 'package' })
        [void]$script:ItemList.Items.Add($lvi)
    }
    $script:ItemList.EndUpdate()
    Update-Total
    Update-DriveList
}

function Get-ItemCompat {
    <#
    .SYNOPSIS
        Versions de Windows compatibles avec un élément (colonne « Windows » de la liste).
    #>
    param([hashtable] $Item, [string] $Systeme)
    if ($Systeme -ne 'Windows' -or $Item.Type -eq 'LinuxIso') { return '' }
    if ($Item.Type -eq 'WindowsIso') { return [string]$Item['FidoWin'] }
    $c = @('11', '10'); if ($Item.ContainsKey('Compat')) { $c = @($Item.Compat) }
    return ($c -join ' · ')
}

function Set-Win7Pack {
    <#
    .SYNOPSIS
        Coche les éléments du pack de compatibilité Windows 7 (quand une ISO de Windows 7 est ajoutée).
    #>
    $n = 0
    foreach ($i in $script:ItemList.Items) {
        if ($i.Tag -is [hashtable] -and $i.Tag.ContainsKey('Compat') -and @($i.Tag.Compat) -contains '7' -and -not $i.Checked) { $i.Checked = $true; $n++ }
    }
    return $n
}

function Update-PersonalIso {
    <#
    .SYNOPSIS
        Affiche les images personnelles choisies (nom des fichiers).
    #>
    $script:IsoPersoBox.Text = (@($script:PersonalIsos | ForEach-Object { Split-Path -Leaf $_ }) -join ' ; ')
    $script:BtnIsoPersoClear.Enabled = ($script:PersonalIsos.Count -gt 0)
}

function Update-Total {
    <#
    .SYNOPSIS
        Affiche la taille estimée de la sélection.
    #>
    # Windows déclenche « ItemChecked » pendant la construction de la liste : on ignore
    # les éléments pas encore prêts (sinon StrictMode lève une erreur sur un objet vide).
    if (-not $script:TotalLabel) { return }
    $sum = 0; $count = 0
    for ($k = 0; $k -lt $script:ItemList.Items.Count; $k++) {
        $i = $script:ItemList.Items[$k]
        if ($null -eq $i -or -not $i.Checked) { continue }
        $count++
        if ($i.Tag -is [hashtable] -and $i.Tag.ContainsKey('EstimatedSizeMB')) { $sum += [int]$i.Tag.EstimatedSizeMB }
    }
    $script:TotalLabel.Text = ((T 'Selection') -f $count, ($sum / 1024))
}

function Set-Running {
    <#
    .SYNOPSIS
        Bascule l'interface en mode « exécution en cours » ou « prête ».
    #>
    param([bool] $Running)
    foreach ($c in @($script:BtnSimulate, $script:BtnBuild, $script:SystemCombo, $script:UsageCombo, $script:DriveCombo, $script:ItemList, $script:BtnRefresh, $btnIsoPerso)) { $c.Enabled = -not $Running }
    $script:BtnStop.Enabled = $Running
    if ($Running) { $script:Progress.Style = 'Marquee' } else { $script:Progress.Style = 'Blocks'; $script:Progress.Value = 0 }
}

function Start-Build {
    <#
    .SYNOPSIS
        Lance Build-Kit.ps1 avec les choix de la fenêtre, dans un processus séparé.
    #>
    param([bool] $Simulation)
    $selected = @($script:ItemList.CheckedItems | ForEach-Object { $_.Text })
    if ($selected.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show((T 'NeedOneItem'), 'Alchemist'); return }
    $installVentoy = $script:ChkInstallVentoy.Checked
    $idx = $script:DriveCombo.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $script:DriveItems.Count) { [void][System.Windows.Forms.MessageBox]::Show((T 'NeedDrive'), 'Alchemist'); return }
    $target = $script:DriveItems[$idx]
    $letter = ''
    if (-not $installVentoy) { $letter = [string]$target.Letter }
    if ($script:ChkBackup.Checked -and -not $script:BackupPath.Text) { [void][System.Windows.Forms.MessageBox]::Show((T 'NeedBackupPath'), 'Alchemist'); return }
    if ($installVentoy -and -not $Simulation) {
        # Effacement : confirmation tapée obligatoire
        Add-Type -AssemblyName Microsoft.VisualBasic
        $word = T 'ConfirmWord'
        $typed = [Microsoft.VisualBasic.Interaction]::InputBox(((T 'ConfirmText') -f $target.Number, $target.Model, $target.SizeGB, $word), (T 'ConfirmTitle'), '')
        if ($typed -cne $word) { [void][System.Windows.Forms.MessageBox]::Show((T 'ConfirmWrong'), 'Alchemist'); return }
        [void][System.Windows.Forms.MessageBox]::Show((T 'AdminNeeded'), 'Alchemist')
    }
    elseif (-not $Simulation) {
        $msg = (T 'ConfirmBuild') -f $letter, $selected.Count
        if ([System.Windows.Forms.MessageBox]::Show($msg, 'Alchemist', 'YesNo', 'Question') -ne 'Yes') { return }
    }

    $logDir = Join-Path $kitRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:LogPath = Join-Path $logDir ("assistant-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $script:LogPos = 0L
    $script:LogBox.Clear()

    $p = Get-SelectedProfile
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $kitRoot 'Build-Kit.ps1')),
        '-Profil', $p.Name, '-Only', ($selected -join ','), '-LogFile', ('"{0}"' -f $script:LogPath))
    if ($installVentoy) { $argList += @('-InstallerVentoy', '-Disque', $target.Number, '-ConfirmerEffacement', ("EFFACER-{0}" -f $target.Number)) }
    else { $argList += @('-DriveLetter', $letter) }
    if ($script:ChkUpdateVentoy.Checked -and -not $installVentoy) { $argList += '-MettreAJourVentoy' }
    if ($Simulation) { $argList += '-DryRun' }
    if ($script:LangCombo.SelectedIndex -ge 0 -and $script:LangCodes.Count -gt 0) { $argList += @('-Langue', $script:LangCodes[$script:LangCombo.SelectedIndex]) }
    if (-not $script:ChkSignature.Checked) { $argList += '-SansVerifSignature' }
    if ($script:ChkBackup.Checked) {
        $argList += @('-SauvegardeVers', ('"{0}"' -f $script:BackupPath.Text))
        if ($script:ChkBackupFull.Checked) { $argList += '-SauvegardeComplete' }
    }
    if ($script:IsoUrl.Text.Trim()) { $argList += @('-WindowsIsoUrl', ('"{0}"' -f $script:IsoUrl.Text.Trim())) }
    # Images personnelles : séparateur « | » (interdit dans un chemin Windows, contrairement à la virgule)
    if (@($script:PersonalIsos).Count -gt 0) { $argList += @('-IsoPersonnelle', ('"{0}"' -f ($script:PersonalIsos -join '|'))) }

    $hostExe = (Get-Process -Id $PID).Path
    $sp = @{ FilePath = $hostExe; ArgumentList = $argList; WindowStyle = 'Hidden'; PassThru = $true }
    # Ventoy (installation ou mise à jour) : droits administrateur requis
    if (($installVentoy -or $script:ChkUpdateVentoy.Checked) -and -not $Simulation -and -not (Test-KitAdmin)) { $sp['Verb'] = 'RunAs' }
    try { $script:Process = Start-Process @sp }
    catch {
        # Autorisation administrateur refusée (bouton « Non » de Windows) ou lancement impossible
        $script:Process = $null
        Add-LogLine -Line ('[ERROR] ' + $_.Exception.Message)
        $why = $(if ($sp.ContainsKey('Verb')) { T 'UacRefused' } else { (T 'LaunchFailed') -f $_.Exception.Message })
        [void][System.Windows.Forms.MessageBox]::Show($why, 'Alchemist', 'OK', 'Warning')
        return
    }
    Add-LogLine -Line ((T 'Starting') -f (($argList | Select-Object -Skip 5) -join ' '))
    Set-Running -Running $true
    $script:Timer.Start()
}

# --------------------------------------------------------------------------- fenêtre
$form = New-Object System.Windows.Forms.Form
$form.Text = (T 'WindowTitle')
$form.Size = New-Object System.Drawing.Size(1130, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1060, 720)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
Set-KitFormStyle -Form $form -Glyph 'Usb'
$theme = Get-KitUiTheme
$kitVersion = ''
if (Test-Path -LiteralPath (Join-Path $kitRoot 'VERSION')) { $kitVersion = (Get-Content -LiteralPath (Join-Path $kitRoot 'VERSION') -TotalCount 1).Trim() }
[void](Add-KitHeader -Form $form -Title (T 'Title') -Subtitle (T 'Intro') -Glyph 'Usb' -Version $kitVersion)

# Profil
# Étape 1 : système (Windows / Linux), étape 2 : usage (bureautique / développement)
$form.Controls.Add((New-Label -Text (T 'SystemLabel') -X 18 -Y 76 -W 155 -Bold))
$script:SystemCombo = New-Object System.Windows.Forms.ComboBox
$script:SystemCombo.DropDownStyle = 'DropDownList'
$script:SystemCombo.Location = New-Object System.Drawing.Point(175, 72); $script:SystemCombo.Size = New-Object System.Drawing.Size(140, 24)
$form.Controls.Add($script:SystemCombo)
$form.Controls.Add((New-Label -Text (T 'UsageLabel') -X 330 -Y 76 -W 70 -Bold))
$script:UsageCombo = New-Object System.Windows.Forms.ComboBox
$script:UsageCombo.DropDownStyle = 'DropDownList'
$script:UsageCombo.Location = New-Object System.Drawing.Point(400, 72); $script:UsageCombo.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($script:UsageCombo)
$script:ProfileDesc = New-Label -Text '' -X 585 -Y 70 -W 520 -H 36
$script:ProfileDesc.Anchor = 'Top,Left,Right'
$form.Controls.Add($script:ProfileDesc)

# Langue du système installé (ISO, Office, clavier) et langue de l'interface
$form.Controls.Add((New-Label -Text (T 'ContentLang') -X 18 -Y 114 -W 155 -Bold))
$script:LangCombo = New-Object System.Windows.Forms.ComboBox
$script:LangCombo.DropDownStyle = 'DropDownList'
$script:LangCombo.Location = New-Object System.Drawing.Point(175, 110); $script:LangCombo.Size = New-Object System.Drawing.Size(220, 24)
$form.Controls.Add($script:LangCombo)
$form.Controls.Add((New-Label -Text (T 'InterfaceLang') -X 420 -Y 114 -W 140))
$uiCombo = New-Object System.Windows.Forms.ComboBox
$uiCombo.DropDownStyle = 'DropDownList'
$uiCombo.Location = New-Object System.Drawing.Point(565, 110); $uiCombo.Size = New-Object System.Drawing.Size(140, 24)
$uiCodes = @(Get-ChildItem -LiteralPath $langDir -Filter '*.psd1' | Sort-Object Name | ForEach-Object BaseName)
foreach ($c in $uiCodes) { [void]$uiCombo.Items.Add((Import-PowerShellDataFile -Path (Join-Path $langDir "$c.psd1")).LangName) }
$uiCombo.SelectedIndex = [array]::IndexOf($uiCodes, $Interface)
$uiCombo.Add_SelectedIndexChanged({
        # Changement de langue : la fenêtre est recréée dans la nouvelle langue
        $new = $uiCodes[$uiCombo.SelectedIndex]
        if ($new -ne $Interface -and -not ($script:Process -and -not $script:Process.HasExited)) {
            $script:Restart = $new
            $form.Close()
        }
    })
$form.Controls.Add($uiCombo)

# Clé
$form.Controls.Add((New-Label -Text (T 'DriveLabel') -X 18 -Y 148 -W 155 -Bold))
$script:DriveCombo = New-Object System.Windows.Forms.ComboBox
$script:DriveCombo.DropDownStyle = 'DropDownList'
$script:DriveCombo.Location = New-Object System.Drawing.Point(175, 144); $script:DriveCombo.Size = New-Object System.Drawing.Size(520, 24)
$form.Controls.Add($script:DriveCombo)
$script:BtnRefresh = New-Object System.Windows.Forms.Button
$script:BtnRefresh.Text = (T 'Refresh'); $script:BtnRefresh.Location = New-Object System.Drawing.Point(705, 143); $script:BtnRefresh.Size = New-Object System.Drawing.Size(105, 28)
$script:BtnRefresh.Add_Click({ Update-DriveList })
$form.Controls.Add($script:BtnRefresh)
$lnkVentoy = New-Object System.Windows.Forms.LinkLabel
$lnkVentoy.Text = (T 'GetVentoy')
$lnkVentoy.Location = New-Object System.Drawing.Point(820, 114); $lnkVentoy.Size = New-Object System.Drawing.Size(290, 22)
$lnkVentoy.Add_LinkClicked({ Start-Process 'https://www.ventoy.net/fr/download.html' })
$form.Controls.Add($lnkVentoy)
$script:ChkInstallVentoy = New-Object System.Windows.Forms.CheckBox
$script:ChkInstallVentoy.Text = (T 'InstallVentoy')
$script:ChkInstallVentoy.Location = New-Object System.Drawing.Point(815, 138); $script:ChkInstallVentoy.Size = New-Object System.Drawing.Size(300, 22)
$script:ChkInstallVentoy.Add_CheckedChanged({ if ($script:ChkInstallVentoy.Checked) { $script:ChkUpdateVentoy.Checked = $false }; Update-DriveList })
$form.Controls.Add($script:ChkInstallVentoy)
$script:ChkUpdateVentoy = New-Object System.Windows.Forms.CheckBox
$script:ChkUpdateVentoy.Text = (T 'UpdateVentoy')
$script:ChkUpdateVentoy.Location = New-Object System.Drawing.Point(815, 158); $script:ChkUpdateVentoy.Size = New-Object System.Drawing.Size(300, 22)
$script:ChkUpdateVentoy.Add_CheckedChanged({ if ($script:ChkUpdateVentoy.Checked -and $script:ChkInstallVentoy.Checked) { $script:ChkInstallVentoy.Checked = $false } })
$form.Controls.Add($script:ChkUpdateVentoy)

# Liste des éléments
$script:ItemList = New-Object System.Windows.Forms.ListView
$script:ItemList.View = 'Details'; $script:ItemList.CheckBoxes = $true; $script:ItemList.FullRowSelect = $true
$script:ItemList.SmallImageList = New-KitStateImageList -Size 20
$script:ItemList.BorderStyle = 'FixedSingle'
$script:ItemList.Location = New-Object System.Drawing.Point(18, 182); $script:ItemList.Size = New-Object System.Drawing.Size(640, 330)
$script:ItemList.Anchor = 'Top,Left,Bottom'
[void]$script:ItemList.Columns.Add((T 'ColItem'), 185)
[void]$script:ItemList.Columns.Add((T 'ColSize'), 75)
[void]$script:ItemList.Columns.Add((T 'ColUsage'), 165)
[void]$script:ItemList.Columns.Add((T 'ColSource'), 95)
[void]$script:ItemList.Columns.Add((T 'ColWindows'), 85)
$script:ItemList.Add_ItemChecked({
        param($s, $e)
        [void]$s
        Update-Total
        # Conseil contextuel : compatibilité des logiciels avec le système coché
        if ($e.Item.Checked -and $e.Item.Tag -is [hashtable] -and $script:Hint) {
            if ($e.Item.Tag.Name -eq 'Windows10') { $script:Hint.Text = (T 'Win10Hint') }
            elseif ($e.Item.Tag.ContainsKey('Compat') -and @($e.Item.Tag.Compat) -contains '7') { $script:Hint.Text = (T 'Win7Hint') }
        }
    })
$form.Controls.Add($script:ItemList)

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = (T 'CheckAll'); $btnAll.Location = New-Object System.Drawing.Point(18, 518); $btnAll.Size = New-Object System.Drawing.Size(125, 28); $btnAll.Anchor = 'Bottom,Left'
$btnAll.Add_Click({ foreach ($i in $script:ItemList.Items) { $i.Checked = $true } })
$form.Controls.Add($btnAll)
$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = (T 'CheckNone'); $btnNone.Location = New-Object System.Drawing.Point(149, 518); $btnNone.Size = New-Object System.Drawing.Size(120, 28); $btnNone.Anchor = 'Bottom,Left'
$btnNone.Add_Click({ foreach ($i in $script:ItemList.Items) { $i.Checked = $false } })
$form.Controls.Add($btnNone)
$script:TotalLabel = New-Label -Text '' -X 278 -Y 523 -W 390
$script:TotalLabel.Anchor = 'Bottom,Left'
$form.Controls.Add($script:TotalLabel)
$script:Hint = New-Label -Text (T 'FreeSuiteHint') -X 18 -Y 548 -W 640
$script:Hint.ForeColor = $theme.Success
$script:Hint.Anchor = 'Bottom,Left'
$form.Controls.Add($script:Hint)

# Options
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = (T 'Options'); $grp.Location = New-Object System.Drawing.Point(672, 182); $grp.Size = New-Object System.Drawing.Size(430, 380)
$grp.Anchor = 'Top,Left,Right'
$form.Controls.Add($grp)
$script:ChkSignature = New-Object System.Windows.Forms.CheckBox
$script:ChkSignature.Text = (T 'VerifySig'); $script:ChkSignature.Checked = $true
$script:ChkSignature.Location = New-Object System.Drawing.Point(14, 26); $script:ChkSignature.Size = New-Object System.Drawing.Size(410, 22)
$grp.Controls.Add($script:ChkSignature)
$grp.Controls.Add((New-Label -Text (T 'VerifySigNote') -X 32 -Y 48 -W 390))
$script:ChkBackup = New-Object System.Windows.Forms.CheckBox
$script:ChkBackup.Text = (T 'Backup')
$script:ChkBackup.Location = New-Object System.Drawing.Point(14, 80); $script:ChkBackup.Size = New-Object System.Drawing.Size(410, 22)
$grp.Controls.Add($script:ChkBackup)
$script:BackupPath = New-Object System.Windows.Forms.TextBox
$script:BackupPath.Location = New-Object System.Drawing.Point(32, 104); $script:BackupPath.Size = New-Object System.Drawing.Size(280, 24)
$script:BackupPath.Text = [Environment]::GetFolderPath('MyDocuments')
$grp.Controls.Add($script:BackupPath)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = (T 'Browse'); $btnBrowse.Location = New-Object System.Drawing.Point(318, 102); $btnBrowse.Size = New-Object System.Drawing.Size(104, 28)
$btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = (T 'BackupDialog')
        if ($dlg.ShowDialog() -eq 'OK') { $script:BackupPath.Text = $dlg.SelectedPath; $script:ChkBackup.Checked = $true }
    })
$grp.Controls.Add($btnBrowse)
$script:ChkBackupFull = New-Object System.Windows.Forms.CheckBox
$script:ChkBackupFull.Text = (T 'BackupFull')
$script:ChkBackupFull.Location = New-Object System.Drawing.Point(32, 132); $script:ChkBackupFull.Size = New-Object System.Drawing.Size(390, 22)
$grp.Controls.Add($script:ChkBackupFull)
$grp.Controls.Add((New-Label -Text (T 'IsoUrlLabel') -X 14 -Y 170 -W 410 -H 36))
$script:IsoUrl = New-Object System.Windows.Forms.TextBox
$script:IsoUrl.Location = New-Object System.Drawing.Point(14, 208); $script:IsoUrl.Size = New-Object System.Drawing.Size(406, 24)
$grp.Controls.Add($script:IsoUrl)
$lnkIso = New-Object System.Windows.Forms.LinkLabel
$lnkIso.Text = (T 'IsoUrlLink')
$lnkIso.Location = New-Object System.Drawing.Point(14, 236); $lnkIso.Size = New-Object System.Drawing.Size(300, 22)
$lnkIso.Add_LinkClicked({ Start-Process 'https://www.microsoft.com/fr-fr/software-download/windows11' })
$grp.Controls.Add($lnkIso)
$grp.Controls.Add((New-Label -Text (T 'Tip') -X 14 -Y 260 -W 410 -H 36))

# Autres versions de Windows : Windows 10 (officiel, dans la liste) et images personnelles (Windows 7…)
$grp.Controls.Add((New-Label -Text (T 'OtherWindows') -X 14 -Y 300 -W 410))
$lnkWin10 = New-Object System.Windows.Forms.LinkLabel
$lnkWin10.Text = (T 'Win10Link')
$lnkWin10.Location = New-Object System.Drawing.Point(14, 322); $lnkWin10.Size = New-Object System.Drawing.Size(410, 20)
$lnkWin10.Add_LinkClicked({ Start-Process (T 'Win10Url') })
$grp.Controls.Add($lnkWin10)
$script:PersonalIsos = @()
$btnIsoPerso = New-Object System.Windows.Forms.Button
$btnIsoPerso.Text = (T 'IsoPerso'); $btnIsoPerso.Location = New-Object System.Drawing.Point(14, 344); $btnIsoPerso.Size = New-Object System.Drawing.Size(200, 28)
$btnIsoPerso.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = (T 'IsoPersoDialog'); $dlg.Multiselect = $true
        $dlg.Filter = 'Images (*.iso;*.img;*.wim;*.vhd;*.vhdx)|*.iso;*.img;*.wim;*.vhd;*.vhdx'
        if ($dlg.ShowDialog() -ne 'OK') { return }
        $script:PersonalIsos = @(@($script:PersonalIsos) + @($dlg.FileNames) | Select-Object -Unique)
        Update-PersonalIso
        # ISO de Windows 7 : on propose (coche) les logiciels compatibles
        if (@($dlg.FileNames | Where-Object { (Split-Path -Leaf $_) -match '(?i)(win(dows)?[ _.-]?7|\bw7\b|seven)' }).Count -gt 0) {
            $n = Set-Win7Pack
            $script:Hint.Text = (T 'Win7Hint')
            if ($n -gt 0) { [void][System.Windows.Forms.MessageBox]::Show(((T 'Win7PackChecked') -f $n), 'Alchemist', 'OK', 'Information') }
        }
    })
$grp.Controls.Add($btnIsoPerso)
$script:IsoPersoBox = New-Object System.Windows.Forms.TextBox
$script:IsoPersoBox.ReadOnly = $true
$script:IsoPersoBox.Location = New-Object System.Drawing.Point(220, 347); $script:IsoPersoBox.Size = New-Object System.Drawing.Size(168, 24)
$grp.Controls.Add($script:IsoPersoBox)
$script:BtnIsoPersoClear = New-Object System.Windows.Forms.Button
$script:BtnIsoPersoClear.Text = 'X'; $script:BtnIsoPersoClear.Enabled = $false
$script:BtnIsoPersoClear.Location = New-Object System.Drawing.Point(392, 345); $script:BtnIsoPersoClear.Size = New-Object System.Drawing.Size(28, 26)
$script:BtnIsoPersoClear.Add_Click({ $script:PersonalIsos = @(); Update-PersonalIso })
$grp.Controls.Add($script:BtnIsoPersoClear)

# Boutons d'action
$script:BtnSimulate = New-Object System.Windows.Forms.Button
$script:BtnSimulate.Text = (T 'Simulate'); $script:BtnSimulate.Location = New-Object System.Drawing.Point(18, 572); $script:BtnSimulate.Size = New-Object System.Drawing.Size(205, 36)
$script:BtnSimulate.Anchor = 'Bottom,Left'
$script:BtnSimulate.Add_Click({ Start-Build -Simulation $true })
$form.Controls.Add($script:BtnSimulate)
$script:BtnBuild = New-Object System.Windows.Forms.Button
$script:BtnBuild.Text = (T 'Build'); $script:BtnBuild.Location = New-Object System.Drawing.Point(231, 572); $script:BtnBuild.Size = New-Object System.Drawing.Size(240, 36)
$script:BtnBuild.Anchor = 'Bottom,Left'
$script:BtnBuild.Add_Click({ Start-Build -Simulation $false })
$form.Controls.Add($script:BtnBuild)
$script:BtnStop = New-Object System.Windows.Forms.Button
$script:BtnStop.Text = (T 'Stop'); $script:BtnStop.Enabled = $false; $script:BtnStop.Location = New-Object System.Drawing.Point(479, 572); $script:BtnStop.Size = New-Object System.Drawing.Size(105, 36)
$script:BtnStop.Anchor = 'Bottom,Left'
$script:BtnStop.Add_Click({
        if ($script:Process -and -not $script:Process.HasExited) {
            # Arrêt propre : un prochain lancement reprendra les téléchargements partiels
            & taskkill.exe /PID $script:Process.Id /T /F | Out-Null
            Add-LogLine -Line (T 'StopRequested')
        }
    })
$form.Controls.Add($script:BtnStop)
$btnLogs = New-Object System.Windows.Forms.Button
$btnLogs.Text = (T 'Logs'); $btnLogs.Location = New-Object System.Drawing.Point(592, 572); $btnLogs.Size = New-Object System.Drawing.Size(115, 36)
$btnLogs.Anchor = 'Bottom,Left'
$btnLogs.Add_Click({ $d = Join-Path $kitRoot 'logs'; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d | Out-Null }; Start-Process explorer.exe $d })
$form.Controls.Add($btnLogs)
$script:Progress = New-Object System.Windows.Forms.ProgressBar
$script:Progress.Location = New-Object System.Drawing.Point(717, 579); $script:Progress.Size = New-Object System.Drawing.Size(385, 22)
$script:Progress.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($script:Progress)

# Journal
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.ReadOnly = $true; $script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:LogBox.ForeColor = [System.Drawing.Color]::Gainsboro; $script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.Location = New-Object System.Drawing.Point(18, 614); $script:LogBox.Size = New-Object System.Drawing.Size(1084, 110)
$script:LogBox.Anchor = 'Bottom,Left,Right'; $script:LogBox.WordWrap = $false
$form.Controls.Add($script:LogBox)
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:Status = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:Status.Text = (T 'Ready')
[void]$statusStrip.Items.Add($script:Status)
$form.Controls.Add($statusStrip)

# Minuterie : suivi du journal et de la fin du processus
$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 700
$script:Timer.Add_Tick({
        Read-NewLogLine
        if ($script:Process -and $script:Process.HasExited) {
            $script:Timer.Stop()
            Read-NewLogLine
            # Processus élevé : le code de sortie peut être illisible, le journal fait alors foi
            $code = -1
            try { $code = $script:Process.ExitCode } catch { Write-Verbose 'Code de sortie indisponible.' }
            if ($code -eq -1) { $last = ((Get-Content -LiteralPath $script:LogPath -Tail 6 -ErrorAction SilentlyContinue) -join ' '); if ($last -match '0 ÉCHEC') { $code = 0 } }
            Set-Running -Running $false
            $texte = switch ($code) {
                0 { (T 'Done0') }
                1 { (T 'Done1') }
                3 { (T 'Done3') }
                default { (T 'DoneOther') -f $code }
            }
            $script:Status.Text = $texte
            Update-DriveList
            [void][System.Windows.Forms.MessageBox]::Show($texte, 'Alchemist', 'OK', $(if ($code -eq 0) { 'Information' } else { 'Warning' }))
        }
    })

$form.Add_FormClosing({
        param($s, $e)
        if ($script:Process -and -not $script:Process.HasExited) {
            $r = [System.Windows.Forms.MessageBox]::Show((T 'CloseRunning'), 'Alchemist', 'YesNoCancel', 'Question')
            if ($r -eq 'Cancel') { $e.Cancel = $true }
            elseif ($r -eq 'No') { & taskkill.exe /PID $script:Process.Id /T /F | Out-Null }
        }
        [void]$s
    })

# --------------------------------------------------------------------------- style des boutons
Set-KitButtonStyle -Button $script:BtnBuild -Kind Primary -Glyph 'Play'
Set-KitButtonStyle -Button $script:BtnSimulate -Kind Secondary -Glyph 'Search'
Set-KitButtonStyle -Button $script:BtnStop -Kind Danger -Glyph 'Stop'
Set-KitButtonStyle -Button $btnLogs -Kind Secondary -Glyph 'Folder'
Set-KitButtonStyle -Button $script:BtnRefresh -Kind Secondary -Glyph 'Refresh'
Set-KitButtonStyle -Button $btnBrowse -Kind Secondary -Glyph 'Folder'
Set-KitButtonStyle -Button $btnIsoPerso -Kind Secondary -Glyph 'Folder'
Set-KitButtonStyle -Button $btnAll -Kind Secondary -Glyph 'Check'
Set-KitButtonStyle -Button $btnNone -Kind Secondary
$grp.ForeColor = $theme.Accent
foreach ($c in $grp.Controls) { if ($c -is [System.Windows.Forms.Control]) { $c.ForeColor = $theme.Text } }

# --------------------------------------------------------------------------- chargement
$profileDir = Join-Path $kitRoot 'config\profils'
$script:Profiles = Get-KitProfileList -Directory $profileDir
$script:Systems = @($script:Profiles | ForEach-Object Systeme | Select-Object -Unique)
$script:Usages = @('Bureautique', 'Developpement')
foreach ($s in $script:Systems) { [void]$script:SystemCombo.Items.Add($s) }
foreach ($u in $script:Usages) { [void]$script:UsageCombo.Items.Add((T "Usage$u")) }
$script:SystemCombo.Add_SelectedIndexChanged({ Update-ItemList })
$script:UsageCombo.Add_SelectedIndexChanged({ Update-ItemList })
if ($script:Profiles.Count -gt 0) {
    # Système par défaut : celui de l'ordinateur (Windows ici) ; usage : bureautique
    $script:UsageCombo.SelectedIndex = 0
    $script:SystemCombo.SelectedIndex = [math]::Max(0, [array]::IndexOf($script:Systems, 'Windows'))
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Add-LogLine -Line (T 'NoWinget')
}

if ($TestSansAffichage) {
    Write-Output ("Fenêtre construite : {0} profil(s), {1} élément(s), {2} clé(s) Ventoy détectée(s)." -f $script:Profiles.Count, $script:ItemList.Items.Count, @(Find-KitVentoyDrive).Count)
    if ($Capture) {
        $form.Show(); [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($Capture, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $form.Hide()
    }
    $form.Dispose()
    return
}
[void]$form.ShowDialog()
$form.Dispose()
if ($script:Restart) {
    # Relance de l'assistant dans la langue choisie
    & $PSCommandPath -Interface $script:Restart
}
