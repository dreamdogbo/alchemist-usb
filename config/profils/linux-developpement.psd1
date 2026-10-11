#
# linux-developpement.psd1 — Profil « Linux — Développement »
#
# Mêmes versions de système que le profil bureautique ; la post-installation (installer-poste.sh)
# ajoute la stack de développement : VS Code, Git/GitHub, Docker Engine + Podman Desktop + Trivy, KVM,
# Python (uv), Node.js LTS (nvm), Java, .NET, Go, Rust, Bruno, DBeaver, outils terminal…
#
@{
    Herite      = 'linux-bureautique'
    Nom         = 'Linux — Développement'
    Usage       = 'Developpement'
    Ordre       = 2
    Description = 'Ubuntu LTS, Mint, Debian ou Fedora + bureautique + VS Code, Git/GitHub, Docker Engine, Podman Desktop, Trivy, KVM, Python, Node.js, Java, .NET, Go, Rust, API et bases de données'
}
