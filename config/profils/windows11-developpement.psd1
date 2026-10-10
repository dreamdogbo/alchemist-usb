#
# windows11-developpement.psd1 — Profil « Windows 11 — Développement »
#
# Hérite du profil bureautique (Windows 11, Office ou suite gratuite, navigateurs, PDF, outils…)
# et ajoute la stack de développement. Champs : voir l'en-tête de windows11-bureautique.psd1.
#
@{
    Herite      = 'windows11-bureautique'
    Nom         = 'Windows 11 — Développement'
    Usage       = 'Developpement'
    Ordre       = 2
    Description = 'Bureautique + VS Code, Git/GitHub, WSL 2, Docker Desktop, Python, Node.js, Java, .NET, Go, outils API et bases de données'

    # La création graphique est souvent utile aux développeurs front : proposée cochée
    ParDefaut   = @('Inkscape', 'GIMP')

    Items = @(
        # ================================================================== Éditeurs et terminal
        @{ Name = 'VSCode'; Category = 'Développement'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/VSCode'
           WingetId = 'Microsoft.VisualStudioCode'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 110; Signer = 'Microsoft Corporation'
           SilentArgs = '/VERYSILENT /NORESTART /SP- /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
           SuccessCodes = @(0); Detection = 'reg:^Microsoft Visual Studio Code'; Order = 100 }
        @{ Name = 'PowerShell7'; Category = 'Développement'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/PowerShell7'
           WingetId = 'Microsoft.PowerShell'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 110; Signer = 'Microsoft Corporation'
           SilentArgs = '/qn /norestart ADD_PATH=1 ENABLE_PSREMOTING=0 REGISTER_MANIFEST=1'; SuccessCodes = @(0, 3010, 1641)
           Detection = 'reg:^PowerShell 7'; Order = 101 }

        # ================================================================== Git
        @{ Name = 'Git'; Category = 'Git'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/Git'
           WingetId = 'Git.Git'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 70; Signer = ''
           SilentArgs = '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES'; SuccessCodes = @(0)
           Detection = 'reg:^Git( version|$)'; Order = 102 }
        @{ Name = 'GitHubCLI'; Category = 'Git'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/GitHubCLI'
           WingetId = 'GitHub.cli'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 15; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^GitHub CLI'; Order = 103 }
        @{ Name = 'GitHubDesktop'; Category = 'Git'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/GitHubDesktop'
           WingetId = 'GitHub.GitHubDesktop'; Architecture = 'x64'; EstimatedSizeMB = 180; Signer = ''
           SilentArgs = '-s'; SuccessCodes = @(0); Detection = 'reg:^GitHub Desktop'; Order = 104 }

        # ================================================================== Conteneurs et virtualisation
        @{ Name = 'WSL'; Category = 'Conteneurs'; Type = 'GitHub'; Priority = 3; TargetDir = 'Logiciels/WSL'
           Repo = 'microsoft/WSL'; AssetPattern = '^wsl\.[\d.]+\.x64\.msi$'; EstimatedSizeMB = 360; Signer = 'Microsoft Corporation'
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Windows Subsystem for Linux'; Order = 105
           PostAction = 'WSLFeatures' }
        @{ Name = 'DockerDesktop'; Category = 'Conteneurs'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/DockerDesktop'
           WingetId = 'Docker.DockerDesktop'; Architecture = 'x64'; EstimatedSizeMB = 650; Signer = 'Docker'
           SilentArgs = 'install --quiet --accept-license --backend=wsl-2 --always-run-service'; SuccessCodes = @(0, 3010)
           Detection = 'reg:^Docker Desktop'; Order = 106 }

        # ================================================================== Langages
        @{ Name = 'Python'; Category = 'Langages'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/Python'
           WingetId = 'Python.Python.3.14'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 30; Signer = 'Python Software Foundation'
           SilentArgs = '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1'; SuccessCodes = @(0, 3010)
           Detection = 'reg:^Python 3\.14'; Order = 110 }
        @{ Name = 'NodeJS'; Category = 'Langages'; Type = 'Winget'; Priority = 3; TargetDir = 'Logiciels/NodeJS'
           WingetId = 'OpenJS.NodeJS.LTS'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 35; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Node\.js'; Order = 111 }
        @{ Name = 'JavaJDK'; Category = 'Langages'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/JavaJDK'
           WingetId = 'EclipseAdoptium.Temurin.25.JDK'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 200; Signer = ''
           SilentArgs = '/qn /norestart ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome'
           SuccessCodes = @(0, 3010, 1641); Detection = 'reg:Temurin.*25'; Order = 112 }
        @{ Name = 'DotNetSDK'; Category = 'Langages'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/DotNetSDK'
           WingetId = 'Microsoft.DotNet.SDK.10'; Architecture = 'x64'; EstimatedSizeMB = 230; Signer = 'Microsoft Corporation'
           SilentArgs = '/install /quiet /norestart'; SuccessCodes = @(0, 1638, 3010, 1641)
           Detection = 'reg:^Microsoft \.NET SDK 10'; Order = 113 }
        @{ Name = 'Go'; Category = 'Langages'; Type = 'Winget'; Priority = 5; Default = $false; TargetDir = 'Logiciels/Go'
           WingetId = 'GoLang.Go'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 75; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Go Programming Language'; Order = 114 }
        @{ Name = 'Rustup'; Category = 'Langages'; Type = 'Winget'; Priority = 5; Default = $false; TargetDir = 'Logiciels/Rustup'
           WingetId = 'Rustlang.Rustup'; Architecture = 'x64'; EstimatedSizeMB = 15; Signer = ''
           SilentArgs = '-y'; SuccessCodes = @(0); Detection = 'file:%USERPROFILE%\.cargo\bin\rustup.exe'; Order = 115 }

        # ================================================================== API et bases de données
        @{ Name = 'Bruno'; Category = 'API et données'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/Bruno'
           WingetId = 'Bruno.Bruno'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 120; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^Bruno'; Order = 120 }
        @{ Name = 'Postman'; Category = 'API et données'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/Postman'
           WingetId = 'Postman.Postman'; Architecture = 'x64'; EstimatedSizeMB = 160; Signer = ''
           SilentArgs = '--silent'; SuccessCodes = @(0); Detection = 'reg:^Postman'; Order = 121 }
        @{ Name = 'DBeaver'; Category = 'API et données'; Type = 'Winget'; Priority = 4; TargetDir = 'Logiciels/DBeaver'
           WingetId = 'DBeaver.DBeaver.Community'; Architecture = 'x64'; EstimatedSizeMB = 120; Signer = ''
           SilentArgs = '/S /allusers'; SuccessCodes = @(0); Detection = 'reg:^DBeaver'; Order = 122 }

        # ================================================================== Outils
        @{ Name = 'JetBrainsToolbox'; Category = 'Développement'; Mode = 'Manuel'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/JetBrainsToolbox'
           WingetId = 'JetBrains.Toolbox'; Architecture = 'x64'; EstimatedSizeMB = 90; Signer = 'JetBrains'
           SilentArgs = ''; SuccessCodes = @(0); Detection = 'reg:^JetBrains Toolbox'; Order = 130 }
        @{ Name = 'PowerToys'; Category = 'Développement'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/PowerToys'
           WingetId = 'Microsoft.PowerToys'; Architecture = 'x64'; Scope = 'machine'; EstimatedSizeMB = 250; Signer = 'Microsoft Corporation'
           SilentArgs = '/install /quiet /norestart'; SuccessCodes = @(0, 3010); Detection = 'reg:^PowerToys'; Order = 131 }
        @{ Name = 'WinSCP'; Category = 'Développement'; Type = 'Winget'; Priority = 6; Default = $false; TargetDir = 'Logiciels/WinSCP'
           WingetId = 'WinSCP.WinSCP'; Architecture = 'x64'; EstimatedSizeMB = 12; Signer = ''
           SilentArgs = '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP- /ALLUSERS'; SuccessCodes = @(0); Detection = 'reg:^WinSCP'; Order = 132 }
        @{ Name = 'KeePassXC'; Category = 'Sécurité'; Type = 'Winget'; Priority = 5; TargetDir = 'Logiciels/KeePassXC'
           WingetId = 'KeePassXCTeam.KeePassXC'; Architecture = 'x64'; InstallerType = 'wix'; EstimatedSizeMB = 45; Signer = ''
           SilentArgs = '/qn /norestart'; SuccessCodes = @(0, 3010, 1641); Detection = 'reg:^KeePassXC'; Order = 133 }
    )
}
