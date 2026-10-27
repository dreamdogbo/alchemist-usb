#
# Budget.psm1 — Estimation de l'espace nécessaire et priorisation
#
# Principe (aucun dépassement possible) :
#   disponible = espace libre réel − marge
#   On parcourt les éléments par priorité croissante (1 d'abord, puis l'ordre du catalogue).
#   Besoin d'un élément = taille de la nouvelle version − octets déjà téléchargés (.part).
#   Si besoin <= disponible : ACCEPTÉ, disponible -= besoin, puis disponible += taille de
#   l'ancienne version gérée (elle sera supprimée juste après la mise en place de la nouvelle).
#   Sinon : IGNORÉ (et signalé).
#
Set-StrictMode -Version Latest

function New-KitPlan {
    <#
    .SYNOPSIS
        Crée l'objet « plan » d'un élément du catalogue (rempli ensuite par Download.psm1).
        Fonction pure : ne modifie rien sur le système.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire uniquement')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [int] $Index
    )
    $estimated = 0.0
    if ($Item.ContainsKey('EstimatedSizeMB')) { $estimated = [double]$Item.EstimatedSizeMB * 1MB }
    return [pscustomobject]@{
        Name         = [string]$Item.Name
        Item         = $Item
        Priority     = [int]$Item.Priority
        Index        = $Index
        Status       = 'INCONNU'     # A_TELECHARGER | A_JOUR | INTROUVABLE | EN_LIGNE | CACHE | ABSENT
        NewBytes     = $estimated
        SizeSource   = 'repli'       # HEAD | winget+HEAD | repli
        OldBytes     = 0.0
        PartialBytes = 0.0
        Version      = ''
        Detail       = ''
        Source       = $null         # données propres au type (URL, SHA256…)
        Decision     = ''            # ACCEPTÉ | IGNORÉ | À JOUR | ÉCHEC
    }
}

function Get-KitPlanNeed {
    <#
    .SYNOPSIS
        Octets supplémentaires à écrire pour un plan (0 s'il est à jour).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)] [pscustomobject] $Plan)
    if ($Plan.Status -in @('A_JOUR', 'INTROUVABLE', 'EN_LIGNE', 'ABSENT')) { return 0.0 }
    if ($Plan.Status -eq 'CACHE') { return 0.0 }   # déjà entièrement sur la clé (zone cache)
    $need = [double]$Plan.NewBytes - [double]$Plan.PartialBytes
    if ($need -lt 0) { $need = 0.0 }
    return $need
}

function Select-KitBudget {
    <#
    .SYNOPSIS
        Décide, par priorité, ce qui sera téléchargé, et ce qui est ignoré faute de place.
    .OUTPUTS
        Les plans triés par priorité, avec la propriété Decision renseignée.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plans,
        [Parameter(Mandatory)] [double] $FreeBytes,
        [Parameter(Mandatory)] [double] $MarginBytes
    )
    $available = $FreeBytes - $MarginBytes
    $sorted = @($Plans | Sort-Object -Property Priority, Index)
    foreach ($p in $sorted) {
        switch ($p.Status) {
            'A_JOUR'      { $p.Decision = 'À JOUR'; continue }
            'INTROUVABLE' { $p.Decision = 'ÉCHEC'; continue }
            'EN_LIGNE'    { $p.Decision = 'IGNORÉ'; continue }
            'ABSENT'      { $p.Decision = 'IGNORÉ'; continue }
            default {
                $need = Get-KitPlanNeed -Plan $p
                if ($need -le $available) {
                    $p.Decision = 'ACCEPTÉ'
                    $available = $available - $need + [double]$p.OldBytes
                }
                else {
                    $p.Decision = 'IGNORÉ'
                    $p.Detail = ("Place insuffisante : besoin {0}, disponible {1} (marge déduite)" -f
                        (Format-KitSize $need), (Format-KitSize ([math]::Max([double]0, $available))))
                }
            }
        }
    }
    return , $sorted
}

function Show-KitBudget {
    <#
    .SYNOPSIS
        Affiche le tableau du budget d'espace et les totaux.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plans,
        [Parameter(Mandatory)] [double] $FreeBytes,
        [Parameter(Mandatory)] [double] $MarginBytes
    )
    $rows = foreach ($p in $Plans) {
        [pscustomobject]@{
            Prio     = $p.Priority
            Element  = $p.Name
            Version  = $p.Version
            TailleMo = [math]::Round($p.NewBytes / 1MB, 0)
            Source   = $p.SizeSource
            BesoinMo = [math]::Round((Get-KitPlanNeed -Plan $p) / 1MB, 0)
            LibereMo = [math]::Round($p.OldBytes / 1MB, 0)
            Decision = $p.Decision
            Detail   = $p.Detail
        }
    }
    Write-KitTable -InputObject @($rows) -Title '================ BUDGET D''ESPACE ================'

    $accepted = @($Plans | Where-Object Decision -eq 'ACCEPTÉ')
    $need = 0.0; $freed = 0.0; $total = 0.0
    foreach ($p in $accepted) { $need += (Get-KitPlanNeed -Plan $p); $freed += $p.OldBytes }
    foreach ($p in $Plans) { if ($p.Decision -in @('ACCEPTÉ', 'À JOUR')) { $total += $p.NewBytes } }
    Write-KitLog -Message ("Espace libre réel         : {0}" -f (Format-KitSize $FreeBytes))
    Write-KitLog -Message ("Marge conservée           : {0}" -f (Format-KitSize $MarginBytes))
    Write-KitLog -Message ("À écrire (acceptés)       : {0}" -f (Format-KitSize $need))
    Write-KitLog -Message ("Libéré (anciennes versions): {0}" -f (Format-KitSize $freed))
    Write-KitLog -Message ("Contenu géré final estimé : {0}" -f (Format-KitSize $total))
    Write-KitLog -Message ("Libre estimé après        : {0}" -f (Format-KitSize ($FreeBytes - $need + $freed)))
    $ignored = @($Plans | Where-Object { $_.Decision -eq 'IGNORÉ' -and $_.Status -notin @('EN_LIGNE', 'ABSENT') })
    if ($ignored.Count -gt 0) {
        Write-KitLog -Level WARN -Message ("Ignorés faute de place : {0}" -f (($ignored | ForEach-Object Name) -join ', '))
    }
}

Export-ModuleMember -Function New-KitPlan, Get-KitPlanNeed, Select-KitBudget, Show-KitBudget
