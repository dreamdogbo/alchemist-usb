#
# linux-bureautique.psd1 — Profil « Linux — Bureautique »
#
# Sur la clé : les distributions choisies (Ubuntu LTS par défaut, Linux Mint, Debian, Fedora…, ISO
# officielles, SHA256 officiels) + le dossier linux/ (installer-poste.sh) qui installe la stack après
# l'installation, quelle que soit la distribution (familles Debian/Ubuntu et Fedora).
# La stack (logiciels) est choisie sur le poste : voir payload/linux/linux/installer-poste.sh.
# Champs des éléments : voir l'en-tête de windows11-bureautique.psd1.
#
@{
    Nom          = 'Linux — Bureautique'
    Systeme      = 'Linux'
    Usage        = 'Bureautique'
    Ordre        = 1
    Description  = 'Ubuntu LTS, Mint, Debian ou Fedora + Microsoft 365 de bureau intégral (LinOffice), ONLYOFFICE, LibreOffice, Chrome, Edge, PDFCraft, Zoom, sécurité, sauvegarde'
    KitVersion   = '2.0'
    MarginMB     = 1024
    VolumeLabel  = 'Ventoy'
    Payload      = 'payload/linux'
    # Fuseau horaire appliqué par la post-installation (identifiant Linux)
    TimeZone     = 'Africa/Abidjan'

    # Pour l'ISO Windows facultative (double démarrage, dépannage)
    FidoUrl      = 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1'
    LangueDefaut = 'fr'
    Langues      = @{
        fr = @{ Label = 'Français';           FidoLang = '^French$';               Office = 'fr-fr'; UILang = 'fr-FR'; InputLocale = '040c:0000040c'; IsoSuffix = 'FR' }
        en = @{ Label = 'English (US)';       FidoLang = '^English$';              Office = 'en-us'; UILang = 'en-US'; InputLocale = '0409:00000409'; IsoSuffix = 'EN' }
        es = @{ Label = 'Español';            FidoLang = '^Spanish$';              Office = 'es-es'; UILang = 'es-ES'; InputLocale = '0c0a:0000040a'; IsoSuffix = 'ES' }
        de = @{ Label = 'Deutsch';            FidoLang = '^German$';               Office = 'de-de'; UILang = 'de-DE'; InputLocale = '0407:00000407'; IsoSuffix = 'DE' }
        pt = @{ Label = 'Português (Brasil)'; FidoLang = '^Brazilian Portuguese$'; Office = 'pt-br'; UILang = 'pt-BR'; InputLocale = '0416:00000416'; IsoSuffix = 'PT' }
    }

    Items = @(
        # ================================================================== Versions (cases à cocher)
        @{ Name = 'Ubuntu'; Category = 'Système'; Type = 'LinuxIso'; Distro = 'Ubuntu'; Priority = 1
           TargetDir = 'ISO/Linux/Ubuntu'; EstimatedSizeMB = 6200 }
        @{ Name = 'Ubuntu2404'; Category = 'Système'; Type = 'LinuxIso'; Distro = 'Ubuntu'; Series = '24.04'; Priority = 7; Default = $false
           TargetDir = 'ISO/Linux/Ubuntu-24.04'; EstimatedSizeMB = 6100 }
        @{ Name = 'LinuxMint'; Category = 'Système'; Type = 'LinuxIso'; Distro = 'Mint'; Priority = 7; Default = $false
           TargetDir = 'ISO/Linux/Mint'; EstimatedSizeMB = 3000 }
        @{ Name = 'Debian'; Category = 'Système'; Type = 'LinuxIso'; Distro = 'Debian'; Priority = 7; Default = $false
           TargetDir = 'ISO/Linux/Debian'; EstimatedSizeMB = 3700 }
        @{ Name = 'Fedora'; Category = 'Système'; Type = 'LinuxIso'; Distro = 'Fedora'; Priority = 7; Default = $false
           TargetDir = 'ISO/Linux/Fedora'; EstimatedSizeMB = 2800 }
        @{ Name = 'Windows11'; Category = 'Système'; Type = 'WindowsIso'; Priority = 8; Default = $false
           TargetDir = 'ISO'; FileName = 'Windows11_{LANG}_x64.iso'; EstimatedSizeMB = 8700
           FidoWin = '11'; FidoRel = 'Latest'; FidoEd = 'Pro'; FidoLang = '^French$'; FidoArch = 'x64' }
    )
}
