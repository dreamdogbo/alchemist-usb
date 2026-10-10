#
# windows11-bureautique.psd1 — Profil « Poste bureautique Windows 11 » (fonctionne hors ligne)
#
# Un profil décrit un type de clé. Build-Kit.ps1 liste les fichiers de config\profils\
# et propose de choisir (assistant) ou prend -Profil <nom du fichier sans extension>.
#
# Champs de chaque élément de « Items » :
#   Name            : nom court, unique, utilisé par -Only et comme nom de dossier.
#   Category        : regroupement affiché dans les menus (Système, Bureautique, Navigateur…).
#   Type            : WindowsIso | LinuxIso | Office | Winget | Url | GitHub
#   Distro          : (Type LinuxIso) Ubuntu | Mint | Debian | Fedora — dernière version stable
#   Mode            : Auto (installé par la post-installation) | Manuel (outil disponible
#                     sur la clé, lancé à la demande : pilotes, diagnostic…). Défaut : Auto.
#   Priority        : 1 = le plus important. En cas de manque de place, les priorités
#                     les plus hautes (chiffre le plus grand) sont ignorées en premier.
#   Default         : $false = non coché par défaut dans l'assistant (défaut : $true).
#   TargetDir       : dossier de destination sur la clé (relatif à la racine).
#   EstimatedSizeMB : valeur de repli si la taille réelle ne peut pas être lue (HEAD).
#   WingetId        : identifiant winget (téléchargement prioritaire + repli en ligne sur le poste).
#   Architecture    : x64 ou x86 (passé à winget). Vide = neutre (outils portables).
#   InstallerType   : (optionnel) type d'installeur winget à forcer (msi, wix, exe…).
#   Scope           : (optionnel) portée winget à forcer (machine ou user).
#   Repo            : (Type GitHub) « propriétaire/dépôt » ; dernière version STABLE uniquement.
#   AssetPattern    : (Type GitHub) regex du fichier à prendre dans la release.
#   Files           : (Type Url) liste de @{ Url = … ; FileName = … (optionnel) }.
#   FallbackUrl     : (optionnel) URL officielle de l'éditeur si winget échoue.
#   Extract         : $true = archive zip décompressée dans <dossier>\app (outil portable).
#   Launcher        : (outil portable) motif du programme à lancer dans <dossier>\app.
#   Signer          : expression régulière attendue dans le sujet du certificat Authenticode
#                     ('' = pas d'exigence d'éditeur, le SHA256 publié fait foi).
#                     La vérification est désactivable : Build-Kit.ps1 -SansVerifSignature.
#   Installer       : (optionnel) fichier à lancer quand l'élément contient plusieurs fichiers.
#   SilentArgs      : arguments d'installation silencieuse. Jeton {DIR} = dossier de l'élément.
#   SuccessCodes    : codes de retour considérés comme un succès.
#   Detection       : comment savoir si le logiciel est déjà installé sur le poste :
#                       'reg:<regex>'   -> DisplayName dans les clés Uninstall
#                       'appx:<nom>'    -> paquet AppX provisionné / installé
#                       'c2r:<produit>' -> Office Click-to-Run
#                       'file:<chemin>' -> fichier présent (variables %ProgramData%… acceptées)
#                       ''              -> toujours lancer (installeur idempotent, ex. VC++)
#   Order           : ordre d'installation sur le poste (petit = d'abord).
#
@{
    # ---------------------------------------------------------------- description du profil
    Nom          = 'Windows 11 — Bureautique'
    Usage        = 'Bureautique'
    Ordre        = 1
    Description  = 'Windows 11 x64 (FR, EN, ES, DE, PT) + Microsoft 365 ou suite gratuite + logiciels + outils technicien, 100 % hors ligne'
    Systeme      = 'Windows'
    KitVersion   = '2.0'

    # Marge de sécurité à laisser libre sur la clé (Mo)
    MarginMB     = 2048

    # Libellé de volume exigé pour la clé
    VolumeLabel  = 'Ventoy'

    # Script Fido (dépôt GitHub officiel de Pete Batard)
    FidoUrl      = 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1'

    # Configuration Office Deployment Tool (relative à config\)
    OfficeConfig = 'office-config.xml'

    # Contenu copié à la racine de la clé (relatif au dossier du kit)
    Payload      = 'payload/windows'

    # Fuseau horaire appliqué à l'installation et par la post-installation (Id Windows)
    TimeZone     = 'Greenwich Standard Time'

    # Langue du CONTENU de la clé (ISO Windows, Office, clavier). Choix : Build-Kit -Langue <code>
    #   FidoLang  : nom de langue Microsoft attendu par Fido (regex)
    #   Office    : langue Office (ODT)
    #   UILang    : langue d'installation Windows ; InputLocale : clavier (unattend)
    LangueDefaut = 'fr'
    Langues      = @{
        fr = @{ Label = 'Français';             FidoLang = '^French$';               Office = 'fr-fr'; UILang = 'fr-FR'; InputLocale = '040c:0000040c'; IsoSuffix = 'FR' }
        en = @{ Label = 'English (US)';         FidoLang = '^English$';              Office = 'en-us'; UILang = 'en-US'; InputLocale = '0409:00000409'; IsoSuffix = 'EN' }
        es = @{ Label = 'Español';              FidoLang = '^Spanish$';              Office = 'es-es'; UILang = 'es-ES'; InputLocale = '0c0a:0000040a'; IsoSuffix = 'ES' }
        de = @{ Label = 'Deutsch';              FidoLang = '^German$';               Office = 'de-de'; UILang = 'de-DE'; InputLocale = '0407:00000407'; IsoSuffix = 'DE' }
        pt = @{ Label = 'Português (Brasil)';   FidoLang = '^Brazilian Portuguese$'; Office = 'pt-br'; UILang = 'pt-BR'; InputLocale = '0416:00000416'; IsoSuffix = 'PT' }
    }

    Items = @(
        # ================================================================== Système
        @{
            Name            = 'Windows11'
            Category        = 'Système'
            Type            = 'WindowsIso'
            Priority        = 1
            TargetDir       = 'ISO'
            FileName        = 'Windows11_{LANG}_x64.iso'   # {LANG} = IsoSuffix de la langue choisie
            EstimatedSizeMB = 8700
            FidoWin         = '11'
            FidoRel         = 'Latest'
            FidoEd          = 'Pro'          # ISO multi-éditions « Home/Pro/Edu »
            FidoLang        = '^French$'     # remplacé selon -Langue (regex : exclut « French Canadian »)
            FidoArch        = 'x64'
        }

        # Systèmes supplémentaires (multiboot Ventoy) : décochés par défaut, à cocher selon l'usage.
        # Dernière version stable, SHA256 vérifié avec la liste d'empreintes officielle.
        @{
            Name = 'Ubuntu'; Category = 'Systèmes supplémentaires'; Type = 'LinuxIso'; Distro = 'Ubuntu'; Priority = 7; Default = $false
            TargetDir = 'ISO/Linux/Ubuntu'; EstimatedSizeMB = 6200
        }
        @{
            Name = 'LinuxMint'; Category = 'Systèmes supplémentaires'; Type = 'LinuxIso'; Distro = 'Mint'; Priority = 7; Default = $false
            TargetDir = 'ISO/Linux/Mint'; EstimatedSizeMB = 3000
        }
        @{
            Name = 'Debian'; Category = 'Systèmes supplémentaires'; Type = 'LinuxIso'; Distro = 'Debian'; Priority = 7; Default = $false
            TargetDir = 'ISO/Linux/Debian'; EstimatedSizeMB = 3700
        }
        @{
            Name = 'Fedora'; Category = 'Systèmes supplémentaires'; Type = 'LinuxIso'; Distro = 'Fedora'; Priority = 7; Default = $false
            TargetDir = 'ISO/Linux/Fedora'; EstimatedSizeMB = 2800
        }

        # ================================================================== Bureautique
        @{
            Name            = 'Office365'
            Category        = 'Bureautique'
            Type            = 'Office'
            Priority        = 2
            TargetDir       = 'Bureautique/Office365'
            EstimatedSizeMB = 3700
            OdtUrl          = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
            # Descripteur de version du Current Channel (CDN Office officiel)
            ChannelCabUrl   = 'https://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60/Office/Data/v64.cab'
            ProductId       = 'O365ProPlusRetail'
            Signer          = 'Microsoft Corporation'
            Detection       = 'c2r:O365ProPlusRetail'
            Order           = 30
        }

        # Suites bureautiques GRATUITES (sans licence) : alternatives à Office, décochées par défaut.
        # Dans l'assistant : décocher Office365 et cocher l'une d'elles.
        @{
            Name = 'LibreOffice'; Category = 'Bureautique'; Type = 'Winget'; Priority = 2; Default = $false; TargetDir = 'Bureautique/LibreOffice'
            WingetId = 'TheDocumentFoundation.LibreOffice'; Architecture = 'x64'; InstallerType = 'msi'; EstimatedSizeMB = 360
            Signer = 'The Document Foundation'
            # MSI multilingue : l'interface suit la langue de Windows
            SilentArgs = '/qn /norestart ALLUSERS=1 CREATEDESKTOPLINK=1 RebootYesNo=No'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^LibreOffice \d'; Order = 31
        }
        @{
            Name = 'ONLYOFFICE'; Category = 'Bureautique'; Type = 'Winget'; Priority = 2; Default = $false; TargetDir = 'Bureautique/ONLYOFFICE'
            WingetId = 'ONLYOFFICE.DesktopEditors'; Architecture = 'x64'; EstimatedSizeMB = 330
            Signer = 'Ascensio System'
            SilentArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-'; SuccessCodes = @(0)
            Detection = 'reg:^ONLYOFFICE'; Order = 32
        }

        # ================================================================== Runtimes
        @{
            Name = 'VCRedist_x64'; Category = 'Runtime'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/VCRedist_x64'
            WingetId = 'Microsoft.VCRedist.2015+.x64'; Architecture = 'x64'; EstimatedSizeMB = 25
            Signer = 'Microsoft Corporation'
            SilentArgs = '/install /quiet /norestart'; SuccessCodes = @(0, 1638, 3010, 1641)
            Detection = ''; Order = 10
        }
        @{
            Name = 'VCRedist_x86'; Category = 'Runtime'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/VCRedist_x86'
            WingetId = 'Microsoft.VCRedist.2015+.x86'; Architecture = 'x86'; EstimatedSizeMB = 15
            Signer = 'Microsoft Corporation'
            SilentArgs = '/install /quiet /norestart'; SuccessCodes = @(0, 1638, 3010, 1641)
            Detection = ''; Order = 11
        }
        @{
            Name = 'DotNetDesktop'; Category = 'Runtime'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/DotNetDesktop'
            WingetId = 'Microsoft.DotNet.DesktopRuntime.10'; Architecture = 'x64'; EstimatedSizeMB = 60
            Signer = 'Microsoft Corporation'
            SilentArgs = '/install /quiet /norestart'; SuccessCodes = @(0, 1638, 3010, 1641)
            Detection = 'reg:^Microsoft Windows Desktop Runtime - 10\..*\(x64\)'; Order = 12
        }

        # ================================================================== Essentiels
        @{
            Name = 'Chrome'; Category = 'Navigateur'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/Chrome'
            WingetId = 'Google.Chrome'; Architecture = 'x64'; EstimatedSizeMB = 165
            FallbackUrl = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
            Signer = 'Google LLC'
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Google Chrome$'; Order = 40
        }
        @{
            Name = 'Firefox'; Category = 'Navigateur'; Type = 'Url'; Priority = 4; TargetDir = 'Logiciels/Firefox'
            WingetId = 'Mozilla.Firefox.fr'; EstimatedSizeMB = 90
            # Le paquet winget français ne propose pas de MSI : lien officiel Mozilla
            Files = @( @{ Url = 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=fr' } )
            Signer = 'Mozilla Corporation'
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Mozilla Firefox'; Order = 41
        }
        @{
            Name = 'AcrobatReader'; Category = 'PDF'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/AcrobatReader'
            WingetId = 'Adobe.Acrobat.Reader.64-bit'; Architecture = 'x64'; EstimatedSizeMB = 830
            Signer = 'Adobe'
            SilentArgs = '/sAll /rs /msi EULA_ACCEPT=YES'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Adobe Acrobat'; Order = 42
        }
        @{
            Name = '7Zip'; Category = 'Utilitaire'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/7Zip'
            WingetId = '7zip.7zip'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 2
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^7-Zip'; Order = 43
        }
        @{
            Name = 'VLC'; Category = 'Multimédia'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/VLC'
            WingetId = 'VideoLAN.VLC'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 60
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^VLC media player'; Order = 44
        }

        # ================================================================== Le reste
        @{
            Name = 'PDF24'; Category = 'PDF'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/PDF24'
            WingetId = 'geeksoftwareGmbH.PDF24Creator'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 500
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^PDF24 Creator'; Order = 50
        }
        @{
            Name = 'NotepadPlusPlus'; Category = 'Utilitaire'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/NotepadPlusPlus'
            WingetId = 'Notepad++.Notepad++'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 7
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Notepad\+\+'; Order = 51
        }
        @{
            Name = 'ShareX'; Category = 'Utilitaire'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/ShareX'
            WingetId = 'ShareX.ShareX'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 135
            Signer = ''
            # /ALLUSERS : installation pour tous les utilisateurs du poste (même fichier que la version « user »)
            SilentArgs = '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NORUN /ALLUSERS'; SuccessCodes = @(0)
            Detection = 'reg:^ShareX'; Order = 52
        }
        @{
            Name = 'Teams'; Category = 'Communication'; Type = 'Url'; Priority = 5; TargetDir = 'Logiciels/Teams'
            WingetId = 'Microsoft.Teams'; EstimatedSizeMB = 280
            Files = @(
                @{ Url = 'https://go.microsoft.com/fwlink/?linkid=2243204'; FileName = 'teamsbootstrapper.exe' }
                @{ Url = 'https://go.microsoft.com/fwlink/?linkid=2196106'; FileName = 'MSTeams-x64.msix' }
            )
            Signer = 'Microsoft Corporation'
            Installer = 'teamsbootstrapper.exe'
            SilentArgs = '-p -o "{DIR}\MSTeams-x64.msix"'; SuccessCodes = @(0)
            Detection = 'appx:MSTeams'; Order = 53
        }
        @{
            Name = 'Zoom'; Category = 'Communication'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/Zoom'
            WingetId = 'Zoom.Zoom'; Architecture = 'x64'; InstallerType = 'msi'; EstimatedSizeMB = 210
            FallbackUrl = 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'
            Signer = 'Zoom'
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Zoom( Workplace)?'; Order = 54
        }
        @{
            # PDFCraft : atelier PDF open source (Rust). Dernière release STABLE GitHub, SHA256 publié.
            Name = 'PDFCraft'; Category = 'PDF'; Type = 'GitHub'; Priority = 5; TargetDir = 'Logiciels/PDFCraft'
            Repo = 'storytold/pdfcraft'; AssetPattern = '^pdfcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 65
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:(?i)^pdfcraft'; Order = 55
        }
        @{
            # Chocolatey : gestionnaire de paquets (MSI officiel, installation hors ligne)
            Name = 'Chocolatey'; Category = 'Gestion de paquets'; Type = 'GitHub'; Priority = 5; TargetDir = 'Logiciels/Chocolatey'
            Repo = 'chocolatey/choco'; AssetPattern = '^chocolatey-[\d.]+\.msi$'; EstimatedSizeMB = 7
            Signer = 'Chocolatey'
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'file:%ProgramData%\chocolatey\choco.exe'; Order = 60
        }
        @{
            # Chocolatey GUI : interface graphique de Chocolatey (après Chocolatey)
            Name = 'ChocolateyGUI'; Category = 'Gestion de paquets'; Type = 'GitHub'; Priority = 5; TargetDir = 'Logiciels/ChocolateyGUI'
            Repo = 'chocolatey/ChocolateyGUI'; AssetPattern = '^ChocolateyGUI\.msi$'; EstimatedSizeMB = 21
            Signer = 'Chocolatey'
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^Chocolatey GUI'; Order = 61
        }

        # ================================================================== Sécurité
        @{
            # ClamAV : antivirus open source le plus répandu (Cisco Talos, GPL-2.0), analyse à la demande.
            # La protection en temps réel reste Microsoft Defender (intégré à Windows 11) : on ne le remplace pas.
            Name = 'ClamAV'; Category = 'Sécurité'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/ClamAV'
            WingetId = 'Cisco.ClamAV'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 60
            Signer = ''
            SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641)
            Detection = 'reg:^ClamAV'; Order = 62
            PostAction = 'ClamAVConfig'   # crée freshclam.conf / clamd.conf, met à jour les signatures si Internet
        }

        # ================================================================== Création (optionnel)
        # Références éprouvées (open source) : décochées par défaut, à cocher selon les besoins.
        @{ Name = 'GIMP'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/GIMP'
           WingetId = 'GIMP.GIMP.3'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 330; Signer = ''
           SilentArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS'; SuccessCodes = @(0); Detection = 'reg:^GIMP'; Order = 70 }
        @{ Name = 'Inkscape'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/Inkscape'
           WingetId = 'Inkscape.Inkscape'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 130; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Inkscape'; Order = 71 }
        @{ Name = 'Krita'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/Krita'
           WingetId = 'KDE.Krita'; Architecture = 'x64'; EstimatedSizeMB = 160; Signer = ''
           SilentArgs = '/S'; SuccessCodes = @(0); Detection = 'reg:^Krita'; Order = 72 }
        @{ Name = 'Kdenlive'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/Kdenlive'
           WingetId = 'KDE.Kdenlive'; Architecture = 'x64'; EstimatedSizeMB = 160; Signer = ''
           SilentArgs = '/S'; SuccessCodes = @(0); Detection = 'reg:^Kdenlive'; Order = 73 }
        @{ Name = 'OBSStudio'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/OBSStudio'
           WingetId = 'OBSProject.OBSStudio'; Architecture = 'x64'; EstimatedSizeMB = 150; Signer = ''
           SilentArgs = '/S'; SuccessCodes = @(0); Detection = 'reg:^OBS Studio'; Order = 74 }
        @{ Name = 'Audacity'; Category = 'Création'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/Audacity'
           WingetId = 'Audacity.Audacity'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 60; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Audacity'; Order = 75 }

        # ================================================================== Suite ArtCraft (même éditeur que PDFCraft)
        # Alternatives open source (Rust) à Photoshop, Illustrator, Premiere, Lightroom, After Effects,
        # InDesign. Encore jeunes (versions 0.x) : décochées par défaut. Dernière release STABLE GitHub.
        @{ Name = 'PhotoCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/PhotoCraft'
           Repo = 'storytold/photocraft'; AssetPattern = '^photocraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 80; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^photocraft'; Order = 80 }
        @{ Name = 'VectorCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/VectorCraft'
           Repo = 'storytold/vectorcraft'; AssetPattern = '^vectorcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 80; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^vectorcraft'; Order = 81 }
        @{ Name = 'FilmCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/FilmCraft'
           Repo = 'storytold/filmcraft'; AssetPattern = '^filmcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 90; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^filmcraft'; Order = 82 }
        @{ Name = 'LightCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/LightCraft'
           Repo = 'storytold/lightcraft'; AssetPattern = '^lightcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 80; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^lightcraft'; Order = 83 }
        @{ Name = 'EffectCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/EffectCraft'
           Repo = 'storytold/effectcraft'; AssetPattern = '^effectcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 80; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^effectcraft'; Order = 84 }
        @{ Name = 'DesignCraft'; Category = 'Création (ArtCraft)'; Type = 'GitHub'; Priority = 6; Default = $false; TargetDir = 'Logiciels/DesignCraft'
           Repo = 'storytold/designcraft'; AssetPattern = '^designcraft-[\d.]+-windows-x64\.msi$'; EstimatedSizeMB = 80; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:(?i)^designcraft'; Order = 85 }

        # ================================================================== Outils technicien (Mode Manuel)
        @{
            # Snappy Driver Installer Origin : pilotes (open source GPLv3, portable, hors ligne)
            Name = 'SDIO'; Category = 'Outil technicien'; Mode = 'Manuel'; Type = 'Winget'; Priority = 6; TargetDir = 'Logiciels/SDIO'
            WingetId = 'GlennDelahoy.SnappyDriverInstallerOrigin'; Architecture = ''; EstimatedSizeMB = 8
            Extract = $true; Launcher = 'SDIO_x64*.exe'
            Signer = ''
            Detection = ''; Order = 90
        }
        @{
            Name = 'CrystalDiskInfo'; Category = 'Outil technicien'; Mode = 'Manuel'; Type = 'Winget'; Priority = 6; TargetDir = 'Logiciels/CrystalDiskInfo'
            WingetId = 'CrystalDewWorld.CrystalDiskInfo'; Architecture = ''; EstimatedSizeMB = 6
            Signer = ''
            SilentArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-'; SuccessCodes = @(0)
            Detection = 'reg:^CrystalDiskInfo'; Order = 91
        }
        @{
            Name = 'HWiNFO'; Category = 'Outil technicien'; Mode = 'Manuel'; Type = 'Winget'; Priority = 6; TargetDir = 'Logiciels/HWiNFO'
            WingetId = 'REALiX.HWiNFO'; Architecture = 'x64'; EstimatedSizeMB = 12
            Signer = ''
            SilentArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-'; SuccessCodes = @(0)
            Detection = 'reg:^HWiNFO'; Order = 92
        }
    )
}
