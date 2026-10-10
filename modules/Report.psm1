#
# Report.psm1 — Journalisation horodatée et rapport final OK / ÉCHEC / IGNORÉ
#
Set-StrictMode -Version Latest

$script:LogFile = $null
$script:Results = New-Object System.Collections.Generic.List[object]

function Initialize-KitLog {
    <#
    .SYNOPSIS
        Crée le fichier journal horodaté dans le dossier logs/ et retourne son chemin.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $LogDirectory,
        [string] $Prefix = 'build',
        [string] $LogFile = ''
    )
    if ($LogFile) { $LogDirectory = Split-Path -Parent $LogFile }
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:LogFile = $LogFile
    if (-not $script:LogFile) { $script:LogFile = Join-Path $LogDirectory ("{0}-{1}.log" -f $Prefix, $stamp) }
    $script:Results.Clear()
    Write-KitLog -Message ("Journal : {0}" -f $script:LogFile)
    return $script:LogFile
}

function Write-KitLog {
    <#
    .SYNOPSIS
        Écrit une ligne horodatée à l'écran (couleur selon le niveau) et dans le journal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')] [string] $Level = 'INFO'
    )
    $line = "{0} [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'STEP'  { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Host "Impossible d'écrire dans le journal : $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Add-KitResult {
    <#
    .SYNOPSIS
        Enregistre le résultat d'un élément pour le rapport final.
    .PARAMETER Status
        OK, ÉCHEC ou IGNORÉ (les trois seuls statuts du rapport).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('OK', 'ÉCHEC', 'IGNORÉ')] [string] $Status,
        [string] $Detail = '',
        [double] $SizeMB = 0
    )
    # Un élément n'a qu'une ligne : la dernière information remplace la précédente
    $existing = @($script:Results | Where-Object { $_.Nom -eq $Name })
    foreach ($e in $existing) { [void]$script:Results.Remove($e) }
    $script:Results.Add([pscustomobject]@{
        Nom    = $Name
        Statut = $Status
        TailleMo = [math]::Round($SizeMB, 0)
        Detail = $Detail
    })
    $level = switch ($Status) { 'OK' { 'OK' } 'ÉCHEC' { 'ERROR' } default { 'WARN' } }
    Write-KitLog -Level $level -Message ("{0} : {1} {2}" -f $Name, $Status, $Detail)
}

function Get-KitResult {
    <#
    .SYNOPSIS
        Retourne la liste des résultats enregistrés.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return , $script:Results.ToArray()
}

function Format-KitSize {
    <#
    .SYNOPSIS
        Formate un nombre d'octets en Go/Mo lisible.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double] $Bytes)
    if ([math]::Abs($Bytes) -ge 1GB) { return ('{0:N2} Go' -f ($Bytes / 1GB)) }
    return ('{0:N0} Mo' -f ($Bytes / 1MB))
}

function Write-KitTable {
    <#
    .SYNOPSIS
        Écrit un tableau d'objets à l'écran et dans le journal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $InputObject,
        [string] $Title = ''
    )
    if ($Title) { Write-KitLog -Level STEP -Message $Title }
    if ($InputObject.Count -eq 0) { Write-KitLog -Message '(vide)'; return }
    $text = ($InputObject | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()
    foreach ($l in ($text -split "`r?`n")) { Write-KitLog -Message $l }
}

function Show-KitReport {
    <#
    .SYNOPSIS
        Affiche le rapport final, l'espace avant/après, et retourne le code de sortie :
        0 = tout est OK (ou ignoré faute de place), 1 = au moins un ÉCHEC.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [double] $FreeBeforeBytes = -1,
        [double] $FreeAfterBytes = -1,
        [switch] $DryRun
    )
    $rows = @($script:Results.ToArray())
    Write-KitLog -Level STEP -Message '================ RAPPORT FINAL ================'
    if ($DryRun) { Write-KitLog -Level WARN -Message 'Mode DryRun : aucune modification n''a été faite sur la clé.' }
    Write-KitTable -InputObject $rows

    $ok = @($rows | Where-Object Statut -eq 'OK').Count
    $ko = @($rows | Where-Object Statut -eq 'ÉCHEC').Count
    $ig = @($rows | Where-Object Statut -eq 'IGNORÉ').Count
    Write-KitLog -Message ("Bilan : {0} OK, {1} ÉCHEC, {2} IGNORÉ" -f $ok, $ko, $ig)
    if ($FreeBeforeBytes -ge 0) { Write-KitLog -Message ("Espace libre AVANT : {0}" -f (Format-KitSize $FreeBeforeBytes)) }
    if ($FreeAfterBytes -ge 0) { Write-KitLog -Message ("Espace libre APRÈS : {0}" -f (Format-KitSize $FreeAfterBytes)) }
    if ($script:LogFile) { Write-KitLog -Message ("Journal complet : {0}" -f $script:LogFile) }

    if ($ko -gt 0) { return 1 }
    return 0
}

Export-ModuleMember -Function Initialize-KitLog, Write-KitLog, Add-KitResult, Get-KitResult,
    Format-KitSize, Write-KitTable, Show-KitReport
