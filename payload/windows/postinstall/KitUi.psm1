#
# KitUi.psm1 — Thème visuel commun aux fenêtres du kit (WinForms, sans dépendance externe)
#
# Icônes : glyphes de la police système « Segoe MDL2 Assets » (Windows 10/11), dessinés en
# bitmaps à la volée. Si la police est absente, une pastille de couleur est dessinée à la place.
#
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Palette inspirée de Windows 11 (Fluent)
$script:Theme = @{
    Accent     = [System.Drawing.Color]::FromArgb(0, 95, 184)
    AccentHot  = [System.Drawing.Color]::FromArgb(0, 120, 212)
    Header     = [System.Drawing.Color]::FromArgb(22, 35, 60)
    HeaderSub  = [System.Drawing.Color]::FromArgb(176, 196, 222)
    Back       = [System.Drawing.Color]::FromArgb(243, 245, 248)
    Card       = [System.Drawing.Color]::White
    Text       = [System.Drawing.Color]::FromArgb(32, 32, 32)
    Muted      = [System.Drawing.Color]::FromArgb(110, 110, 110)
    Border     = [System.Drawing.Color]::FromArgb(214, 219, 226)
    Success    = [System.Drawing.Color]::FromArgb(16, 124, 16)
    Warning    = [System.Drawing.Color]::FromArgb(178, 106, 0)
    Danger     = [System.Drawing.Color]::FromArgb(196, 43, 28)
    Tool       = [System.Drawing.Color]::FromArgb(92, 45, 145)
}

# Auteur du kit (affiché dans le bandeau des fenêtres)
$script:Author = 'dreamdogbo'
$script:AuthorUrl = 'https://github.com/dreamdogbo'

# Glyphes Segoe MDL2 Assets utilisés
$script:Glyphs = @{
    Usb      = [char]0xE88E
    Check    = [char]0xE73E
    Download = [char]0xE896
    Cloud    = [char]0xE753
    Warning  = [char]0xE7BA
    Repair   = [char]0xE90F
    Settings = [char]0xE713
    Play     = [char]0xE768
    Stop     = [char]0xE71A
    Folder   = [char]0xE8B7
    Refresh  = [char]0xE72C
    Search   = [char]0xE721
    Pc       = [char]0xE7F8
    Close    = [char]0xE8BB
    Globe    = [char]0xE774
    Package  = [char]0xE7B8
}

function Get-KitUiTheme {
    <#
    .SYNOPSIS
        Retourne la palette de couleurs du kit.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return $script:Theme
}

function New-KitGlyphBitmap {
    <#
    .SYNOPSIS
        Dessine un glyphe (Segoe MDL2 Assets) dans un bitmap transparent.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire')]
    [CmdletBinding()]
    [OutputType([System.Drawing.Bitmap])]
    param(
        [Parameter(Mandatory)] [string] $Glyph,
        [System.Drawing.Color] $Color = $script:Theme.Accent,
        [int] $Size = 20,
        [System.Drawing.Color] $Circle = [System.Drawing.Color]::Empty
    )
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $fg = $Color
        if (-not $Circle.IsEmpty) {
            $b = New-Object System.Drawing.SolidBrush($Circle)
            $g.FillEllipse($b, 0, 0, $Size - 1, $Size - 1); $b.Dispose()
            $fg = [System.Drawing.Color]::White
        }
        $key = $script:Glyphs[$Glyph]
        if (-not $key) { $key = $Glyph }
        $fontSize = [single]($Size * 0.55)
        if ($Circle.IsEmpty) { $fontSize = [single]($Size * 0.72) }
        $font = New-Object System.Drawing.Font('Segoe MDL2 Assets', $fontSize, [System.Drawing.GraphicsUnit]::Pixel)
        if ($font.Name -ne 'Segoe MDL2 Assets') {
            # Police absente : pastille de couleur
            $b = New-Object System.Drawing.SolidBrush($Color); $g.FillEllipse($b, 3, 3, $Size - 7, $Size - 7); $b.Dispose()
        }
        else {
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
            $brush = New-Object System.Drawing.SolidBrush($fg)
            $g.DrawString([string]$key, $font, $brush, (New-Object System.Drawing.RectangleF(0, 1, $Size, $Size)), $fmt)
            $brush.Dispose(); $fmt.Dispose()
        }
        $font.Dispose()
    }
    finally { $g.Dispose() }
    return $bmp
}

function New-KitAppIcon {
    <#
    .SYNOPSIS
        Icône de fenêtre : pastille bleue avec un glyphe blanc.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire')]
    [CmdletBinding()]
    [OutputType([System.Drawing.Icon])]
    param([string] $Glyph = 'Usb')
    $bmp = New-KitGlyphBitmap -Glyph $Glyph -Size 32 -Circle $script:Theme.Accent
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Add-KitHeader {
    <#
    .SYNOPSIS
        Ajoute le bandeau d'en-tête (icône, titre, sous-titre) en haut d'une fenêtre.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Forms.Panel])]
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.Form] $Form,
        [Parameter(Mandatory)] [string] $Title,
        [string] $Subtitle = '',
        [string] $Glyph = 'Usb',
        [int] $Height = 64,
        [string] $Version = ''
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'; $panel.Height = $Height; $panel.BackColor = $script:Theme.Header
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Image = New-KitGlyphBitmap -Glyph $Glyph -Size 40 -Circle $script:Theme.Accent
    $pic.Size = New-Object System.Drawing.Size(40, 40); $pic.Location = New-Object System.Drawing.Point(16, [int](($Height - 40) / 2))
    $panel.Controls.Add($pic)
    $t = New-Object System.Windows.Forms.Label
    $t.Text = $Title; $t.ForeColor = [System.Drawing.Color]::White; $t.AutoSize = $true
    $t.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $t.Location = New-Object System.Drawing.Point(66, 7)
    $panel.Controls.Add($t)
    $s = New-Object System.Windows.Forms.Label
    $s.Text = $Subtitle; $s.ForeColor = $script:Theme.HeaderSub; $s.AutoSize = $true
    $s.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $s.Location = New-Object System.Drawing.Point(68, 38)
    $panel.Controls.Add($s)

    # Signature de l'auteur, cliquable (en haut à droite du bandeau)
    $credit = New-Object System.Windows.Forms.LinkLabel
    $credit.Text = "by $($script:Author)  ·  github.com/$($script:Author)"
    if ($Version) { $credit.Text = "v$Version  ·  " + $credit.Text }
    $credit.AutoSize = $true
    $credit.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $credit.LinkColor = $script:Theme.HeaderSub; $credit.ActiveLinkColor = [System.Drawing.Color]::White
    $credit.VisitedLinkColor = $script:Theme.HeaderSub; $credit.LinkBehavior = 'HoverUnderline'
    $credit.Anchor = 'Top,Right'
    $credit.Add_LinkClicked({ Start-Process $script:AuthorUrl })
    $panel.Controls.Add($credit)
    $Form.Controls.Add($panel)
    # Position à droite, recalculée si la fenêtre change de taille
    $place = { $credit.Location = New-Object System.Drawing.Point(($panel.ClientSize.Width - $credit.PreferredWidth - 14), ($panel.Height - 22)) }.GetNewClosure()
    & $place
    $panel.Add_Resize($place)
    return $panel
}

function Set-KitButtonStyle {
    <#
    .SYNOPSIS
        Style moderne d'un bouton : Primary (bleu), Danger (rouge) ou Secondary (clair), avec icône.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Mise en forme d''un contrôle')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.Button] $Button,
        [ValidateSet('Primary', 'Secondary', 'Danger')] [string] $Kind = 'Secondary',
        [string] $Glyph = ''
    )
    $Button.FlatStyle = 'Flat'
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.FlatAppearance.BorderSize = 1
    switch ($Kind) {
        'Primary' {
            $Button.BackColor = $script:Theme.Accent; $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderColor = $script:Theme.Accent
            $Button.FlatAppearance.MouseOverBackColor = $script:Theme.AccentHot
            $Button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5)
            $iconColor = [System.Drawing.Color]::White
        }
        'Danger' {
            $Button.BackColor = [System.Drawing.Color]::White; $Button.ForeColor = $script:Theme.Danger
            $Button.FlatAppearance.BorderColor = $script:Theme.Danger
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(253, 231, 233)
            $iconColor = $script:Theme.Danger
        }
        default {
            $Button.BackColor = [System.Drawing.Color]::White; $Button.ForeColor = $script:Theme.Text
            $Button.FlatAppearance.BorderColor = $script:Theme.Border
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(229, 241, 251)
            $iconColor = $script:Theme.Accent
        }
    }
    if ($Glyph) {
        $Button.Image = New-KitGlyphBitmap -Glyph $Glyph -Color $iconColor -Size 18
        $Button.ImageAlign = 'MiddleLeft'; $Button.TextAlign = 'MiddleCenter'
        $Button.TextImageRelation = 'ImageBeforeText'
        $Button.Padding = New-Object System.Windows.Forms.Padding(6, 0, 4, 0)
    }
}

function New-KitStateImageList {
    <#
    .SYNOPSIS
        Liste d'icônes d'état pour les ListView (clés : ok, todo, online, missing, tool, system, office).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire')]
    [CmdletBinding()]
    [OutputType([System.Windows.Forms.ImageList])]
    param([int] $Size = 20)
    $il = New-Object System.Windows.Forms.ImageList
    $il.ImageSize = New-Object System.Drawing.Size($Size, $Size)
    $il.ColorDepth = 'Depth32Bit'
    $il.Images.Add('ok', (New-KitGlyphBitmap -Glyph 'Check' -Size $Size -Circle $script:Theme.Success))
    $il.Images.Add('todo', (New-KitGlyphBitmap -Glyph 'Download' -Size $Size -Circle $script:Theme.Accent))
    $il.Images.Add('online', (New-KitGlyphBitmap -Glyph 'Cloud' -Size $Size -Circle $script:Theme.Warning))
    $il.Images.Add('missing', (New-KitGlyphBitmap -Glyph 'Warning' -Size $Size -Circle $script:Theme.Danger))
    $il.Images.Add('tool', (New-KitGlyphBitmap -Glyph 'Repair' -Size $Size -Circle $script:Theme.Tool))
    $il.Images.Add('system', (New-KitGlyphBitmap -Glyph 'Pc' -Size $Size -Circle $script:Theme.Header))
    $il.Images.Add('package', (New-KitGlyphBitmap -Glyph 'Package' -Size $Size -Circle $script:Theme.Accent))
    return $il
}

function Set-KitFormStyle {
    <#
    .SYNOPSIS
        Fond, police et icône standard d'une fenêtre du kit.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Mise en forme d''un contrôle')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.Form] $Form,
        [string] $Glyph = 'Usb'
    )
    $Form.BackColor = $script:Theme.Back
    $Form.ForeColor = $script:Theme.Text
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Form.Icon = New-KitAppIcon -Glyph $Glyph
}

Export-ModuleMember -Function Get-KitUiTheme, New-KitGlyphBitmap, New-KitAppIcon, Add-KitHeader,
    Set-KitButtonStyle, New-KitStateImageList, Set-KitFormStyle
