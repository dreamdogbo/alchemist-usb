#
# WebUi.psm1 — Serveur web local de l'assistant universel (web/alchemist.html), Windows et Linux
#
# Une même page sert à CRÉER la clé (Assistant-Web.ps1) et à INSTALLER le poste Windows
# (Assistant-Poste-Web.ps1) ; le poste Linux a l'équivalent en Python (assistant-poste.py).
# Compatible Windows PowerShell 5.1 et PowerShell 7 : TcpListener (aucun droit administrateur,
# aucune réservation d'URL), HTTP minimal, une requête à la fois.
#
# Sécurité : écoute sur 127.0.0.1 uniquement ; chaque appel à /api/ exige le jeton aléatoire
# de la session (transmis dans l'adresse, après #) ; l'en-tête Host doit être 127.0.0.1 ou
# localhost (aucune page web extérieure ne peut piloter l'assistant).
#
Set-StrictMode -Version Latest

$script:Job = $null

function Get-KitWebToken {
    <#
    .SYNOPSIS
        Jeton aléatoire de 32 caractères hexadécimaux (générateur cryptographique).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $bytes = New-Object byte[] 16
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Read-KitWebRequest {
    <#
    .SYNOPSIS
        Lit une requête HTTP (ligne, en-têtes, corps selon Content-Length) depuis le flux client.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [IO.Stream] $Stream)
    $buf = New-Object IO.MemoryStream
    $one = New-Object byte[] 1
    $end = 0
    # En-têtes : jusqu'à la ligne vide (\r\n\r\n), 64 Ko au plus
    while ($buf.Length -lt 65536) {
        $n = $Stream.Read($one, 0, 1)
        if ($n -le 0) { break }
        $buf.WriteByte($one[0])
        if (($end -eq 0 -or $end -eq 2) -and $one[0] -eq 13) { $end++ }
        elseif (($end -eq 1 -or $end -eq 3) -and $one[0] -eq 10) { $end++ }
        else { $end = 0 }
        if ($end -eq 4) { break }
    }
    $head = [Text.Encoding]::ASCII.GetString($buf.ToArray())
    $lines = $head -split "`r`n"
    if ($lines.Count -lt 1 -or $lines[0] -notmatch '^([A-Z]+) (\S+) HTTP/1\.[01]$') { return $null }
    $method = $Matches[1]; $target = $Matches[2]
    $headers = @{}
    foreach ($l in $lines[1..($lines.Count - 1)]) { if ($l -match '^([^:]+):\s*(.*)$') { $headers[$Matches[1].ToLowerInvariant()] = $Matches[2] } }
    $body = ''
    $len = 0
    if ($headers.ContainsKey('content-length')) { [void][int]::TryParse($headers['content-length'], [ref]$len) }
    if ($len -gt 0 -and $len -le 1048576) {
        $data = New-Object byte[] $len
        $read = 0
        while ($read -lt $len) {
            $n = $Stream.Read($data, $read, $len - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        $body = [Text.Encoding]::UTF8.GetString($data, 0, $read)
    }
    $path = $target; $query = @{}
    $q = $target.IndexOf('?')
    if ($q -ge 0) {
        $path = $target.Substring(0, $q)
        foreach ($pair in $target.Substring($q + 1).Split('&')) {
            $kv = $pair.Split('=', 2)
            if ($kv[0]) { $query[[uri]::UnescapeDataString($kv[0])] = $(if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } else { '' }) }
        }
    }
    return [pscustomobject]@{ Method = $method; Path = $path; Query = $query; Headers = $headers; Body = $body }
}

function Write-KitWebResponse {
    <#
    .SYNOPSIS
        Écrit une réponse HTTP complète (Connection: close).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [IO.Stream] $Stream,
        [int] $Status = 200,
        [string] $ContentType = 'application/json; charset=utf-8',
        [AllowEmptyString()] [string] $Body = ''
    )
    $reason = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 409 = 'Conflict'; 500 = 'Internal Server Error' }[$Status]
    if (-not $reason) { $reason = 'OK' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $head = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nReferrer-Policy: no-referrer`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if ($bytes.Length) { $Stream.Write($bytes, 0, $bytes.Length) }
    $Stream.Flush()
}

function Get-KitWebValue {
    <#
    .SYNOPSIS
        Champ d'un objet JSON reçu de la page, avec valeur par défaut s'il est absent (StrictMode).
        Chemin pointé accepté : « cle.mode ».
    #>
    [CmdletBinding()]
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Name, $Default = $null)
    $o = $Object
    foreach ($part in $Name.Split('.')) {
        if ($null -eq $o) { return $Default }
        $prop = $o.PSObject.Properties[$part]
        if (-not $prop -or $null -eq $prop.Value) { return $Default }
        $o = $prop.Value
    }
    return $o
}

function ConvertTo-KitWebJson {
    <#
    .SYNOPSIS
        Objet -> JSON (tableaux toujours sérialisés comme des tableaux, même à un élément).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $InputObject)
    if ($null -eq $InputObject) { return '{}' }
    return (ConvertTo-Json -InputObject $InputObject -Depth 8 -Compress)
}

function Open-KitBrowser {
    <#
    .SYNOPSIS
        Ouvre l'adresse dans le navigateur par défaut (Windows : association http ; Linux : xdg-open).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Url)
    try {
        if ($PSVersionTable.PSEdition -eq 'Desktop' -or [Environment]::OSVersion.Platform -eq 'Win32NT') { Start-Process -FilePath $Url }
        else {
            # Lancé par sudo : le navigateur est ouvert pour l'utilisateur du bureau, pas pour root
            if ((& id -u) -eq '0' -and $env:SUDO_USER) { Start-Process -FilePath 'sudo' -ArgumentList @('-u', $env:SUDO_USER, 'xdg-open', $Url) }
            else { Start-Process -FilePath 'xdg-open' -ArgumentList @($Url) }
        }
    }
    catch { Write-Warning ("Ouvrez cette adresse dans le navigateur : {0}" -f $Url) }
}

# --------------------------------------------------------------------------- tâche de fond (journal suivi)

function Start-KitWebJob {
    <#
    .SYNOPSIS
        Lance la tâche (moteur ou post-installation) dans un processus séparé, dont le journal est suivi.
    .PARAMETER LogPath
        Journal écrit par la tâche (-LogFile / -Journal) : lu au fil de l'eau, même en administrateur.
    .PARAMETER Elevate
        Windows : demande les droits administrateur (UAC). La sortie console n'est alors pas lisible :
        seul le journal fait foi.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [string] $LogPath,
        [switch] $Elevate
    )
    if ($script:Job -and $script:Job.Process -and -not $script:Job.Process.HasExited) { throw 'Une tâche est déjà en cours.' }
    if (-not $PSCmdlet.ShouldProcess($FilePath, 'Lancer')) { return }
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $err = "$LogPath.stderr"
    $out = "$LogPath.stdout"
    $sp = @{ FilePath = $FilePath; ArgumentList = $ArgumentList; PassThru = $true }
    $win = ($PSVersionTable.PSEdition -eq 'Desktop' -or [Environment]::OSVersion.Platform -eq 'Win32NT')
    if ($win) { $sp['WindowStyle'] = 'Hidden' }
    if ($Elevate) { $sp['Verb'] = 'RunAs' }
    else { $sp['RedirectStandardError'] = $err; $sp['RedirectStandardOutput'] = $out }
    $p = Start-Process @sp
    $script:Job = [pscustomobject]@{
        Process = $p; LogPath = $LogPath; ErrPath = $(if ($Elevate) { '' } else { $err }); OutPath = $(if ($Elevate) { '' } else { $out })
        Pos = 0L; Lines = (New-Object System.Collections.Generic.List[string]); Code = $null; Done = $false; Stopped = $false
    }
}

function Read-KitWebJob {
    <#
    .SYNOPSIS
        Lit les nouvelles lignes du journal de la tâche ; à la fin, ajoute ses erreurs console.
    #>
    [CmdletBinding()]
    param()
    $j = $script:Job
    if (-not $j -or $j.Done) { return }
    $exited = $j.Process.HasExited
    # Le journal peut être créé (ou renommé) un peu après le démarrage
    if (Test-Path -LiteralPath $j.LogPath) {
        $fs = $null
        try {
            $fs = New-Object IO.FileStream($j.LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            if ($fs.Length -gt $j.Pos) {
                [void]$fs.Seek($j.Pos, [IO.SeekOrigin]::Begin)
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                $text = $sr.ReadToEnd()
                # Dernière ligne incomplète : relue au prochain passage
                $cut = $text.LastIndexOf("`n")
                if ($cut -ge 0 -and -not $exited) { $text = $text.Substring(0, $cut + 1) }
                $j.Pos += [Text.Encoding]::UTF8.GetByteCount($text)
                foreach ($l in ($text -split "`r?`n")) { if ($l -ne '') { $j.Lines.Add($l.TrimStart([char]0xFEFF)) } }
            }
        }
        catch { Write-Verbose $_.Exception.Message }
        finally { if ($fs) { $fs.Dispose() } }
    }
    if ($exited) {
        foreach ($f in @($j.OutPath, $j.ErrPath)) {
            if ($f -and (Test-Path -LiteralPath $f)) {
                # Sortie console utile seulement si le journal n'a rien dit (erreur de démarrage)
                $extra = @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -notmatch '^\s*$' })
                if ($j.Lines.Count -eq 0 -or $f -eq $j.ErrPath) { foreach ($l in $extra) { $j.Lines.Add($l) } }
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            }
        }
        $code = $null
        try { $code = [int]$j.Process.ExitCode } catch { $code = $null }
        if ($j.Stopped) { $code = $null }
        $j.Code = $code
        $j.Done = $true
    }
}

function Get-KitWebJobState {
    <#
    .SYNOPSIS
        État de la tâche pour la page : lignes à partir de -From, actif, code de sortie.
    #>
    [CmdletBinding()]
    param([int] $From = 0)
    Read-KitWebJob
    $j = $script:Job
    if (-not $j) { return [ordered]@{ lignes = @(); suivant = 0; actif = $false; code = $null } }
    if ($From -lt 0 -or $From -gt $j.Lines.Count) { $From = 0 }
    $new = @()
    if ($From -lt $j.Lines.Count) { $new = @($j.Lines.GetRange($From, $j.Lines.Count - $From)) }
    return [ordered]@{ lignes = $new; suivant = $j.Lines.Count; actif = (-not $j.Done); code = $j.Code }
}

function Stop-KitWebJob {
    <#
    .SYNOPSIS
        Arrête la tâche en cours (processus et ses enfants).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $j = $script:Job
    if (-not $j -or $j.Process.HasExited) { return }
    if (-not $PSCmdlet.ShouldProcess($j.Process.Id, 'Arrêter')) { return }
    $j.Stopped = $true
    if ($PSVersionTable.PSEdition -eq 'Desktop' -or [Environment]::OSVersion.Platform -eq 'Win32NT') { & taskkill.exe /PID $j.Process.Id /T /F 2>&1 | Out-Null }
    else { try { $j.Process.Kill() } catch { throw "Arrêt impossible (tâche lancée en administrateur) : $($_.Exception.Message)" } }
}

function Test-KitWebJobActive {
    <#
    .SYNOPSIS
        Vrai si une tâche tourne encore.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]($script:Job -and -not $script:Job.Process.HasExited)
}

# --------------------------------------------------------------------------- serveur

function Invoke-KitWebUi {
    <#
    .SYNOPSIS
        Sert la page et l'API jusqu'à la fermeture de la page (aucun appel pendant IdleSec, sans tâche en cours).
    .PARAMETER Routes
        Hashtable « MÉTHODE /api/chemin » -> scriptblock param($Request) retournant un objet (JSON).
        Une exception devient une erreur 400 avec son message.
    .PARAMETER NoBrowser
        N'ouvre pas le navigateur (tests) ; l'adresse est écrite sur la sortie standard.
    .PARAMETER Port
        Port fixe (tests) ; 0 = port libre choisi par le système.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $HtmlPath,
        [Parameter(Mandatory)] [hashtable] $Routes,
        [int] $IdleSec = 180,
        [switch] $NoBrowser,
        [int] $Port = 0,
        [string] $Token = '',
        # Fichier où écrire l'adresse le temps de la session (le lanceur rouvre la page au lieu d'un 2e assistant)
        [string] $UrlFile = ''
    )
    if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "Page de l'assistant introuvable : $HtmlPath" }
    $html = [IO.File]::ReadAllText($HtmlPath, [Text.Encoding]::UTF8)
    if (-not $Token) { $Token = Get-KitWebToken }
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $Port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $url = "http://127.0.0.1:$Port/#$Token"
    $hosts = @("127.0.0.1:$Port", "localhost:$Port")
    Write-Output ("ALCHEMIST-URL {0}" -f $url)
    if ($UrlFile) { try { [IO.File]::WriteAllText($UrlFile, $url) } catch { Write-Verbose 'Adresse non mémorisée.' } }
    if (-not $NoBrowser) { Open-KitBrowser -Url $url }
    $lastCall = [DateTime]::UtcNow
    try {
        while ($true) {
            if (-not $listener.Pending()) {
                Start-Sleep -Milliseconds 60
                if (([DateTime]::UtcNow - $lastCall).TotalSeconds -gt $IdleSec -and -not (Test-KitWebJobActive)) { break }
                continue
            }
            $client = $listener.AcceptTcpClient()
            try {
                $client.ReceiveTimeout = 10000; $client.SendTimeout = 10000
                $stream = $client.GetStream()
                $req = Read-KitWebRequest -Stream $stream
                if (-not $req) { continue }
                $hostHeader = ''
                if ($req.Headers.ContainsKey('host')) { $hostHeader = $req.Headers['host'] }
                if ($hostHeader -notin $hosts) { Write-KitWebResponse -Stream $stream -Status 403 -Body '{"erreur":"hôte refusé"}'; continue }
                if ($req.Method -eq 'GET' -and ($req.Path -eq '/' -or $req.Path -eq '/index.html')) {
                    Write-KitWebResponse -Stream $stream -ContentType 'text/html; charset=utf-8' -Body $html
                    continue
                }
                if (-not $req.Path.StartsWith('/api/')) { Write-KitWebResponse -Stream $stream -Status 404 -Body '{"erreur":"introuvable"}'; continue }
                $given = ''
                if ($req.Headers.ContainsKey('x-alchemist-jeton')) { $given = $req.Headers['x-alchemist-jeton'] }
                if ($given -cne $Token) { Write-KitWebResponse -Stream $stream -Status 403 -Body '{"erreur":"jeton invalide : rouvrez l''assistant avec son lanceur"}'; continue }
                $lastCall = [DateTime]::UtcNow
                if ($req.Path -eq '/api/ping') { Write-KitWebResponse -Stream $stream -Body '{"ok":true}'; continue }
                if ($req.Path -eq '/api/journal') {
                    $from = 0; [void][int]::TryParse([string]$req.Query['depuis'], [ref]$from)
                    Write-KitWebResponse -Stream $stream -Body (ConvertTo-KitWebJson (Get-KitWebJobState -From $from)); continue
                }
                if ($req.Path -eq '/api/arreter' -and $req.Method -eq 'POST') { Stop-KitWebJob -Confirm:$false; Write-KitWebResponse -Stream $stream -Body '{"ok":true}'; continue }
                $key = "$($req.Method) $($req.Path)"
                if (-not $Routes.ContainsKey($key)) { Write-KitWebResponse -Stream $stream -Status 404 -Body '{"erreur":"introuvable"}'; continue }
                $data = $null
                if ($req.Body) { try { $data = $req.Body | ConvertFrom-Json } catch { Write-KitWebResponse -Stream $stream -Status 400 -Body '{"erreur":"JSON invalide"}'; continue } }
                try {
                    $result = & $Routes[$key] $data $req
                    Write-KitWebResponse -Stream $stream -Body (ConvertTo-KitWebJson $result)
                }
                catch { Write-KitWebResponse -Stream $stream -Status 400 -Body (ConvertTo-KitWebJson ([ordered]@{ erreur = $_.Exception.Message })) }
            }
            catch { Write-Verbose ("Requête abandonnée : {0}" -f $_.Exception.Message) }
            finally { $client.Close() }
        }
    }
    finally {
        $listener.Stop()
        if ($UrlFile) { Remove-Item -LiteralPath $UrlFile -Force -ErrorAction SilentlyContinue }
    }
}

Export-ModuleMember -Function Get-KitWebToken, Get-KitWebValue, Invoke-KitWebUi, Start-KitWebJob, Get-KitWebJobState, Stop-KitWebJob, Test-KitWebJobActive,
    Read-KitWebJob, Open-KitBrowser, ConvertTo-KitWebJson
