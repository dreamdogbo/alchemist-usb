<#
.SYNOPSIS
    Assistant graphique (fenêtre Windows) d'installation du poste depuis la clé.

.DESCRIPTION
    Ouvert par Lancer.bat. Affiche l'état de chaque logiciel du catalogue (déjà installé,
    sur la clé…), permet de cocher ce qu'il faut installer, de renommer le poste et
    d'appliquer les réglages recommandés, puis lance Install-Poste.ps1 en suivant son
    journal en direct. Donne aussi accès aux outils portables (SDIO pour les pilotes…).
    S'élève automatiquement en administrateur.

.EXAMPLE
    Double-clic sur Lancer.bat
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Fonctions internes d''interface graphique')]
[CmdletBinding()]
param(
    # Langue de l'interface (lang\<code>.psd1). Défaut : langue de Windows, sinon fr.
    [string] $Interface,
    # Construit la fenêtre sans l'afficher (test automatique)
    [switch] $TestSansAffichage,
    # Avec -TestSansAffichage : capture PNG de la fenêtre
    [string] $Capture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# --------------------------------------------------------------------------- élévation
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $TestSansAffichage -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Interface) { $a += @('-Interface', $Interface) }
    try { Start-Process -FilePath $ps51 -ArgumentList $a -Verb RunAs } catch { Write-Warning 'Droits administrateur refusés.' }
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
Import-Module (Join-Path $PSScriptRoot 'KitUi.psm1') -Force -DisableNameChecking

$here = $PSScriptRoot
$installScript = Join-Path $here 'Install-Poste.ps1'
$script:Process = $null
$script:LogPath = ''
$script:LogPos = 0L
$script:LogBox = $null
$script:Restart = $false
$script:RunKind = 'install'

# --------------------------------------------------------------------------- langue
$langDir = Join-Path $here 'lang'
if (-not $Interface) { $Interface = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }
if (-not (Test-Path -LiteralPath (Join-Path $langDir "$Interface.psd1"))) { $Interface = 'fr' }
$script:Lfr = Import-PowerShellDataFile -Path (Join-Path $langDir 'fr.psd1')
$script:L = Import-PowerShellDataFile -Path (Join-Path $langDir "$Interface.psd1")

function T {
    <#
    .SYNOPSIS
        Texte traduit (repli sur le français).
    #>
    param([string] $Key)
    if ($script:L.ContainsKey($Key)) { return $script:L[$Key] }
    if ($script:Lfr.ContainsKey($Key)) { return $script:Lfr[$Key] }
    return $Key
}

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
        Ajoute une ligne colorée au journal affiché.
    #>
    param([string] $Line)
    if (-not $script:LogBox) { return }
    $color = [System.Drawing.Color]::Gainsboro
    if ($Line -match '\[OK\s*\]') { $color = [System.Drawing.Color]::LightGreen }
    elseif ($Line -match '\[WARN\s*\]') { $color = [System.Drawing.Color]::Khaki }
    elseif ($Line -match '\[ERREUR\]|\[ERROR\s*\]') { $color = [System.Drawing.Color]::Salmon }
    elseif ($Line -match '\[ETAPE\]|\[STEP\s*\]') { $color = [System.Drawing.Color]::SkyBlue }
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.SelectionColor = $color
    $script:LogBox.AppendText($Line + [Environment]::NewLine)
    $script:LogBox.ScrollToCaret()
}

[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e); [void]$s; Add-LogLine -Line ('[ERREUR] ' + $e.Exception.Message) })

function Get-PosteEtat {
    <#
    .SYNOPSIS
        Interroge Install-Poste.ps1 -Etat (mêmes règles de détection que l'installation).
    #>
    $json = & $ps51 -NoProfile -ExecutionPolicy Bypass -File $installScript -Etat 2>$null | Out-String
    return ($json | ConvertFrom-Json)
}

function Read-NewLogLine {
    <#
    .SYNOPSIS
        Lecture incrémentale du journal d'installation.
    #>
    if (-not $script:LogPath -or -not (Test-Path -LiteralPath $script:LogPath)) { return }
    $fs = $null
    try {
        $fs = New-Object System.IO.FileStream($script:LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        if ($fs.Length -le $script:LogPos) { return }
        [void]$fs.Seek($script:LogPos, [IO.SeekOrigin]::Begin)
        $text = (New-Object System.IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd()
        $script:LogPos = $fs.Length
        foreach ($l in ($text -split "`r?`n")) { if ($l) { Add-LogLine -Line $l; $script:Status.Text = ($l -replace '^\S+\s+\[[^\]]+\]\s*', '') } }
    }
    catch { Write-Verbose $_.Exception.Message }
    finally { if ($fs) { $fs.Dispose() } }
}

function Update-List {
    <#
    .SYNOPSIS
        Remplit la liste à partir de l'état du poste.
    #>
    $script:Etat = Get-PosteEtat
    $script:ItemList.BeginUpdate()
    $script:ItemList.Items.Clear(); $script:ItemList.Groups.Clear()
    $groups = @{}
    foreach ($e in @($script:Etat.Items)) {
        $cat = [string]$e.Category
        if (-not $groups.ContainsKey($cat)) { $g = New-Object System.Windows.Forms.ListViewGroup($cat, $cat); [void]$script:ItemList.Groups.Add($g); $groups[$cat] = $g }
        $state = if ($e.Launcher) { T 'StTool' } elseif ($e.Installed) { T 'StInstalled' } elseif ($e.OnKey) { T 'StToInstall' } elseif ($e.WingetId -and $script:Etat.Internet) { T 'StOnline' } else { T 'StMissing' }
        $lvi = New-Object System.Windows.Forms.ListViewItem([string]$e.Name, $groups[$cat])
        [void]$lvi.SubItems.Add([string]$e.Version)
        [void]$lvi.SubItems.Add($state)
        $lvi.Tag = $e
        $lvi.ImageKey = $(if ($e.Launcher) { 'tool' } elseif ($e.Installed) { 'ok' } elseif ($e.OnKey) { 'todo' } elseif ($e.WingetId -and $script:Etat.Internet) { 'online' } else { 'missing' })
        # Coché par défaut : installable automatiquement, pas encore installé, disponible
        # Coché par défaut seulement s'il est sur la clé (les éléments en ligne restent au choix)
        $lvi.Checked = (-not $e.Launcher) -and (-not $e.Installed) -and ($e.Mode -ne 'Manuel') -and $e.OnKey
        if ($e.Installed) { $lvi.ForeColor = $theme.Muted }
        if ($e.Launcher) { $lvi.ForeColor = $theme.Tool }
        [void]$script:ItemList.Items.Add($lvi)
    }
    $script:ItemList.EndUpdate()
    $win = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
    $winText = if ($win) { "$($win.Caption) $($win.BuildNumber)" } else { '?' }
    $script:InfoLabel.Text = (T 'Computer') -f $env:COMPUTERNAME, $winText, $(if ($script:Etat.Internet) { T 'InternetYes' } else { T 'InternetNo' })
}

function Start-Tool {
    <#
    .SYNOPSIS
        Lance un outil portable depuis la clé.
    #>
    param($Entry)
    if (-not $Entry -or -not $Entry.Launcher) { [void][System.Windows.Forms.MessageBox]::Show((T 'SelectTool'), 'Alchemist'); return }
    if (-not (Test-Path -LiteralPath $Entry.Launcher)) { [void][System.Windows.Forms.MessageBox]::Show((T 'ToolMissing'), 'Alchemist'); return }
    Start-Process -FilePath $Entry.Launcher -WorkingDirectory (Split-Path -Parent $Entry.Launcher)
}

function Start-CompleteKey {
    <#
    .SYNOPSIS
        Télécharge sur la clé les éléments du catalogue qui y manquent (Internet requis),
        avec le kit présent à la racine de la clé (mêmes sources et vérifications).
    #>
    $keyRoot = Split-Path -Parent $here
    # Moteur présent sur la clé (dossier alchemist-usb, ou kit-ventoy pour les anciennes clés)
    $build = @(Get-ChildItem -LiteralPath $keyRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Build-Kit.ps1' } | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
    if (-not $build) { $build = '' }
    $missing = @($script:Etat.Items | Where-Object { -not $_.OnKey } | ForEach-Object Name)
    if (-not $script:Etat.Internet -or -not $build -or $missing.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'CompleteNone'), 'Alchemist'); return
    }
    if ([System.Windows.Forms.MessageBox]::Show(((T 'CompleteAsk') -f ($missing -join ', ')), 'Alchemist', 'YesNo', 'Question') -ne 'Yes') { return }
    $cat = Get-Content -LiteralPath (Join-Path $here 'catalogue.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $profilName = 'windows11-bureautique'
    if ($cat.PSObject.Properties['Profile'] -and $cat.Profile) { $profilName = [string]$cat.Profile }
    if (-not (Test-Path 'C:\PostInstall')) { New-Item -ItemType Directory 'C:\PostInstall' | Out-Null }
    $script:LogPath = Join-Path 'C:\PostInstall' ("completer-cle-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $script:LogPos = 0L
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $build), '-Profil', $profilName,
        '-DriveLetter', $keyRoot.Substring(0, 1), '-Only', ($missing -join ','), '-LogFile', ('"{0}"' -f $script:LogPath))
    $script:RunKind = 'complete'
    $script:Process = Start-Process -FilePath $ps51 -ArgumentList $a -WindowStyle Hidden -PassThru
    Set-Running -Running $true
    $script:Timer.Start()
}

function Set-Running {
    <#
    .SYNOPSIS
        Bascule l'interface pendant l'installation.
    #>
    param([bool] $Running)
    foreach ($c in @($script:BtnInstall, $script:ItemList, $script:NameBox, $script:ChkSettings)) { $c.Enabled = -not $Running }
    if ($Running) { $script:Progress.Style = 'Marquee' } else { $script:Progress.Style = 'Blocks' }
}

function Start-Install {
    <#
    .SYNOPSIS
        Lance Install-Poste.ps1 avec la sélection.
    #>
    $sel = @($script:ItemList.CheckedItems | ForEach-Object { $_.Text })
    if ($sel.Count -eq 0 -and -not $script:ChkSettings.Checked) { [void][System.Windows.Forms.MessageBox]::Show((T 'NothingChosen'), 'Alchemist'); return }
    $name = $script:NameBox.Text.Trim()
    if ($name -and $name -notmatch '^(?![0-9]+$)[A-Za-z0-9-]{1,15}$') { [void][System.Windows.Forms.MessageBox]::Show((T 'BadName'), 'Alchemist'); return }
    if ([System.Windows.Forms.MessageBox]::Show(((T 'ConfirmRun') -f $sel.Count), 'Alchemist', 'YesNo', 'Question') -ne 'Yes') { return }

    $logDir = 'C:\PostInstall'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $script:LogPath = Join-Path $logDir ("assistant-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $script:LogPos = 0L
    $list = '__aucun__'
    if ($sel.Count -gt 0) { $list = $sel -join ',' }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $installScript), '-Logiciels', $list, '-Journal', ('"{0}"' -f $script:LogPath))
    if (-not $script:ChkSettings.Checked) { $a += '-SansReglages' }
    if ($name) { $a += @('-NomPoste', $name) }
    $script:RunKind = 'install'
    $script:Process = Start-Process -FilePath $ps51 -ArgumentList $a -WindowStyle Hidden -PassThru
    Set-Running -Running $true
    $script:Timer.Start()
}

# --------------------------------------------------------------------------- fenêtre
$form = New-Object System.Windows.Forms.Form
$form.Text = (T 'WindowTitle')
$form.Size = New-Object System.Drawing.Size(1080, 760)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 700)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
Set-KitFormStyle -Form $form -Glyph 'Pc'
$theme = Get-KitUiTheme
$kitVersion = ''
if (Test-Path -LiteralPath (Join-Path $here 'VERSION')) { $kitVersion = (Get-Content -LiteralPath (Join-Path $here 'VERSION') -TotalCount 1).Trim() }
$header = Add-KitHeader -Form $form -Title (T 'Title') -Subtitle (T 'Intro') -Glyph 'Pc' -Version $kitVersion
$script:InfoLabel = New-Label -Text (T 'Loading') -X 18 -Y 70 -W 1000
$script:InfoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($script:InfoLabel)

$uiLabel = New-Label -Text (T 'InterfaceLang') -X 760 -Y 10 -W 140
$uiLabel.ForeColor = $theme.HeaderSub; $uiLabel.BackColor = $theme.Header; $uiLabel.Anchor = 'Top,Right'
$header.Controls.Add($uiLabel)
$uiCombo = New-Object System.Windows.Forms.ComboBox
$uiCombo.DropDownStyle = 'DropDownList'
$uiCombo.Location = New-Object System.Drawing.Point(905, 7); $uiCombo.Size = New-Object System.Drawing.Size(130, 24); $uiCombo.Anchor = 'Top,Right'
$uiCodes = @(Get-ChildItem -LiteralPath $langDir -Filter '*.psd1' | Sort-Object Name | ForEach-Object BaseName)
foreach ($c in $uiCodes) { [void]$uiCombo.Items.Add((Import-PowerShellDataFile -Path (Join-Path $langDir "$c.psd1")).LangName) }
$uiCombo.SelectedIndex = [array]::IndexOf($uiCodes, $Interface)
$uiCombo.Add_SelectedIndexChanged({
        $new = $uiCodes[$uiCombo.SelectedIndex]
        if ($new -ne $Interface -and -not ($script:Process -and -not $script:Process.HasExited)) { $script:Restart = $new; $form.Close() }
    })
$header.Controls.Add($uiCombo)

$script:ItemList = New-Object System.Windows.Forms.ListView
$script:ItemList.View = 'Details'; $script:ItemList.CheckBoxes = $true; $script:ItemList.FullRowSelect = $true
$script:ItemList.SmallImageList = New-KitStateImageList -Size 20
$script:ItemList.BorderStyle = 'FixedSingle'
$script:ItemList.Location = New-Object System.Drawing.Point(18, 96); $script:ItemList.Size = New-Object System.Drawing.Size(640, 360)
$script:ItemList.Anchor = 'Top,Left,Bottom'
[void]$script:ItemList.Columns.Add((T 'ColItem'), 190)
[void]$script:ItemList.Columns.Add((T 'ColVersion'), 130)
[void]$script:ItemList.Columns.Add((T 'ColState'), 290)
$script:ItemList.Add_DoubleClick({ $s = @($script:ItemList.SelectedItems); if ($s.Count -gt 0 -and $s[0].Tag.Launcher) { Start-Tool -Entry $s[0].Tag } })
$form.Controls.Add($script:ItemList)

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = (T 'CheckAll'); $btnAll.Location = New-Object System.Drawing.Point(18, 462); $btnAll.Size = New-Object System.Drawing.Size(125, 28); $btnAll.Anchor = 'Bottom,Left'
$btnAll.Add_Click({ foreach ($i in @($script:ItemList.Items)) { if ($i -and -not $i.Tag.Launcher) { $i.Checked = $true } } })
$form.Controls.Add($btnAll)
$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = (T 'CheckNone'); $btnNone.Location = New-Object System.Drawing.Point(149, 462); $btnNone.Size = New-Object System.Drawing.Size(125, 28); $btnNone.Anchor = 'Bottom,Left'
$btnNone.Add_Click({ foreach ($i in @($script:ItemList.Items)) { if ($i) { $i.Checked = $false } } })
$form.Controls.Add($btnNone)

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = (T 'Options'); $grp.Location = New-Object System.Drawing.Point(672, 96); $grp.Size = New-Object System.Drawing.Size(380, 260); $grp.Anchor = 'Top,Left,Right'
$form.Controls.Add($grp)
$grp.Controls.Add((New-Label -Text (T 'NewName') -X 14 -Y 26 -W 350))
$script:NameBox = New-Object System.Windows.Forms.TextBox
$script:NameBox.Location = New-Object System.Drawing.Point(14, 50); $script:NameBox.Size = New-Object System.Drawing.Size(200, 24); $script:NameBox.MaxLength = 15
$grp.Controls.Add($script:NameBox)
$grp.Controls.Add((New-Label -Text (T 'NameHint') -X 14 -Y 78 -W 350))
$script:ChkSettings = New-Object System.Windows.Forms.CheckBox
$script:ChkSettings.Text = (T 'Settings'); $script:ChkSettings.Checked = $true
$script:ChkSettings.Location = New-Object System.Drawing.Point(14, 112); $script:ChkSettings.Size = New-Object System.Drawing.Size(350, 22)
$grp.Controls.Add($script:ChkSettings)
$grp.Controls.Add((New-Label -Text (T 'SettingsList') -X 32 -Y 136 -W 336 -H 70))

$script:BtnInstall = New-Object System.Windows.Forms.Button
$script:BtnInstall.Text = (T 'Install'); $script:BtnInstall.Location = New-Object System.Drawing.Point(672, 366); $script:BtnInstall.Size = New-Object System.Drawing.Size(180, 40)
$script:BtnInstall.Add_Click({ Start-Install })
$form.Controls.Add($script:BtnInstall)
$btnTool = New-Object System.Windows.Forms.Button
$btnTool.Text = (T 'LaunchTool'); $btnTool.Location = New-Object System.Drawing.Point(862, 366); $btnTool.Size = New-Object System.Drawing.Size(190, 40)
$btnTool.Add_Click({ $s = @($script:ItemList.SelectedItems); $tag = $null; if ($s.Count -gt 0) { $tag = $s[0].Tag }; Start-Tool -Entry $tag })
$form.Controls.Add($btnTool)
$btnDrivers = New-Object System.Windows.Forms.Button
$btnDrivers.Text = (T 'Drivers'); $btnDrivers.Location = New-Object System.Drawing.Point(672, 414); $btnDrivers.Size = New-Object System.Drawing.Size(170, 32)
# Menu « Pilotes » : page officielle du fabricant détecté, SDIO (clé), composants, Windows Update
$driverMenu = New-Object System.Windows.Forms.ContextMenuStrip
$pilotes = Get-Content -LiteralPath (Join-Path $here 'pilotes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$maker = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer
$fab = @($pilotes.Fabricants | Where-Object { $maker -match $_.Motif }) | Select-Object -First 1
if ($fab) {
    $mi = $driverMenu.Items.Add(("{0} {1}  ({2})" -f (T 'DrvMaker'), $fab.Nom, $fab.Outil))
    $mi.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $url = $fab.Url; $mi.Add_Click({ Start-Process $url }.GetNewClosure())
}
$sdioItem = $driverMenu.Items.Add((T 'DrvSdio'))
$sdioItem.Add_Click({ Start-Tool -Entry (@($script:Etat.Items | Where-Object { $_.Name -eq 'SDIO' }) | Select-Object -First 1) })
$winItem = $driverMenu.Items.Add($pilotes.Windows.Nom)
$winUrl = $pilotes.Windows.Url; $winItem.Add_Click({ Start-Process $winUrl }.GetNewClosure())
[void]$driverMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
foreach ($c in @($pilotes.Composants) + @($pilotes.Fabricants | Where-Object { $_ -ne $fab })) {
    $it = $driverMenu.Items.Add($c.Nom); $u = $c.Url; $it.Add_Click({ Start-Process $u }.GetNewClosure())
}
$btnDrivers.Add_Click({ $driverMenu.Show($btnDrivers, 0, $btnDrivers.Height) })
$form.Controls.Add($btnDrivers)
$btnLogs = New-Object System.Windows.Forms.Button
$btnLogs.Text = (T 'Logs'); $btnLogs.Location = New-Object System.Drawing.Point(850, 414); $btnLogs.Size = New-Object System.Drawing.Size(108, 32)
$btnLogs.Add_Click({ if (-not (Test-Path 'C:\PostInstall')) { New-Item -ItemType Directory 'C:\PostInstall' | Out-Null }; Start-Process explorer.exe 'C:\PostInstall' })
$form.Controls.Add($btnLogs)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = (T 'Close'); $btnClose.Location = New-Object System.Drawing.Point(964, 414); $btnClose.Size = New-Object System.Drawing.Size(88, 32)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)
$btnComplete = New-Object System.Windows.Forms.Button
$btnComplete.Text = (T 'CompleteKey'); $btnComplete.Location = New-Object System.Drawing.Point(672, 452); $btnComplete.Size = New-Object System.Drawing.Size(220, 32)
$btnComplete.Add_Click({ Start-CompleteKey })
$form.Controls.Add($btnComplete)
$script:Progress = New-Object System.Windows.Forms.ProgressBar
$script:Progress.Location = New-Object System.Drawing.Point(902, 458); $script:Progress.Size = New-Object System.Drawing.Size(150, 22); $script:Progress.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($script:Progress)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.ReadOnly = $true; $script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:LogBox.ForeColor = [System.Drawing.Color]::Gainsboro; $script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.Location = New-Object System.Drawing.Point(18, 496); $script:LogBox.Size = New-Object System.Drawing.Size(1034, 190)
$script:LogBox.Anchor = 'Bottom,Left,Right'; $script:LogBox.WordWrap = $false
$form.Controls.Add($script:LogBox)
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:Status = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:Status.Text = (T 'Ready')
[void]$statusStrip.Items.Add($script:Status)
$form.Controls.Add($statusStrip)

$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 800
$script:Timer.Add_Tick({
        Read-NewLogLine
        if ($script:Process -and $script:Process.HasExited) {
            $script:Timer.Stop(); Read-NewLogLine
            Set-Running -Running $false
            $code = $script:Process.ExitCode
            $msg = if ($script:RunKind -eq 'complete') { (T 'CompleteDone') -f $code } elseif ($code -eq 0) { T 'Done0' } else { (T 'DoneFail') -f $code }
            $script:Status.Text = $msg
            Update-List
            [void][System.Windows.Forms.MessageBox]::Show($msg, 'Alchemist', 'OK', $(if ($code -eq 0) { 'Information' } else { 'Warning' }))
        }
    })
$form.Add_FormClosing({
        param($s, $e)
        [void]$s
        if ($script:Process -and -not $script:Process.HasExited) {
            if ([System.Windows.Forms.MessageBox]::Show((T 'CloseRunning'), 'Alchemist', 'YesNo', 'Question') -ne 'Yes') { $e.Cancel = $true }
        }
    })

Set-KitButtonStyle -Button $script:BtnInstall -Kind Primary -Glyph 'Download'
Set-KitButtonStyle -Button $btnTool -Kind Secondary -Glyph 'Repair'
Set-KitButtonStyle -Button $btnDrivers -Kind Secondary -Glyph 'Settings'
Set-KitButtonStyle -Button $btnLogs -Kind Secondary -Glyph 'Folder'
Set-KitButtonStyle -Button $btnClose -Kind Secondary -Glyph 'Close'
Set-KitButtonStyle -Button $btnComplete -Kind Secondary -Glyph 'Cloud'
Set-KitButtonStyle -Button $btnAll -Kind Secondary -Glyph 'Check'
Set-KitButtonStyle -Button $btnNone -Kind Secondary
$grp.ForeColor = $theme.Accent
foreach ($c in $grp.Controls) { $c.ForeColor = $theme.Text }

Update-List

if ($TestSansAffichage) {
    Write-Output ("Fenêtre poste construite : {0} élément(s), Internet={1}" -f $script:ItemList.Items.Count, $script:Etat.Internet)
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
if ($script:Restart) { & $PSCommandPath -Interface $script:Restart }
