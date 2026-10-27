#
# Download.psm1 — Résolution des sources officielles, téléchargement (reprise + 3 tentatives),
#                  vérifications (SHA256, Authenticode, ISO), winget download, Fido, ODT.
#
# Les téléchargements se font dans la zone cache\<Nom>\ (sur le même volume que la clé,
# donc le passage vers l'emplacement final est un simple déplacement, sans copie).
# Un élément est considéré comme « complet en cache » quand son fichier <Nom>.source.json
# y a été écrit (c'est toujours la dernière étape d'un téléchargement réussi).
#
Set-StrictMode -Version Latest

$script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) alchemist/1.2'
$script:MaxAttempts = 3
$script:SkipSignature = $false
# Agent « honnête » pour les sites qui bloquent les robots se présentant comme un navigateur (Fedora…)
$script:PlainAgent = 'alchemist/1.2 (+https://github.com/dreamdogbo/alchemist-usb)'

function Set-KitSignaturePolicy {
    <#
    .SYNOPSIS
        Active ou désactive la vérification Authenticode (les SHA256 publiés restent vérifiés).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([switch] $Disabled)
    if ($PSCmdlet.ShouldProcess('Vérification des signatures', $(if ($Disabled) { 'Désactiver' } else { 'Activer' }))) {
        $script:SkipSignature = [bool]$Disabled
    }
}

function Get-KitGitHubRelease {
    <#
    .SYNOPSIS
        Dernière release STABLE (ni brouillon ni pré-version) d'un dépôt GitHub et l'asset voulu.
    .DESCRIPTION
        Utilise l'API publique GitHub (jeton facultatif via $env:GITHUB_TOKEN pour éviter la
        limite de 60 requêtes/heure). L'empreinte SHA256 publiée par GitHub (« digest ») sert
        de référence d'intégrité.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Repo,
        [Parameter(Mandatory)] [string] $AssetPattern
    )
    $headers = @{ 'User-Agent' = $script:UserAgent; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    $last = ''
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -UseBasicParsing -TimeoutSec 30
            if ($rel.draft -or $rel.prerelease) { throw "la dernière release de $Repo n'est pas stable" }
            $asset = @($rel.assets | Where-Object { $_.name -match $AssetPattern }) | Select-Object -First 1
            if (-not $asset) { throw "aucun fichier ne correspond à « $AssetPattern » dans $Repo $($rel.tag_name)" }
            $sha = ''
            $digest = $asset.PSObject.Properties['digest']
            if ($digest -and [string]$digest.Value -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1].ToLowerInvariant() }
            return [pscustomobject]@{
                Version  = ([string]$rel.tag_name).TrimStart('v')
                Url      = $asset.browser_download_url
                FileName = $asset.name
                Length   = [double]$asset.size
                Sha256   = $sha
            }
        }
        catch {
            $last = $_.Exception.Message
            # Limite de l'API GitHub atteinte (403/429) : repli immédiat sur les pages publiques
            if ($last -match '403|429|rate limit') { break }
            if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (3 * $attempt) }
        }
    }
    # Repli sans API : étiquette via /releases/latest, fichiers via la page des assets (pas de SHA256
    # publié dans ce cas : la signature de l'éditeur devient obligatoire en aval)
    try {
        $ri = Get-KitRemoteInfo -Url "https://github.com/$Repo/releases/latest" -Agent $script:PlainAgent
        if ($ri.FinalUrl -match '/releases/tag/([^/?#]+)') {
            $tag = [uri]::UnescapeDataString($Matches[1])
            $html = Get-KitText -Url "https://github.com/$Repo/releases/expanded_assets/$tag"
            foreach ($m in [regex]::Matches($html, 'href="(/[^"]+/releases/download/[^"]+)"')) {
                $path = $m.Groups[1].Value
                $name = [uri]::UnescapeDataString(($path -split '/')[-1])
                if ($name -match $AssetPattern) {
                    $url = 'https://github.com' + $path
                    $len = -1.0
                    try { $len = (Get-KitRemoteInfo -Url $url -Agent $script:PlainAgent).Length } catch { Write-Verbose 'Taille inconnue.' }
                    Write-KitLog -Level WARN -Message "GitHub $Repo : API indisponible ($last), repli sur la page publique des releases."
                    return [pscustomobject]@{ Version = $tag.TrimStart('v'); Url = $url; FileName = $name; Length = $len; Sha256 = '' }
                }
            }
        }
    }
    catch { $last = "$last ; repli : $($_.Exception.Message)" }
    throw "GitHub $Repo : $last"
}

function Get-KitText {
    <#
    .SYNOPSIS
        Télécharge une petite ressource texte (liste d'empreintes, index de répertoire), 3 tentatives.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Url)
    $last = ''
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        $wc = New-Object System.Net.WebClient
        try {
            $wc.Headers['User-Agent'] = $script:PlainAgent
            $wc.Encoding = [Text.Encoding]::UTF8
            return $wc.DownloadString($Url)
        }
        catch { $last = $_.Exception.Message; if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (2 * $attempt) } }
        finally { $wc.Dispose() }
    }
    throw "Ressource injoignable : $Url ($last)"
}

function Find-KitChecksum {
    <#
    .SYNOPSIS
        Cherche dans une liste d'empreintes officielle (formats GNU « hash  nom » / « hash *nom »
        et BSD « SHA256 (nom) = hash ») le fichier correspondant au motif.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Pattern
    )
    foreach ($line in ($Text -split "`r?`n")) {
        $name = $null; $hash = $null
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$') { $hash = $Matches[1]; $name = $Matches[2] }
        elseif ($line -match '^SHA256 \((.+)\) = ([0-9a-fA-F]{64})\s*$') { $name = $Matches[1]; $hash = $Matches[2] }
        if ($name -and $name -match $Pattern) { return [pscustomobject]@{ FileName = $name; Sha256 = $hash.ToLowerInvariant() } }
    }
    return $null
}

function Get-KitLatestDir {
    <#
    .SYNOPSIS
        Dans un index de répertoire HTTP, retourne le sous-dossier de version la plus élevée.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $IndexUrl,
        [string] $Pattern = '^\d+(\.\d+)*$'
    )
    $html = Get-KitText -Url $IndexUrl
    $dirs = @([regex]::Matches($html, 'href="([^"/?]+)/"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match $Pattern })
    if ($dirs.Count -eq 0) { throw "Aucune version trouvée dans $IndexUrl" }
    return ($dirs | Sort-Object { [version]($(if ($_ -match '\.') { $_ } else { "$_.0" })) } | Select-Object -Last 1)
}

function Resolve-KitLinuxIso {
    <#
    .SYNOPSIS
        Dernière version STABLE d'une distribution Linux depuis son site officiel, avec le SHA256
        publié dans sa liste d'empreintes officielle.
    .DESCRIPTION
        Distributions prises en charge (champ Distro du profil) :
          Ubuntu  : dernière LTS supportée (changelogs.ubuntu.com/meta-release-lts), édition Desktop
          Debian  : « current-live » GNOME (cdimage.debian.org)
          Mint    : dernière version stable Cinnamon (miroir officiel mirrors.kernel.org)
          Fedora  : dernière version Workstation (dl.fedoraproject.org)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [hashtable] $Item)
    switch ($Item.Distro) {
        'Ubuntu' {
            if ($Item.ContainsKey('Series') -and $Item.Series) {
                # Version LTS imposée par le profil (ex. 24.04)
                $series = [string]$Item.Series
            }
            else {
                # Dernière LTS supportée, d'après le fichier officiel d'Ubuntu
                $meta = Get-KitText -Url 'https://changelogs.ubuntu.com/meta-release-lts'
                $block = @($meta -split "`r?`n`r?`n" | Where-Object { $_ -match 'Supported: 1' }) | Select-Object -Last 1
                if (-not $block -or $block -notmatch 'Version:\s*(\d+\.\d+)') { throw 'Version LTS Ubuntu introuvable.' }
                $series = $Matches[1]
            }
            $base = "https://releases.ubuntu.com/$series/"
            $sums = Get-KitText -Url ($base + 'SHA256SUMS')
            $hit = Find-KitChecksum -Text $sums -Pattern '^ubuntu-[\d.]+-desktop-amd64\.iso$'
            $label = 'Ubuntu {0} LTS'
        }
        'Debian' {
            $base = 'https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/'
            $hit = Find-KitChecksum -Text (Get-KitText -Url ($base + 'SHA256SUMS')) -Pattern '^debian-live-[\d.]+-amd64-gnome\.iso$'
            $label = 'Debian {0} (GNOME)'
        }
        'Mint' {
            $root = 'https://mirrors.kernel.org/linuxmint/stable/'
            $ver = Get-KitLatestDir -IndexUrl $root
            $base = "$root$ver/"
            $hit = Find-KitChecksum -Text (Get-KitText -Url ($base + 'sha256sum.txt')) -Pattern '^linuxmint-[\d.]+-cinnamon-64bit\.iso$'
            $label = 'Linux Mint {0} (Cinnamon)'
        }
        'Fedora' {
            $root = 'https://dl.fedoraproject.org/pub/fedora/linux/releases/'
            $rel = Get-KitLatestDir -IndexUrl $root -Pattern '^\d+$'
            $base = "$root$rel/Workstation/x86_64/iso/"
            $index = Get-KitText -Url $base
            $sumFile = @([regex]::Matches($index, 'href="([^"]+-CHECKSUM)"') | ForEach-Object { $_.Groups[1].Value }) | Select-Object -First 1
            if (-not $sumFile) { throw "Fichier CHECKSUM Fedora introuvable dans $base" }
            $hit = Find-KitChecksum -Text (Get-KitText -Url ($base + $sumFile)) -Pattern '^Fedora-Workstation-Live-.*x86_64\.iso$'
            $label = 'Fedora Workstation {0}'
        }
        default { throw "Distribution inconnue : $($Item.Distro)" }
    }
    if (-not $hit) { throw "ISO introuvable dans la liste d'empreintes officielle de $($Item.Distro)." }
    $version = ''
    if ($hit.FileName -match '(\d+(\.\d+)+)') { $version = $Matches[1] }
    elseif ($hit.FileName -match '-(\d+)-') { $version = $Matches[1] }
    if ($Item.Distro -eq 'Fedora') { $version = $rel }   # « 44-1.7 » : la version est le numéro de release
    return [pscustomobject]@{
        Version  = $version
        Url      = $base + $hit.FileName
        FileName = $hit.FileName
        Sha256   = $hit.Sha256
        Label    = ($label -f $version)
    }
}

function Expand-KitPortable {
    <#
    .SYNOPSIS
        Décompresse un outil portable (zip) dans <dossier>\app pour l'utiliser depuis la clé.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StageDir,
        [Parameter(Mandatory)] [string] $ZipPath
    )
    $app = Join-Path $StageDir 'app'
    if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $app -Force
    Write-KitLog -Message ("{0} décompressé dans app\ ({1} fichier(s))" -f (Split-Path -Leaf $ZipPath), @(Get-ChildItem -LiteralPath $app -Recurse -File).Count)
}

# --------------------------------------------------------------------------- utilitaires

function Initialize-KitNetwork {
    <#
    .SYNOPSIS
        Active TLS 1.2 (et 1.3 si disponible) — indispensable sous Windows PowerShell 5.1.
    #>
    [CmdletBinding()]
    param()
    $proto = [Net.SecurityProtocolType]::Tls12
    try { $proto = $proto -bor [Net.SecurityProtocolType]::Tls13 } catch { Write-Verbose 'TLS 1.3 indisponible sur ce système.' }
    [Net.ServicePointManager]::SecurityProtocol = $proto
    # Proxy d'entreprise avec authentification Windows : sans ces identifiants, chaque requête
    # échoue en « 407 Proxy Authentication Required »
    try {
        $proxy = [Net.WebRequest]::DefaultWebProxy
        if ($proxy) { $proxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials }
    }
    catch { Write-Verbose 'Proxy système non configurable.' }
}

function Initialize-KitWinget {
    <#
    .SYNOPSIS
        Rend winget utilisable dans le processus courant et retourne son chemin (vide si absent).
    .DESCRIPTION
        winget est un « alias d'exécution » propre à chaque utilisateur. Dans une session élevée
        (clé neuve : autorisation administrateur, parfois avec un AUTRE compte), il est souvent
        introuvable. On le cherche alors dans le dossier de l'utilisateur et dans le paquet
        App Installer, et on ajoute son dossier au PATH du processus.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return [string]$cmd.Source }
    if (-not (Test-KitWindows)) { return '' }
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe' }
    $apps = Join-Path $env:ProgramFiles 'WindowsApps'
    try {
        $candidates += @(Get-ChildItem -LiteralPath $apps -Directory -Filter 'Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe' -ErrorAction Stop |
                Sort-Object { try { [version](($_.Name -split '_')[1]) } catch { [version]'0.0' } } -Descending |
                ForEach-Object { Join-Path $_.FullName 'winget.exe' })
    }
    catch { Write-Verbose "Dossier $apps illisible." }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $env:PATH = (Split-Path -Parent $c) + [IO.Path]::PathSeparator + $env:PATH
            Write-KitLog -Message ("winget trouvé hors du PATH : {0}" -f $c)
            return $c
        }
    }
    return ''
}

function Set-KitKeepAwake {
    <#
    .SYNOPSIS
        Windows : empêche la mise en veille pendant la préparation (plusieurs Go à télécharger),
        puis rétablit le comportement normal. L'écran peut s'éteindre, l'ordinateur reste actif.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [bool] $Enabled)
    if (-not (Test-KitWindows)) { return }
    if (-not $PSCmdlet.ShouldProcess('Mise en veille', $(if ($Enabled) { 'Suspendre' } else { 'Rétablir' }))) { return }
    try {
        if (-not ('Alchemist.Power' -as [type])) {
            Add-Type -Namespace Alchemist -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
        }
        # ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x1)
        $flags = [uint32]2147483648
        if ($Enabled) { $flags = $flags -bor [uint32]1 }
        [void][Alchemist.Power]::SetThreadExecutionState($flags)
        if ($Enabled) { Write-KitLog -Message 'Mise en veille suspendue pendant la préparation.' }
    }
    catch { Write-Verbose ('Mise en veille non contrôlable : {0}' -f $_.Exception.Message) }
}

function Get-KitValue {
    <#
    .SYNOPSIS
        Lit une clé d'un hashtable ou une propriété d'objet, avec valeur par défaut
        (compatible Set-StrictMode, y compris pour les objets issus de JSON).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Object,
        [Parameter(Mandatory)] [string] $Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Get-KitSha256 {
    <#
    .SYNOPSIS
        Retourne le SHA256 (minuscules) d'un fichier.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-KitSafeFileName {
    <#
    .SYNOPSIS
        Déduit un nom de fichier propre à partir d'une URL finale (après redirections).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Url)
    $segment = ([uri]$Url).Segments[-1]
    $name = [uri]::UnescapeDataString($segment)
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $name = $name.Replace([string]$c, '_') }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'telechargement.bin' }
    return $name
}

function Get-KitRemoteInfo {
    <#
    .SYNOPSIS
        Interroge une URL sans la télécharger : URL finale, taille, date, nom de fichier.
    .DESCRIPTION
        Requête HEAD (redirections suivies). Si le serveur refuse HEAD, repli sur un GET
        de l'octet 0 (Content-Range). 3 tentatives.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Url, [string] $Agent = '')
    if (-not $Agent) { $Agent = $script:UserAgent }
    $lastError = $null
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        foreach ($method in @('HEAD', 'RANGE')) {
            $resp = $null
            try {
                $req = [Net.HttpWebRequest]::Create($Url)
                $req.UserAgent = $Agent
                $req.AllowAutoRedirect = $true
                $req.Timeout = 30000
                if ($method -eq 'HEAD') { $req.Method = 'HEAD' } else { $req.Method = 'GET'; $req.AddRange([long]0, [long]0) }
                $resp = $req.GetResponse()
                $length = [double]$resp.ContentLength
                if ($method -eq 'RANGE') {
                    $range = $resp.Headers['Content-Range']
                    if ($range -and $range -match '/(\d+)$') { $length = [double]$Matches[1] } else { $length = -1 }
                }
                $final = $resp.ResponseUri.AbsoluteUri
                return [pscustomobject]@{
                    Url          = $Url
                    FinalUrl     = $final
                    Length       = $length
                    LastModified = [string]$resp.Headers['Last-Modified']
                    FileName     = (Get-KitSafeFileName -Url $final)
                }
            }
            catch { $lastError = $_.Exception.Message }
            finally { if ($resp) { $resp.Close() } }
        }
        Start-Sleep -Seconds (2 * $attempt)
    }
    throw ("URL injoignable après {0} tentatives : {1} ({2})" -f $script:MaxAttempts, $Url, $lastError)
}

function Invoke-KitHttpDownload {
    <#
    .SYNOPSIS
        Télécharge une URL vers un fichier avec reprise (fichier .part + en-tête Range)
        et 3 tentatives.
    .PARAMETER SourceTag
        Identifiant de la version attendue. Si un .part existant provient d'une autre
        version, il est supprimé au lieu d'être repris (évite un fichier mélangé).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Destination,
        [double] $ExpectedLength = -1,
        [string] $SourceTag = '',
        [string] $Agent = ''
    )
    if (-not $SourceTag) { $SourceTag = $Url }
    if (-not $Agent) { $Agent = $script:UserAgent }
    $part = "$Destination.part"
    $tagFile = "$Destination.part.src"
    $label = Split-Path -Leaf $Destination

    if ((Test-Path -LiteralPath $tagFile) -and ((Get-Content -LiteralPath $tagFile -Raw).Trim() -ne $SourceTag)) {
        Write-KitLog -Level WARN -Message "$label : fichier partiel d'une autre version, il est supprimé."
        Remove-Item -LiteralPath $part, $tagFile -Force -ErrorAction SilentlyContinue
    }

    # Les tentatives ne sont comptées que lorsqu'elles n'apportent rien : une connexion instable
    # qui coupe régulièrement finit l'ISO (reprise) au lieu d'abandonner après 3 coupures.
    $attempt = 0; $loops = 0
    while ($true) {
        $attempt++; $loops++
        $resp = $null; $stream = $null; $fs = $null
        $sizeBefore = 0.0
        if (Test-Path -LiteralPath $part) { $sizeBefore = [double](Get-Item -LiteralPath $part).Length }
        try {
            $have = 0.0
            if (Test-Path -LiteralPath $part) { $have = [double](Get-Item -LiteralPath $part).Length }
            if ($ExpectedLength -gt 0 -and $have -gt $ExpectedLength) {
                Remove-Item -LiteralPath $part -Force; $have = 0.0
            }
            if (-not ($ExpectedLength -gt 0 -and $have -eq $ExpectedLength)) {
                Set-Content -LiteralPath $tagFile -Value $SourceTag -Encoding UTF8
                $req = [Net.HttpWebRequest]::Create($Url)
                $req.UserAgent = $Agent
                $req.AllowAutoRedirect = $true
                $req.Timeout = 60000
                $req.ReadWriteTimeout = 120000
                if ($have -gt 0) { $req.AddRange([long]$have) }
                $resp = $req.GetResponse()
                $append = ($have -gt 0 -and [int]$resp.StatusCode -eq 206)
                if ($have -gt 0 -and -not $append) {
                    Write-KitLog -Level WARN -Message "$label : le serveur ne gère pas la reprise, téléchargement complet."
                    $have = 0.0
                }
                elseif ($append) {
                    Write-KitLog -Message ("{0} : reprise à {1}" -f $label, (Format-KitSize $have))
                }
                $total = $ExpectedLength
                if ($resp.ContentLength -gt 0) { $total = $have + [double]$resp.ContentLength }

                $mode = [IO.FileMode]::Create
                if ($append) { $mode = [IO.FileMode]::Append }
                $fs = New-Object IO.FileStream($part, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None, 1MB)
                $stream = $resp.GetResponseStream()
                $buffer = New-Object byte[] (1MB)
                $done = $have
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $lastLog = 0
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fs.Write($buffer, 0, $read)
                    $done += $read
                    if ($timer.ElapsedMilliseconds - $lastLog -ge 1000) {
                        $lastLog = $timer.ElapsedMilliseconds
                        if ($total -gt 0) {
                            $pct = [math]::Min(100, [int](100 * $done / $total))
                            Write-Progress -Activity "Téléchargement $label" -Status ("{0} / {1}" -f (Format-KitSize $done), (Format-KitSize $total)) -PercentComplete $pct
                        }
                        else {
                            Write-Progress -Activity "Téléchargement $label" -Status (Format-KitSize $done)
                        }
                    }
                }
                Write-Progress -Activity "Téléchargement $label" -Completed
                $fs.Dispose(); $fs = $null
                if ($total -gt 0) {
                    $len = [double](Get-Item -LiteralPath $part).Length
                    if ($len -ne $total) { throw ("téléchargement incomplet ({0} sur {1})" -f (Format-KitSize $len), (Format-KitSize $total)) }
                }
            }
            # Un serveur peut renvoyer une page web (erreur, captcha, miroir) au lieu du fichier : refus
            $head = New-Object byte[] 64
            $hs = [IO.File]::OpenRead($part)
            try { $n = $hs.Read($head, 0, 64) } finally { $hs.Dispose() }
            $start = [Text.Encoding]::ASCII.GetString($head, 0, $n).TrimStart().ToLowerInvariant()
            $isHtml = $start.StartsWith('<!doctype html') -or $start.StartsWith('<html')
            if ($isHtml -and $label -notmatch '\.(html?|xml)$') {
                Remove-Item -LiteralPath $part, $tagFile -Force -ErrorAction SilentlyContinue
                throw "le serveur a renvoyé une page web au lieu du fichier attendu ($Url)"
            }
            if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
            Move-Item -LiteralPath $part -Destination $Destination
            Remove-Item -LiteralPath $tagFile -Force -ErrorAction SilentlyContinue
            return
        }
        catch {
            $msg = $_.Exception.Message
            # 416 = plage demandée invalide : le .part est déjà complet ou corrompu
            if ($msg -match '416') {
                Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            }
            Write-KitLog -Level WARN -Message ("{0} : tentative {1}/{2} échouée : {3}" -f $label, $attempt, $script:MaxAttempts, $msg)
            # Fichier fermé avant de le mesurer : le dernier bloc en mémoire tampon compte
            if ($fs) { $fs.Dispose(); $fs = $null }
            $sizeAfter = 0.0
            if (Test-Path -LiteralPath $part) { $sizeAfter = [double](Get-Item -LiteralPath $part).Length }
            if ($sizeAfter -gt $sizeBefore + 1MB -and $loops -lt 40) {
                Write-KitLog -Message ("{0} : {1} reçus avant la coupure, reprise." -f $label, (Format-KitSize ($sizeAfter - $sizeBefore)))
                $attempt = 0
            }
            if ($attempt -ge $script:MaxAttempts -or $loops -ge 40) { break }
            Start-Sleep -Seconds (5 * [math]::Max(1, $attempt))
        }
        finally {
            if ($fs) { $fs.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($resp) { $resp.Close() }
        }
    }
    throw ("Échec du téléchargement après {0} tentatives : {1}" -f $loops, $Url)
}

function Test-KitSignature {
    <#
    .SYNOPSIS
        Vérifie la signature Authenticode d'un fichier.
    .DESCRIPTION
        - Signature corrompue (HashMismatch) ou non approuvée (NotTrusted) : toujours refusée.
        - Non signé : refusé si -Required (aucun autre moyen de vérifier), sinon avertissement
          (l'intégrité est alors garantie par le SHA256 du manifeste winget).
        - Éditeur différent de -Signer : refusé si -Required, sinon avertissement.
        - Format non pris en charge par Authenticode (ex. certains MSIX) : avertissement.
    .OUTPUTS
        Texte décrivant le résultat. Lève une exception en cas de refus.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Signer = '',
        [switch] $Required
    )
    $leaf = Split-Path -Leaf $Path
    if ($script:SkipSignature) {
        # Vérification désactivée par l'opérateur (-SansVerifSignature) : on le trace
        return 'signature non vérifiée (désactivée par -SansVerifSignature)'
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    $status = [string]$sig.Status
    $subject = ''
    if ($sig.SignerCertificate) { $subject = $sig.SignerCertificate.Subject }
    switch ($status) {
        'Valid' {
            if ($Signer -and $subject -notmatch $Signer) {
                $m = "$leaf : signé par « $subject », éditeur attendu « $Signer »."
                if ($Required) { throw $m }
                Write-KitLog -Level WARN -Message $m
                return "signature valide (éditeur inattendu)"
            }
            return ("signature valide : {0}" -f ($subject -replace '^CN=("?)([^,"]+).*$', '$2'))
        }
        'NotSigned' {
            if ($Required) { throw "$leaf n'est pas signé : impossible de vérifier son origine." }
            Write-KitLog -Level WARN -Message "$leaf n'est pas signé numériquement (intégrité garantie par le SHA256 publié)."
            return 'non signé (SHA256 publié vérifié)'
        }
        { $_ -in @('HashMismatch', 'NotTrusted') } {
            throw "$leaf : signature numérique invalide ($status). Fichier refusé."
        }
        default {
            # Sans SHA256 publié (-Required), une signature non vérifiable ne prouve rien : refus
            if ($Required) { throw "$leaf : signature non vérifiable ($status) et aucune empreinte publiée : fichier refusé." }
            Write-KitLog -Level WARN -Message "$leaf : signature non vérifiable par Authenticode ($status)."
            return "signature non vérifiable ($status)"
        }
    }
}

function Test-KitIsoFile {
    <#
    .SYNOPSIS
        Vérifie qu'un fichier est une image ISO complète (taille et descripteur ISO 9660).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [double] $ExpectedLength = -1
    )
    $len = [double](Get-Item -LiteralPath $Path).Length
    if ($ExpectedLength -gt 0 -and $len -ne $ExpectedLength) {
        throw ("ISO incomplète : {0} au lieu de {1}" -f (Format-KitSize $len), (Format-KitSize $ExpectedLength))
    }
    $fs = [IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 5
        [void]$fs.Seek(32769, [IO.SeekOrigin]::Begin)   # descripteur de volume primaire
        [void]$fs.Read($buf, 0, 5)
        if ([Text.Encoding]::ASCII.GetString($buf) -ne 'CD001') { throw "Le fichier n'est pas une image ISO valide (signature CD001 absente)." }
    }
    finally { $fs.Dispose() }
}

function Get-KitKeySource {
    <#
    .SYNOPSIS
        Lit le fichier <Nom>.source.json déjà présent sur la clé pour un élément (ou $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [hashtable] $Item
    )
    $path = Join-Path (Join-Path $KeyRoot $Item.TargetDir) ("{0}.source.json" -f $Item.Name)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Write-KitLog -Level WARN -Message "Fichier source illisible : $path"; return $null }
}

function Write-KitSourceFile {
    <#
    .SYNOPSIS
        Écrit <Nom>.source.json dans la zone de préparation : marque l'élément comme complet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StageDir,
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [hashtable] $Data
    )
    $Data['Name'] = $Item.Name
    $Data['Type'] = $Item.Type
    $Data['RetrievedOn'] = (Get-Date).ToString('s')
    $path = Join-Path $StageDir ("{0}.source.json" -f $Item.Name)
    $Data | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Get-KitStageDir {
    <#
    .SYNOPSIS
        Dossier de préparation d'un élément dans le cache (créé si besoin).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $Name
    )
    $dir = Join-Path $CacheRoot $Name
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Test-KitStageComplete {
    <#
    .SYNOPSIS
        Indique si la zone de préparation contient un élément complet (source.json présent).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $Name
    )
    return (Test-Path -LiteralPath (Join-Path (Join-Path $CacheRoot $Name) "$Name.source.json"))
}

function Get-KitPartialSize {
    <#
    .SYNOPSIS
        Octets déjà présents dans la zone de préparation (fichiers .part et fichiers finis).
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([Parameter(Mandatory)] [string] $StageDir)
    if (-not (Test-Path -LiteralPath $StageDir)) { return 0.0 }
    $sum = 0.0
    foreach ($f in @(Get-ChildItem -LiteralPath $StageDir -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sum += $f.Length }
    return $sum
}

# --------------------------------------------------------------------------- winget

function Invoke-KitWinget {
    <#
    .SYNOPSIS
        Lance winget avec les arguments donnés ; retourne le code de sortie et la sortie texte.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & winget @Arguments 2>&1 | ForEach-Object { [string]$_ }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($out) }
}

function Get-KitWingetFilter {
    <#
    .SYNOPSIS
        Arguments communs de filtrage winget (identifiant exact, architecture, type, langue).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [hashtable] $Item)
    $a = @('--id', $Item.WingetId, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    $arch = Get-KitValue $Item 'Architecture'
    if ($arch) { $a += @('--architecture', $arch) }
    $type = Get-KitValue $Item 'InstallerType'
    if ($type) { $a += @('--installer-type', $type) }
    $locale = Get-KitValue $Item 'Locale'
    if ($locale) { $a += @('--locale', $locale) }
    $scope = Get-KitValue $Item 'Scope'
    if ($scope) { $a += @('--scope', $scope) }
    return , $a
}

function Get-KitWingetInfo {
    <#
    .SYNOPSIS
        Lit dans le dépôt winget la version, l'URL et le SHA256 de l'installeur retenu.
    .DESCRIPTION
        La sortie de « winget show » est traduite selon la langue de Windows ; on s'appuie donc
        sur des motifs indépendants de la langue : dernière URL et empreinte de 64 caractères
        hexadécimaux (section « Programme d'installation », toujours en fin de sortie).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [hashtable] $Item)
    $lastOutput = ''
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        $r = Invoke-KitWinget -Arguments (@('show') + (Get-KitWingetFilter -Item $Item))
        $lastOutput = ($r.Output | Select-Object -Last 3) -join ' | '
        $urls = @($r.Output | Select-String -Pattern 'https?://\S+' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object Value)
        $hashes = @($r.Output | Select-String -Pattern '\b[0-9A-Fa-f]{64}\b' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object Value)
        $version = ''
        foreach ($line in $r.Output) { if ($line -cmatch '^\s*Version\s*:\s*(\S+)') { $version = $Matches[1]; break } }
        if ($r.ExitCode -eq 0 -and $urls.Count -gt 0 -and $hashes.Count -gt 0) {
            return [pscustomobject]@{
                Version = $version
                Url     = $urls[-1]
                Sha256  = $hashes[-1].ToLowerInvariant()
            }
        }
        if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (3 * $attempt) }
    }
    throw ("winget ne trouve pas d'installeur hors ligne pour {0} : {1}" -f $Item.WingetId, $lastOutput)
}

# --------------------------------------------------------------------------- Windows / Office

function Get-KitFido {
    <#
    .SYNOPSIS
        Télécharge le script Fido officiel (github.com/pbatard/Fido) dans le dossier d'outils.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $ToolsDir,
        [Parameter(Mandatory)] [string] $FidoUrl
    )
    if (-not (Test-Path -LiteralPath $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
    $path = Join-Path $ToolsDir 'Fido.ps1'
    Invoke-KitHttpDownload -Url $FidoUrl -Destination $path
    return $path
}

function Get-KitWindowsIsoUrl {
    <#
    .SYNOPSIS
        Obtient via Fido le lien de téléchargement officiel Microsoft de l'ISO Windows 11.
    .DESCRIPTION
        Fido interroge le site de Microsoft et retourne un lien temporaire (24 h) hébergé
        par Microsoft. Le lien est refusé s'il ne pointe pas vers un domaine microsoft.com.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [string] $FidoPath
    )
    $last = ''
    # Linux : Fido refuse les plateformes autres que Windows (choix de l'auteur, pas une limite de l'API
    # Microsoft) et lit l'architecture par WMI. Copie adaptée (GPLv3) : version de Windows simulée et
    # architecture x64 fournie ; le lien obtenu reste contrôlé (domaine microsoft.com obligatoire).
    $linuxPrefix = ''
    if (-not (Test-KitWindows)) {
        $src = [IO.File]::ReadAllText($FidoPath)
        if ($src -match '(?m)^\$winver = Get-Platform-Version\s*$') {
            $FidoPath = Join-Path (Split-Path -Parent $FidoPath) 'Fido-linux.ps1'
            [IO.File]::WriteAllText($FidoPath, ($src -replace '(?m)^\$winver = Get-Platform-Version\s*$', '$winver = 10.0'), (New-Object Text.UTF8Encoding($true)))
            $linuxPrefix = 'function global:Get-CimInstance { param([string] $ClassName) [pscustomobject]@{ Architecture = 9 } }; '
        }
    }
    for ($attempt = 1; $attempt -le $script:MaxAttempts; $attempt++) {
        if (Test-KitWindows) {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $FidoPath `
                -Win $Item.FidoWin -Rel $Item.FidoRel -Ed $Item.FidoEd -Lang $Item.FidoLang -Arch $Item.FidoArch -GetUrl 2>&1 |
                ForEach-Object { [string]$_ }
        }
        else {
            $q = { param($v) "'" + ([string]$v).Replace("'", "''") + "'" }
            $cmd = $linuxPrefix + ("& {0} -Win {1} -Rel {2} -Ed {3} -Lang {4} -Arch {5} -GetUrl" -f (& $q $FidoPath), (& $q $Item.FidoWin), (& $q $Item.FidoRel), (& $q $Item.FidoEd), (& $q $Item.FidoLang), (& $q $Item.FidoArch))
            $out = & (Get-Process -Id $PID).Path -NoProfile -Command $cmd 2>&1 | ForEach-Object { [string]$_ }
        }
        $url = @($out | Where-Object { $_ -match '^https://\S+\.iso' }) | Select-Object -Last 1
        if ($url) {
            $hostName = ([uri]$url).Host
            if ($hostName -notmatch '(^|\.)microsoft\.com$') { throw "Fido a retourné un lien non Microsoft ($hostName) : refusé." }
            return $url.Trim()
        }
        $last = ($out | Select-Object -Last 3) -join ' | '
        if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (10 * $attempt) }
    }
    throw ("Fido n'a pas pu obtenir le lien officiel de l'ISO ({0}). Microsoft bloque parfois les requêtes automatisées (erreur 715-123130) : téléchargez l'ISO à la main depuis https://www.microsoft.com/fr-fr/software-download/windows{1} et collez le lien dans l'assistant (« Lien de l'ISO »), ou placez-la dans le cache sous le nom {2} puis relancez avec -SkipDownload." -f $last, $(if ([string]$Item.FidoWin -eq '10') { '10ISO' } else { '11' }), $Item.FileName)
}

function Get-KitOfficeVersion {
    <#
    .SYNOPSIS
        Lit sur le CDN Office officiel la dernière version x64 du canal configuré.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [string] $ToolsDir
    )
    if (-not (Test-Path -LiteralPath $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null }
    $cab = Join-Path $ToolsDir 'v64.cab'
    $xml = Join-Path $ToolsDir 'VersionDescriptor.xml'
    Remove-Item -LiteralPath $cab, $xml -Force -ErrorAction SilentlyContinue
    Invoke-KitHttpDownload -Url $Item.ChannelCabUrl -Destination $cab
    $null = & expand.exe $cab "-F:VersionDescriptor.xml" $ToolsDir 2>&1
    if (-not (Test-Path -LiteralPath $xml)) { throw 'Impossible de lire le descripteur de version Office (v64.cab).' }
    [xml]$doc = Get-Content -LiteralPath $xml -Raw
    $version = [string]$doc.Version.Available.I640Version
    if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "Version Office illisible dans le descripteur : « $version »." }
    return $version
}

# --------------------------------------------------------------------------- résolution

function Resolve-KitPlan {
    <#
    .SYNOPSIS
        Remplit un plan : version disponible, taille réelle, état (à jour / à télécharger…).
    .DESCRIPTION
        Ne télécharge rien d'autre que de petits fichiers d'outillage (Fido, descripteur Office)
        dans le dossier d'outils. N'écrit rien sur la clé.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $KeyRoot,
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $ToolsDir,
        [Parameter(Mandatory)] [string] $FidoUrl,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [hashtable] $Manifest,
        [string] $WindowsIsoUrl = '',
        [switch] $SkipDownload
    )
    $item = $Plan.Item
    $stage = Join-Path $CacheRoot $item.Name
    $keySrc = Get-KitKeySource -KeyRoot $KeyRoot -Item $item
    $Plan.OldBytes = Get-KitManagedSize -KeyRoot $KeyRoot -Manifest $Manifest -Prefix ($item.TargetDir.TrimEnd('/') + '/')
    $Plan.PartialBytes = Get-KitPartialSize -StageDir $stage

    # Mode -SkipDownload : on ne regarde que ce qui est déjà présent
    if ($SkipDownload) {
        $manualIso = $null
        if ($item.Type -eq 'WindowsIso') { $manualIso = Join-Path $stage $item.FileName }
        if (Test-KitStageComplete -CacheRoot $CacheRoot -Name $item.Name) {
            $Plan.Status = 'CACHE'; $Plan.SizeSource = 'cache'; $Plan.NewBytes = $Plan.PartialBytes
            $Plan.Detail = 'Complet dans le cache, à mettre en place'
        }
        elseif ($manualIso -and (Test-Path -LiteralPath $manualIso)) {
            # ISO officielle téléchargée à la main et déposée dans le cache : sera vérifiée puis mise en place
            $len = [double](Get-Item -LiteralPath $manualIso).Length
            $Plan.Status = 'A_TELECHARGER'; $Plan.SizeSource = 'cache'; $Plan.NewBytes = $len
            $Plan.Version = '(ISO déposée manuellement)'
            $Plan.Source = [pscustomobject]@{ Url = ''; Length = $len; OriginalName = '(ISO déposée manuellement)' }
        }
        elseif ($keySrc) {
            $Plan.Status = 'A_JOUR'; $Plan.Version = [string](Get-KitValue $keySrc 'Version' '')
            $Plan.NewBytes = $Plan.OldBytes; $Plan.SizeSource = 'clé'; $Plan.Detail = 'Déjà sur la clé (non revérifié en ligne)'
        }
        else {
            $Plan.Status = 'ABSENT'; $Plan.Detail = 'Absent du cache (-SkipDownload)'
        }
        return
    }

    switch ($item.Type) {
        'Winget' {
            $info = Get-KitWingetInfo -Item $item
            $Plan.Version = $info.Version
            $Plan.Source = $info
            try {
                $ri = Get-KitRemoteInfo -Url $info.Url
                if ($ri.Length -gt 0) { $Plan.NewBytes = $ri.Length; $Plan.SizeSource = 'winget+HEAD' }
            }
            catch { Write-KitLog -Level WARN -Message ("{0} : taille non lue ({1}), valeur de repli utilisée." -f $item.Name, $_.Exception.Message) }
            # À jour si le SHA256 de l'installeur publié correspond à celui déjà sur la clé
            $keyFiles = @(Get-KitValue $keySrc 'Files' @())
            foreach ($f in $keyFiles) {
                $rel = ($item.TargetDir.TrimEnd('/') + '/' + $f.Name)
                if ($f.Sha256 -eq $info.Sha256 -and $Manifest.ContainsKey($rel) -and $Manifest[$rel] -eq $info.Sha256 -and
                    (Test-Path -LiteralPath (Join-Path $KeyRoot $rel))) { $Plan.Status = 'A_JOUR' }
            }
        }
        'Url' {
            $files = @()
            foreach ($f in @($item.Files)) {
                $ri = Get-KitRemoteInfo -Url $f.Url
                $name = Get-KitValue $f 'FileName' $ri.FileName
                $files += [pscustomobject]@{ Url = $f.Url; FinalUrl = $ri.FinalUrl; Length = $ri.Length; LastModified = $ri.LastModified; FileName = $name; Sha256 = [string](Get-KitValue $f 'Sha256' '') }
            }
            $Plan.Source = $files
            $total = 0.0; $known = $true
            foreach ($f in $files) { if ($f.Length -gt 0) { $total += $f.Length } else { $known = $false } }
            if ($known) { $Plan.NewBytes = $total; $Plan.SizeSource = 'HEAD' }
            $Plan.Version = (($files | ForEach-Object FileName) -join ', ')
            # À jour si chaque fichier a le même nom, la même taille et la même date côté serveur
            $upToDate = ($null -ne $keySrc)
            foreach ($f in $files) {
                $k = @(Get-KitValue $keySrc 'Files' @()) | Where-Object { $_.Name -eq $f.FileName } | Select-Object -First 1
                $rel = ($item.TargetDir.TrimEnd('/') + '/' + $f.FileName)
                if (-not $k -or [double]$k.Length -ne [double]$f.Length -or [string](Get-KitValue $k 'LastModified' '') -ne $f.LastModified -or
                    -not $Manifest.ContainsKey($rel) -or -not (Test-Path -LiteralPath (Join-Path $KeyRoot $rel))) { $upToDate = $false }
            }
            if ($upToDate) { $Plan.Status = 'A_JOUR' }
        }
        'LinuxIso' {
            $info = Resolve-KitLinuxIso -Item $item
            $Plan.Version = $info.Label
            $Plan.Source = $info
            try {
                $ri = Get-KitRemoteInfo -Url $info.Url -Agent $script:PlainAgent
                if ($ri.Length -gt 0) { $Plan.NewBytes = $ri.Length; $Plan.SizeSource = 'HEAD'; $info | Add-Member -NotePropertyName Length -NotePropertyValue $ri.Length -Force }
            }
            catch { Write-KitLog -Level WARN -Message ("{0} : taille non lue, valeur de repli." -f $item.Name) }
            $rel = ($item.TargetDir.TrimEnd('/') + '/' + $info.FileName)
            $k = @(Get-KitValue $keySrc 'Files' @()) | Where-Object { $_.Name -eq $info.FileName } | Select-Object -First 1
            if ($k -and $k.Sha256 -eq $info.Sha256 -and $Manifest.ContainsKey($rel) -and (Test-Path -LiteralPath (Join-Path $KeyRoot $rel))) { $Plan.Status = 'A_JOUR' }
        }
        'GitHub' {
            $info = Get-KitGitHubRelease -Repo $item.Repo -AssetPattern $item.AssetPattern
            $Plan.Version = $info.Version
            $Plan.Source = $info
            if ($info.Length -gt 0) { $Plan.NewBytes = $info.Length; $Plan.SizeSource = 'GitHub' }
            $rel = ($item.TargetDir.TrimEnd('/') + '/' + $info.FileName)
            $k = @(Get-KitValue $keySrc 'Files' @()) | Where-Object { $_.Name -eq $info.FileName } | Select-Object -First 1
            if ($k -and $Manifest.ContainsKey($rel) -and (Test-Path -LiteralPath (Join-Path $KeyRoot $rel)) -and
                (($info.Sha256 -and $k.Sha256 -eq $info.Sha256) -or (-not $info.Sha256 -and [double]$k.Length -eq $info.Length))) {
                $Plan.Status = 'A_JOUR'
            }
        }
        'WindowsIso' {
            # Le lien manuel ne vaut que pour SA version de Windows : les noms Microsoft commencent par
            # « Win10_ » / « Win11_ » ; un nom illisible est attribué à l'ISO principale (Windows 11)
            $manualFor = ''
            if ($WindowsIsoUrl -and (([uri]$WindowsIsoUrl).AbsolutePath -match '/Win(\d+)_')) { $manualFor = $Matches[1] }
            $useManual = [bool]$WindowsIsoUrl -and (($manualFor -and $manualFor -eq [string]$item.FidoWin) -or (-not $manualFor -and [int](Get-KitValue $item 'Priority' 9) -le 1))
            if ($useManual) {
                # Lien officiel fourni par l'opérateur (Fido bloqué) : domaine Microsoft obligatoire
                $hostName = ([uri]$WindowsIsoUrl).Host
                if ($hostName -notmatch '(^|\.)microsoft\.com$') { throw "-WindowsIsoUrl doit pointer vers un domaine microsoft.com (reçu : $hostName)." }
                $url = $WindowsIsoUrl
            }
            else {
                try {
                    $fido = Get-KitFido -ToolsDir $ToolsDir -FidoUrl $FidoUrl
                    $url = Get-KitWindowsIsoUrl -Item $item -FidoPath $fido
                }
                catch {
                    # Microsoft bloque parfois Fido : si l'ISO est déjà sur la clé, on la conserve
                    $relIso = ($item.TargetDir.TrimEnd('/') + '/' + $item.FileName)
                    if ($keySrc -and $Manifest.ContainsKey($relIso) -and (Test-Path -LiteralPath (Join-Path $KeyRoot $relIso))) {
                        Write-KitLog -Level WARN -Message ("Windows : lien Microsoft indisponible ({0}). L'ISO déjà présente sur la clé est conservée." -f $_.Exception.Message.Split('.')[0])
                        $Plan.Status = 'A_JOUR'; $Plan.Version = [string](Get-KitValue $keySrc 'OriginalName' '')
                        $Plan.NewBytes = $Plan.OldBytes; $Plan.Detail = 'Conservée (vérification en ligne impossible)'
                        return
                    }
                    throw
                }
            }
            $ri = Get-KitRemoteInfo -Url $url
            $orig = Get-KitSafeFileName -Url $url
            $Plan.Source = [pscustomobject]@{ Url = $url; Length = $ri.Length; OriginalName = $orig }
            $Plan.Version = $orig
            if ($ri.Length -gt 0) { $Plan.NewBytes = $ri.Length; $Plan.SizeSource = 'HEAD' }
            $rel = ($item.TargetDir.TrimEnd('/') + '/' + $item.FileName)
            if ($keySrc -and [string](Get-KitValue $keySrc 'OriginalName' '') -eq $orig -and
                [double](Get-KitValue $keySrc 'Length' 0) -eq [double]$ri.Length -and $Manifest.ContainsKey($rel) -and
                (Test-Path -LiteralPath (Join-Path $KeyRoot $rel))) { $Plan.Status = 'A_JOUR' }
        }
        'Office' {
            $version = Get-KitOfficeVersion -Item $item -ToolsDir $ToolsDir
            $Plan.Version = $version
            $Plan.Source = [pscustomobject]@{ Version = $version }
            $dataDir = Join-Path (Join-Path $KeyRoot $item.TargetDir) ("Office\Data\{0}" -f $version)
            $wantLang = [string](Get-KitValue $item 'OfficeLanguage' 'fr-fr')
            $haveLang = [string](Get-KitValue $keySrc 'Language' 'fr-fr')
            if ($keySrc -and [string](Get-KitValue $keySrc 'Version' '') -eq $version -and $haveLang -eq $wantLang -and (Test-Path -LiteralPath $dataDir)) {
                $Plan.Status = 'A_JOUR'
            }
        }
        default { throw "Type d'élément inconnu : $($item.Type)" }
    }

    if ($Plan.Status -eq 'A_JOUR') {
        $Plan.NewBytes = $Plan.OldBytes; $Plan.Detail = 'Déjà à jour sur la clé'
        return
    }
    # Téléchargement déjà terminé en cache pour la même version : rien à retélécharger
    if (Test-KitStageComplete -CacheRoot $CacheRoot -Name $item.Name) {
        $staged = Get-Content -LiteralPath (Join-Path $stage "$($item.Name).source.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string](Get-KitValue $staged 'Version' '') -eq [string]$Plan.Version) {
            $Plan.Status = 'CACHE'; $Plan.Detail = 'Déjà complet dans le cache'
            return
        }
    }
    $Plan.Status = 'A_TELECHARGER'
}

# --------------------------------------------------------------------------- téléchargement

function Save-KitWingetItem {
    <#
    .SYNOPSIS
        winget download (manifeste YAML conservé), vérification SHA256 + signature ;
        repli sur l'URL officielle de l'éditeur si winget échoue.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir
    )
    $item = $Plan.Item
    Get-ChildItem -LiteralPath $StageDir -Force | Remove-Item -Recurse -Force
    $installer = $null; $sigInfo = ''; $source = 'winget'; $sha = ''
    $wingetError = ''
    for ($attempt = 1; $attempt -le $script:MaxAttempts -and -not $installer; $attempt++) {
        $args2 = @('download') + (Get-KitWingetFilter -Item $item) + @('-d', $StageDir, '--accept-package-agreements', '--skip-dependencies', '--skip-license')
        $r = Invoke-KitWinget -Arguments $args2
        if ($r.ExitCode -eq 0) {
            $installer = Get-ChildItem -LiteralPath $StageDir -File | Where-Object { $_.Extension -notin @('.yaml', '.yml') } |
                Sort-Object Length -Descending | Select-Object -First 1
        }
        if (-not $installer) {
            $wingetError = ($r.Output | Select-Object -Last 2) -join ' | '
            Write-KitLog -Level WARN -Message ("{0} : winget download tentative {1}/{2} échouée (code {3}) {4}" -f $item.Name, $attempt, $script:MaxAttempts, $r.ExitCode, $wingetError)
            Get-ChildItem -LiteralPath $StageDir -Force | Remove-Item -Recurse -Force
            if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (5 * $attempt) }
        }
    }

    if ($installer) {
        $sha = Get-KitSha256 -Path $installer.FullName
        $yaml = Get-ChildItem -LiteralPath $StageDir -Filter '*.yaml' -File | Select-Object -First 1
        $known = @()
        if ($yaml) {
            $known = @(Select-String -LiteralPath $yaml.FullName -Pattern 'InstallerSha256:\s*([0-9A-Fa-f]{64})' -AllMatches |
                    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
        }
        if ($known.Count -gt 0 -and $sha -notin $known) { throw "$($installer.Name) : SHA256 différent du manifeste winget. Fichier refusé." }
        if ($known.Count -eq 0 -and $sha -ne $Plan.Source.Sha256) { throw "$($installer.Name) : SHA256 différent de celui publié par winget. Fichier refusé." }
        $sigInfo = Test-KitSignature -Path $installer.FullName -Signer (Get-KitValue $item 'Signer' '')
    }
    else {
        $fallback = Get-KitValue $item 'FallbackUrl' ''
        if (-not $fallback) { throw "winget download a échoué ($wingetError) et aucune URL éditeur de repli n'est définie." }
        Write-KitLog -Level WARN -Message ("{0} : repli sur le site officiel de l'éditeur." -f $item.Name)
        $ri = Get-KitRemoteInfo -Url $fallback
        $dest = Join-Path $StageDir $ri.FileName
        Invoke-KitHttpDownload -Url $fallback -Destination $dest -ExpectedLength $ri.Length
        # Sans SHA256 publié, la signature de l'éditeur est obligatoire
        $sigInfo = Test-KitSignature -Path $dest -Signer (Get-KitValue $item 'Signer' '') -Required
        $installer = Get-Item -LiteralPath $dest
        $sha = Get-KitSha256 -Path $dest
        $source = 'éditeur'
    }

    # Outil portable : décompressé dans app\ pour être lancé directement depuis la clé
    if ((Get-KitValue $item 'Extract' $false) -and $installer.Extension -eq '.zip') {
        Expand-KitPortable -StageDir $StageDir -ZipPath $installer.FullName
    }

    # Options silencieuses : celles du catalogue, complétées par celles du manifeste YAML
    $yamlSilent = ''
    $yaml2 = Get-ChildItem -LiteralPath $StageDir -Filter '*.yaml' -File | Select-Object -First 1
    if ($yaml2) {
        $m = Select-String -LiteralPath $yaml2.FullName -Pattern '^\s*Silent:\s*(.+)$' | Select-Object -First 1
        if ($m) { $yamlSilent = $m.Matches[0].Groups[1].Value.Trim().Trim("'").Trim('"') }
    }
    $silent = @(
        "Installation silencieuse de $($item.Name) $($Plan.Version)"
        ''
        ('Commande utilisée par le kit : "{0}" {1}' -f $installer.Name, (Get-KitValue $item 'SilentArgs' ''))
        ('Options silencieuses du manifeste winget : {0}' -f $(if ($yamlSilent) { $yamlSilent } else { '(non précisé, MSI : /qn)' }))
        ('Codes de retour acceptés : {0}' -f ((@(Get-KitValue $item 'SuccessCodes' @(0))) -join ', '))
    )
    Set-Content -LiteralPath (Join-Path $StageDir 'silent.txt') -Value $silent -Encoding UTF8

    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version   = $Plan.Version
        WingetId  = $item.WingetId
        Source    = $source
        Signature = $sigInfo
        Installer = $installer.Name
        Files     = @(@{ Name = $installer.Name; Sha256 = $sha; Length = $installer.Length; Url = $(if ($source -eq 'winget') { $Plan.Source.Url } else { $item.FallbackUrl }) })
    }
}

function Save-KitLinuxIso {
    <#
    .SYNOPSIS
        Télécharge une ISO Linux officielle (reprise), vérifie le SHA256 publié et l'image ISO.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir
    )
    $item = $Plan.Item
    $info = $Plan.Source
    $keep = @($info.FileName, "$($info.FileName).part", "$($info.FileName).part.src")
    Get-ChildItem -LiteralPath $StageDir -Force | Where-Object { $_.Name -notin $keep } | Remove-Item -Recurse -Force
    $dest = Join-Path $StageDir $info.FileName
    $len = -1
    if ($info.PSObject.Properties['Length']) { $len = [double]$info.Length }
    Invoke-KitHttpDownload -Url $info.Url -Destination $dest -ExpectedLength $len -SourceTag ("{0}|{1}" -f $info.FileName, $info.Sha256) -Agent $script:PlainAgent
    Test-KitIsoFile -Path $dest -ExpectedLength $len
    Write-KitLog -Message ("{0} : contrôle SHA256…" -f $info.FileName)
    $sha = Get-KitSha256 -Path $dest
    if ($sha -ne $info.Sha256) {
        Remove-Item -LiteralPath $dest -Force
        throw "$($info.FileName) : SHA256 différent de la liste d'empreintes officielle. Fichier supprimé."
    }
    Write-KitLog -Level OK -Message ("{0} vérifiée (SHA256 officiel)." -f $info.Label)
    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version   = $info.Label
        Label     = $info.Label
        Source    = $info.Url
        Installer = $info.FileName
        Files     = @(@{ Name = $info.FileName; Sha256 = $sha; Length = (Get-Item -LiteralPath $dest).Length; Url = $info.Url })
    }
}

function Save-KitGitHubItem {
    <#
    .SYNOPSIS
        Téléchargement depuis la dernière release stable GitHub, contrôle du SHA256 publié.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir
    )
    $item = $Plan.Item
    $info = $Plan.Source
    $keep = @($info.FileName, "$($info.FileName).part", "$($info.FileName).part.src")
    Get-ChildItem -LiteralPath $StageDir -Force | Where-Object { $_.Name -notin $keep } | Remove-Item -Recurse -Force
    $dest = Join-Path $StageDir $info.FileName
    Invoke-KitHttpDownload -Url $info.Url -Destination $dest -ExpectedLength $info.Length -SourceTag ("{0}|{1}" -f $info.Url, $info.Sha256)
    $sha = Get-KitSha256 -Path $dest
    if ($info.Sha256 -and $sha -ne $info.Sha256) { throw "$($info.FileName) : SHA256 différent de celui publié sur GitHub. Fichier refusé." }
    # Sans SHA256 publié, la signature devient la seule preuve d'origine
    $sig = Test-KitSignature -Path $dest -Signer (Get-KitValue $item 'Signer' '') -Required:(-not $info.Sha256)
    if (Get-KitValue $item 'Extract' $false) { Expand-KitPortable -StageDir $StageDir -ZipPath $dest }
    Set-Content -LiteralPath (Join-Path $StageDir 'silent.txt') -Encoding UTF8 -Value @(
        "Installation silencieuse de $($item.Name) $($info.Version)"
        ''
        ('Commande utilisée par le kit : "{0}" {1}' -f $info.FileName, (Get-KitValue $item 'SilentArgs' ''))
        ('Source : https://github.com/{0}/releases (dernière version stable)' -f $item.Repo)
    )
    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version   = $info.Version
        WingetId  = (Get-KitValue $item 'WingetId' '')
        Source    = "GitHub $($item.Repo)"
        Signature = $sig
        Installer = $info.FileName
        Files     = @(@{ Name = $info.FileName; Sha256 = $sha; Length = (Get-Item -LiteralPath $dest).Length; Url = $info.Url })
    }
}

function Save-KitUrlItem {
    <#
    .SYNOPSIS
        Téléchargement direct depuis le site officiel de l'éditeur (signature obligatoire).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir
    )
    $item = $Plan.Item
    $keep = @()
    foreach ($f in $Plan.Source) { $keep += $f.FileName; $keep += "$($f.FileName).part"; $keep += "$($f.FileName).part.src" }
    Get-ChildItem -LiteralPath $StageDir -Force | Where-Object { $_.Name -notin $keep } | Remove-Item -Recurse -Force

    $files = @(); $sigs = @()
    foreach ($f in $Plan.Source) {
        $dest = Join-Path $StageDir $f.FileName
        Invoke-KitHttpDownload -Url $f.Url -Destination $dest -ExpectedLength $f.Length -SourceTag ("{0}|{1}|{2}" -f $f.FinalUrl, $f.Length, $f.LastModified)
        if ($f.Sha256) {
            # Fichier officiel figé et non signé : l'empreinte fixée dans le profil fait foi
            if ((Get-KitSha256 -Path $dest) -ne $f.Sha256.ToLowerInvariant()) { Remove-Item -LiteralPath $dest -Force; throw "$($f.FileName) : SHA256 différent de l'empreinte attendue. Fichier refusé." }
            $sigs += ("{0} : SHA256 conforme à l'empreinte fixée" -f $f.FileName)
        }
        else { $sigs += ("{0} : {1}" -f $f.FileName, (Test-KitSignature -Path $dest -Signer (Get-KitValue $item 'Signer' '') -Required)) }
        $files += @{ Name = $f.FileName; Sha256 = (Get-KitSha256 -Path $dest); Length = (Get-Item -LiteralPath $dest).Length; Url = $f.Url; FinalUrl = $f.FinalUrl; LastModified = $f.LastModified }
    }
    $installer = Get-KitValue $item 'Installer' $files[0].Name
    Set-Content -LiteralPath (Join-Path $StageDir 'silent.txt') -Encoding UTF8 -Value @(
        "Installation silencieuse de $($item.Name)"
        ''
        ('Commande utilisée par le kit : "{0}" {1}' -f $installer, ((Get-KitValue $item 'SilentArgs' '') -replace '\{DIR\}', '<dossier du logiciel>'))
        ('Codes de retour acceptés : {0}' -f ((@(Get-KitValue $item 'SuccessCodes' @(0))) -join ', '))
    )
    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version   = $Plan.Version
        WingetId  = (Get-KitValue $item 'WingetId' '')
        Source    = 'éditeur'
        Signature = ($sigs -join ' ; ')
        Installer = $installer
        Files     = $files
    }
}

function Save-KitWindowsIso {
    <#
    .SYNOPSIS
        Télécharge l'ISO Windows 11 officielle (lien Fido), avec reprise, puis la vérifie.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir
    )
    $item = $Plan.Item
    $dest = Join-Path $StageDir $item.FileName
    $tag = "{0}|{1}" -f $Plan.Source.OriginalName, $Plan.Source.Length
    # Une ISO complète déposée à la main est acceptée si elle a exactement la taille attendue
    if (-not ((Test-Path -LiteralPath $dest) -and [double](Get-Item -LiteralPath $dest).Length -eq [double]$Plan.Source.Length)) {
        Invoke-KitHttpDownload -Url $Plan.Source.Url -Destination $dest -ExpectedLength $Plan.Source.Length -SourceTag $tag
    }
    Test-KitIsoFile -Path $dest -ExpectedLength $Plan.Source.Length
    Write-KitLog -Message 'Calcul du SHA256 de l''ISO (à comparer avec celui publié par Microsoft)…'
    $sha = Get-KitSha256 -Path $dest
    Write-KitLog -Level OK -Message ("ISO vérifiée : {0} — SHA256 {1}" -f $Plan.Source.OriginalName, $sha.ToUpperInvariant())
    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version      = $Plan.Version
        OriginalName = $Plan.Source.OriginalName
        Length       = $Plan.Source.Length
        Sha256       = $sha
        Source       = 'Microsoft (lien officiel obtenu via Fido)'
    }
}

function Save-KitOffice {
    <#
    .SYNOPSIS
        Télécharge Microsoft 365 Apps hors ligne avec l'Office Deployment Tool.
    .DESCRIPTION
        1) setup.exe (ODT) depuis le CDN officiel Office, signature Microsoft obligatoire ;
        2) config de téléchargement = office-config.xml + SourcePath (cache) + Version figée ;
        3) setup.exe /download (incrémental : un téléchargement interrompu reprend) ;
        4) contrôle : Office\Data\<version>\ et v64.cab présents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $StageDir,
        [Parameter(Mandatory)] [string] $OfficeConfigPath,
        [Parameter(Mandatory)] [string] $ToolsDir
    )
    $item = $Plan.Item
    $version = $Plan.Version

    # Nettoyage des restes d'une autre version dans la zone de préparation
    $dataDir = Join-Path $StageDir 'Office\Data'
    if (Test-Path -LiteralPath $dataDir) {
        Get-ChildItem -LiteralPath $dataDir -Directory | Where-Object { $_.Name -ne $version } | Remove-Item -Recurse -Force
    }
    Remove-Item -LiteralPath (Join-Path $StageDir "$($item.Name).source.json") -Force -ErrorAction SilentlyContinue

    $setup = Join-Path $StageDir 'setup.exe'
    $ri = Get-KitRemoteInfo -Url $item.OdtUrl
    Invoke-KitHttpDownload -Url $item.OdtUrl -Destination $setup -ExpectedLength $ri.Length -SourceTag ("{0}|{1}" -f $ri.Length, $ri.LastModified)
    $sig = Test-KitSignature -Path $setup -Signer $item.Signer -Required

    # config.xml d'installation : sans SourcePath (setup.exe prend le dossier Office\ voisin),
    # avec la version téléchargée figée (le dossier ne contient que v64_<version>.cab)
    [xml]$inst = Get-Content -LiteralPath $OfficeConfigPath -Raw -Encoding UTF8
    $inst.Configuration.Add.SetAttribute('Version', $version)
    $officeLang = [string](Get-KitValue $item 'OfficeLanguage' 'fr-fr')
    foreach ($l in @($inst.Configuration.Add.Product.Language)) { $l.SetAttribute('ID', $officeLang) }
    $inst.Save((Join-Path $StageDir 'config.xml'))

    # config de téléchargement (hors zone de préparation : elle ne va pas sur la clé)
    [xml]$cfg = Get-Content -LiteralPath $OfficeConfigPath -Raw -Encoding UTF8
    $add = $cfg.Configuration.Add
    $add.SetAttribute('SourcePath', $StageDir)
    $add.SetAttribute('Version', $version)
    foreach ($l in @($add.Product.Language)) { $l.SetAttribute('ID', $officeLang) }
    $dlConfig = Join-Path $ToolsDir 'office-download.xml'
    $cfg.Save($dlConfig)

    $ok = $false
    for ($attempt = 1; $attempt -le $script:MaxAttempts -and -not $ok; $attempt++) {
        Write-KitLog -Message ("Office {0} : téléchargement ODT (tentative {1}/{2}), plusieurs Go, patience…" -f $version, $attempt, $script:MaxAttempts)
        # Dossier de travail = zone de préparation : ODT y dépose Office\ même s'il ignore SourcePath
        $p = Start-Process -FilePath $setup -ArgumentList @('/download', ('"{0}"' -f $dlConfig)) -WorkingDirectory $StageDir -Wait -PassThru -NoNewWindow
        $cab = @(Get-ChildItem -LiteralPath $dataDir -Filter 'v64*.cab' -File -ErrorAction SilentlyContinue)
        if ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $dataDir $version)) -and $cab.Count -gt 0) { $ok = $true }
        else {
            Write-KitLog -Level WARN -Message ("ODT a retourné le code {0}. Journaux ODT : %TEMP% (fichiers <PC>-*.log)." -f $p.ExitCode)
            if ($attempt -lt $script:MaxAttempts) { Start-Sleep -Seconds (10 * $attempt) }
        }
    }
    if (-not $ok) { throw "Office Deployment Tool n'a pas pu télécharger Office $version." }

    Write-KitSourceFile -StageDir $StageDir -Item $item -Data @{
        Version   = $version
        ProductId = $item.ProductId
        Language  = $officeLang
        Channel   = 'Current'
        Signature = "setup.exe : $sig"
        Source    = 'Microsoft Office CDN (Office Deployment Tool)'
    }
}

function Save-KitPlan {
    <#
    .SYNOPSIS
        Télécharge et vérifie un élément dans sa zone de préparation (cache\<Nom>\).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Plan,
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $ToolsDir,
        [Parameter(Mandatory)] [string] $OfficeConfigPath
    )
    $stage = Get-KitStageDir -CacheRoot $CacheRoot -Name $Plan.Name
    switch ($Plan.Item.Type) {
        'Winget'     { Save-KitWingetItem -Plan $Plan -StageDir $stage }
        'Url'        { Save-KitUrlItem -Plan $Plan -StageDir $stage }
        'GitHub'     { Save-KitGitHubItem -Plan $Plan -StageDir $stage }
        'LinuxIso'   { Save-KitLinuxIso -Plan $Plan -StageDir $stage }
        'WindowsIso' { Save-KitWindowsIso -Plan $Plan -StageDir $stage }
        'Office'     { Save-KitOffice -Plan $Plan -StageDir $stage -OfficeConfigPath $OfficeConfigPath -ToolsDir $ToolsDir }
        default      { throw "Type d'élément inconnu : $($Plan.Item.Type)" }
    }
    return $stage
}

Export-ModuleMember -Function Initialize-KitNetwork, Initialize-KitWinget, Set-KitKeepAwake, Get-KitValue, Get-KitSha256, Get-KitRemoteInfo,
    Invoke-KitHttpDownload, Test-KitSignature, Test-KitIsoFile, Get-KitKeySource, Get-KitStageDir,
    Test-KitStageComplete, Get-KitWingetInfo, Get-KitWindowsIsoUrl, Get-KitOfficeVersion,
    Resolve-KitPlan, Save-KitPlan, Set-KitSignaturePolicy, Get-KitGitHubRelease, Expand-KitPortable,
    Resolve-KitLinuxIso, Find-KitChecksum
