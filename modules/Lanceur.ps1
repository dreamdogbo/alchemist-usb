<#
.SYNOPSIS
    Lanceur de l'assistant Alchemist (appelé par Creer-Cle.bat).

.DESCRIPTION
    Creer-Cle.bat démarre PowerShell sans console : sans ce lanceur, une erreur au démarrage
    (mode de langage restreint, fichier bloqué, erreur de syntaxe…) ne laisse AUCUNE trace et
    l'utilisateur relance plusieurs fois. Ce lanceur :
      - vérifie que PowerShell peut afficher une fenêtre (mode de langage complet, version 5.1+) ;
      - refuse un dossier temporaire d'archive (kit lancé depuis le ZIP sans extraction) ;
      - débloque les fichiers du kit (marque « téléchargé depuis Internet ») ;
      - n'ouvre qu'un seul assistant à la fois (double-clics répétés) ;
      - affiche un message clair et écrit logs\demarrage-*.log si l'assistant ne peut pas s'ouvrir.

.EXAMPLE
    Creer-Cle.bat -Console     (dépannage : erreurs affichées dans la console)
#>
[CmdletBinding()]
param(
    # Affiche les erreurs dans la console au lieu d'une boîte de dialogue (dépannage)
    [switch] $Console
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot
$fr = ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'fr')

function Show-LaunchError {
    <#
    .SYNOPSIS
        Écrit l'erreur dans logs\demarrage-*.log et l'affiche (boîte de dialogue, ou Bloc-notes
        quand PowerShell est en mode restreint et ne peut pas créer de fenêtre).
    #>
    param([string] $Message, [string] $Detail = '')
    $log = ''
    try {
        $logDir = Join-Path $kitRoot 'logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $log = Join-Path $logDir ('demarrage-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $lines = @(
            ('Alchemist : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
            ('PowerShell {0} ({1}), mode {2}, {3}' -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, $ExecutionContext.SessionState.LanguageMode, [Environment]::OSVersion.VersionString),
            ('Dossier du kit : {0}' -f $kitRoot), '', $Message, '', $Detail
        )
        [IO.File]::WriteAllLines($log, [string[]]$lines, (New-Object Text.UTF8Encoding($true)))
    }
    catch { $log = '' }
    $text = $Message
    if ($log) { $text += "`n`n" + $(if ($fr) { 'Détails : ' } else { 'Details: ' }) + $log }
    if ($Console) { Write-Host $text -ForegroundColor Red; if ($Detail) { Write-Host $Detail -ForegroundColor DarkGray }; return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($text, 'Alchemist', 'OK', 'Error')
    }
    catch {
        # Mode restreint : pas de fenêtre .NET possible, on ouvre le journal dans le Bloc-notes
        if ($log) { Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $log) }
    }
}

# --------------------------------------------------------------------------- contrôles
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Show-LaunchError -Message $(if ($fr) {
            "PowerShell fonctionne ici en mode restreint ($($ExecutionContext.SessionState.LanguageMode)) : stratégie de sécurité de l'entreprise (AppLocker, WDAC) ou antivirus.`n`nL'assistant ne peut pas s'ouvrir sur ce poste. Préparez la clé depuis un autre ordinateur, ou demandez à l'administrateur d'autoriser le dossier du kit."
        }
        else {
            "PowerShell runs in restricted mode here ($($ExecutionContext.SessionState.LanguageMode)): company security policy (AppLocker, WDAC) or antivirus.`n`nThe assistant cannot open on this computer. Prepare the key from another computer, or ask the administrator to allow the kit folder."
        })
    exit 1
}
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Show-LaunchError -Message $(if ($fr) { "PowerShell $($PSVersionTable.PSVersion) est trop ancien : Windows PowerShell 5.1 (Windows 10/11) est requis." } else { "PowerShell $($PSVersionTable.PSVersion) is too old: Windows PowerShell 5.1 (Windows 10/11) is required." })
    exit 1
}
# Kit ouvert depuis l'archive par Windows, 7-Zip ou WinRAR : dossier temporaire effacé à la fermeture
if ($kitRoot -match '\\(Temp\d+_[^\\]*\.zip|Rar\$[^\\]*|7z[A-Z0-9]+)\\') {
    Show-LaunchError -Message $(if ($fr) { "Le kit est lancé depuis l'archive ZIP (dossier temporaire : $kitRoot).`n`nFaites d'abord clic droit sur l'archive > « Extraire tout… », puis double-cliquez Creer-Cle.bat dans le dossier extrait." } else { "The kit runs from inside the ZIP archive (temporary folder: $kitRoot).`n`nRight-click the archive > « Extract All… » first, then double-click Creer-Cle.bat in the extracted folder." })
    exit 1
}

# Fichiers marqués « téléchargé depuis Internet » : bloqués par une stratégie RemoteSigned imposée
# par l'entreprise (qui l'emporte sur -ExecutionPolicy Bypass). Seuls les scripts du kit sont visés.
try {
    $dirs = @('modules', 'config', 'lang', 'payload') | ForEach-Object { Join-Path $kitRoot $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $files = @(Get-ChildItem -LiteralPath $kitRoot -File) + @(Get-ChildItem -LiteralPath $dirs -Recurse -File -ErrorAction SilentlyContinue)
    $files | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1', '.bat', '.json', '.xml') } | Unblock-File -ErrorAction SilentlyContinue
}
catch { Write-Verbose ('Déblocage des fichiers ignoré : {0}' -f $_.Exception.Message) }

# Un seul assistant à la fois : deux préparations simultanées de la même clé la rendraient incohérente
$mutex = New-Object System.Threading.Mutex($false, 'Local\Alchemist-Assistant')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    $msg = $(if ($fr) { "L'assistant Alchemist est déjà ouvert (regardez dans la barre des tâches).`n`nSa fenêtre peut mettre quelques secondes à apparaître." } else { "The Alchemist assistant is already open (check the taskbar).`n`nIts window may take a few seconds to appear." })
    if ($Console) { Write-Host $msg -ForegroundColor Yellow }
    else {
        try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($msg, 'Alchemist', 'OK', 'Information') } catch { Write-Verbose $msg }
    }
    $mutex.Dispose()
    exit 0
}

# --------------------------------------------------------------------------- assistant
$code = 0
try {
    & (Join-Path $kitRoot 'Assistant.ps1')
}
catch {
    $code = 1
    $e = $_
    $detail = ($e | Out-String) + "`n" + [string]$e.ScriptStackTrace
    Show-LaunchError -Message $(if ($fr) { "L'assistant n'a pas pu s'ouvrir :`n`n$($e.Exception.Message)" } else { "The assistant could not open:`n`n$($e.Exception.Message)" }) -Detail $detail
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
exit $code
