#!/usr/bin/env bash
# =============================================================================
#  verifier-poste.sh — Vérifie qu'un poste Linux préparé par Alchemist est opérationnel
#  Chaque outil est réellement exécuté (version, commande de test).
#  Usage : bash tests/linux/verifier-poste.sh   (en tant qu'utilisateur du poste)
#  Code de sortie : nombre d'outils absents ou en erreur.
# =============================================================================
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"
# shellcheck disable=SC1091
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

ECHECS=0
verifier() {
  local nom="$1"; shift
  local sortie rc
  # La commande va jusqu'au bout (couper sa sortie l'interromprait) ; on affiche la 1re ligne
  sortie="$("$@" 2>&1)"; rc=$?
  sortie="$(printf '%s\n' "$sortie" | grep -m1 -v '^\s*$')"
  if [ "$rc" -eq 0 ]; then printf '  OK      %-24s %s\n' "$nom" "${sortie:0:70}"
  else printf '  ÉCHEC   %-24s %s\n' "$nom" "${sortie:0:70}"; ECHECS=$((ECHECS + 1)); fi
}
paquet() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || rpm -q --qf '%{VERSION}' "$1" 2>/dev/null; }
flatpak_app() { flatpak info "$1" 2>/dev/null | grep -m1 -E '^ *(Version|Branche|Branch)'; }

echo "== Système et sécurité"
verifier "Flatpak + Flathub" sh -c 'flatpak remotes | grep -q flathub && flatpak --version'
verifier "fwupd" fwupdmgr --version
verifier "VLC" vlc --version
verifier "Polices Carlito" sh -c 'fc-list | grep -qi carlito && echo présentes'
verifier "Pare-feu ufw" sh -c 'command -v ufw >/dev/null && echo installé'
verifier "ClamAV" clamscan --version
verifier "KeePassXC" keepassxc-cli --version
verifier "Timeshift" sh -c 'command -v timeshift >/dev/null && echo installé'

echo "== Navigateurs et bureautique"
verifier "Google Chrome" google-chrome --version
verifier "ONLYOFFICE" flatpak_app org.onlyoffice.desktopeditors
verifier "PDFCraft" paquet pdfcraft
verifier "Okular" paquet okular
verifier "Xournal++" xournalpp --version
verifier "PDF Arranger" flatpak_app com.github.jeromerobert.pdfarranger
verifier "Zoom" paquet zoom

echo "== Terminal et Git"
verifier "gcc" gcc --version
verifier "ripgrep" rg --version
verifier "fzf" fzf --version
verifier "bat" sh -c 'batcat --version 2>/dev/null || bat --version'
verifier "eza" eza --version
verifier "Neovim" nvim --version
verifier "Git" git --version
verifier "Git LFS" git lfs version
verifier "GitHub CLI" gh --version
verifier "lazygit" lazygit --version

echo "== Éditeur et conteneurs"
verifier "VS Code" code --version
verifier "Docker Engine" sh -c 'sudo docker run --rm hello-world | grep -m1 "Hello from Docker"'
verifier "Docker Compose" docker compose version
verifier "Podman Desktop" flatpak info io.podman_desktop.PodmanDesktop
# Docker Desktop est facultatif (décoché par défaut) : vérifié seulement s'il est installé
if [ -n "$(paquet docker-desktop)" ]; then verifier "Docker Desktop" paquet docker-desktop; fi
verifier "virt-manager" paquet virt-manager

echo "== Sécurité des conteneurs"
verifier "Trivy" trivy --version
verifier "Trivy (scan d'image)" trivy image --quiet --severity CRITICAL hello-world

echo "== Langages"
verifier "Python" python3 --version
verifier "uv" uv --version
verifier "Node.js (nvm)" node --version
verifier "pnpm (corepack)" sh -c 'corepack --version'
verifier "Java" java -version
verifier "Maven" mvn -v
verifier ".NET SDK" dotnet --version
verifier "Go" go version
verifier "Rust" rustc --version

echo "== API, données, DevOps"
verifier "Bruno" flatpak_app com.usebruno.Bruno
verifier "DBeaver" flatpak_app io.dbeaver.DBeaverCommunity
verifier "kubectl" kubectl version --client
verifier "Helm" helm version --short
verifier "Terraform" terraform version
verifier "Ansible" ansible --version
verifier "AWS CLI" aws --version
verifier "Azure CLI" az version

echo
if [ "$ECHECS" -eq 0 ]; then echo "Tous les outils sont opérationnels."; else echo "$ECHECS outil(s) en échec."; fi
exit "$ECHECS"
