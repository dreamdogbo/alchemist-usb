#!/usr/bin/env bash
# =============================================================================
#  installer-poste.sh — Post-installation Linux (bureautique / développement)
#  Alchemist by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
#
#  Distributions : Ubuntu LTS, Linux Mint, Debian (famille apt) et Fedora (famille dnf).
#  Installe la stack depuis les dépôts OFFICIELS (distribution, Microsoft, Google, Docker,
#  Aqua Security, GitHub, HashiCorp, Flathub, éditeurs). Idempotent : ce qui est déjà installé est sauté.
#  Conteneurs : Docker Engine natif + Podman Desktop (interface) + Trivy (scan) ; Docker Desktop en option.
#  Journal : /var/log/kit-poste/ (copie dans le dossier personnel).
#
#  Usage :
#    sudo bash installer-poste.sh                      # menu (cases à cocher)
#    sudo bash installer-poste.sh -u developpement -y  # stack développement, sans questions
#    sudo bash installer-poste.sh -c vscode,docker,podmandesktop,trivy -y  # composants précis
#    bash installer-poste.sh --liste                   # liste des composants
#    bash installer-poste.sh -u developpement -n -y    # simulation (rien n'est installé)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_VERSION="dev"; KIT_USAGE=""; KIT_TZ=""
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/kit.conf" ] && . "$SCRIPT_DIR/kit.conf"

USAGE_CHOISI="${KIT_USAGE:-}"
COMPOSANTS_DEMANDES=""
TOUT=0; SIMULATION=0; OUI=0; LISTE=0; TSV=0

# ----------------------------------------------------------------------------- composants
# id | libellé | catégorie | défaut bureautique (1/0) | défaut développement (1/0)
COMPOSANTS=(
  "base|Mises à jour du système et outils de base|Système|1|1"
  "zram|Mémoire compressée zram (réactivité, moins d'écritures sur le disque)|Système|1|1"
  "flatpak|Flatpak + Flathub (logithèque élargie)|Système|1|1"
  "pilotes|Pilotes recommandés et micrologiciels (fwupd)|Système|1|1"
  "codecs|Codecs multimédia et VLC|Système|1|1"
  "polices|Polices compatibles Microsoft Office (Carlito/Calibri, Caladea/Cambria, Arial…)|Système|1|1"
  "bureau|Réglages du bureau (GNOME Tweaks, extensions)|Système|1|1"
  "securite|Pare-feu, antivirus ClamAV + ClamTk, KeePassXC|Sécurité|1|1"
  "sauvegarde|Timeshift (instantanés du système)|Sécurité|1|1"
  "chrome|Google Chrome|Navigateurs|1|1"
  "edge|Microsoft Edge|Navigateurs|0|0"
  "office365|Microsoft 365 de bureau INTÉGRAL : Word, Excel, PowerPoint, Outlook, OneNote (LinOffice, Windows léger KVM)|Bureautique|1|1"
  "m365web|Raccourcis web : Teams (pas de version Linux de bureau), OneDrive (option)|Bureautique|0|0"
  "onlyoffice|ONLYOFFICE Desktop (meilleure compatibilité .docx .xlsx .pptx)|Bureautique|1|1"
  "libreoffice|LibreOffice (français)|Bureautique|1|0"
  "pdf|PDF : PDFCraft, Okular, Xournal++, PDF Arranger|Bureautique|1|1"
  "zoom|Zoom|Communication|1|1"
  "messagerie|Slack et Discord (Flathub)|Communication|0|0"
  "devbase|Outils de compilation et de terminal (ripgrep, fzf, bat, eza, tmux, neovim, zsh…)|Développement|0|1"
  "git|Git, Git LFS, GitHub CLI (gh), lazygit, Meld|Développement|0|1"
  "vscode|Visual Studio Code (dépôt Microsoft)|Développement|0|1"
  "docker|Docker Engine + Compose + Buildx (dépôt Docker)|Conteneurs|0|1"
  "podmandesktop|Podman Desktop (interface graphique pour Docker Engine et Podman)|Conteneurs|0|1"
  "trivy|Trivy : scan de vulnérabilités des images, dépendances et secrets|Sécurité|0|1"
  "dockerdesktop|Docker Desktop for Linux (licence payante en entreprise/administration)|Conteneurs|0|0"
  "virtualisation|Virtualisation KVM / QEMU + virt-manager|Conteneurs|0|1"
  "python|Python 3, pipx, uv|Langages|0|1"
  "node|Node.js LTS (nvm) + corepack (pnpm, yarn)|Langages|0|1"
  "java|Java JDK + Maven|Langages|0|1"
  "dotnet|.NET SDK|Langages|0|1"
  "go|Go (dernière version officielle)|Langages|0|1"
  "rust|Rust (rustup)|Langages|0|1"
  "api|Bruno (client API)|API et données|0|1"
  "bdd|DBeaver Community (bases de données)|API et données|0|1"
  "jetbrains|JetBrains Toolbox (IntelliJ, PyCharm, WebStorm…)|Développement|0|0"
  "devops|kubectl, Helm, Terraform, Ansible, AWS CLI, Azure CLI|DevOps|0|0"
  "winboat|WinBoat : toutes applications Windows dans un conteneur (alternative à LinOffice)|Bureautique|0|0"
  "creation|Création : GIMP, Inkscape, Krita, Kdenlive, OBS Studio, Audacity, HandBrake|Création|0|0"
  "artcraft|Suite ArtCraft : PhotoCraft, VectorCraft, FilmCraft, LightCraft, EffectCraft, DesignCraft|Création|0|0"
)

# ----------------------------------------------------------------------------- aide et options
aide() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Options :
  -u, --usage bureautique|developpement   stack par défaut (sinon : kit.conf de la clé)
  -c, --composants id1,id2                composants précis (voir --liste)
  -t, --tout                              tous les composants
  -n, --simulation                        affiche ce qui serait fait, n'installe rien
  -y, --oui                               sans menu ni question
  -l, --liste                             liste des composants
  -h, --aide                              cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -u|--usage) USAGE_CHOISI="${2:-}"; shift 2 ;;
    -c|--composants) COMPOSANTS_DEMANDES="${2:-}"; shift 2 ;;
    -t|--tout) TOUT=1; shift ;;
    -n|--simulation|--dry-run) SIMULATION=1; shift ;;
    -y|--oui) OUI=1; shift ;;
    -l|--liste) LISTE=1; shift ;;
    --liste-tsv) LISTE=1; TSV=1; shift ;;
    -h|--aide|--help) aide; exit 0 ;;
    --) shift ;;
    *) echo "Option inconnue : $1" >&2; aide; exit 2 ;;
  esac
done
USAGE_CHOISI="$(echo "${USAGE_CHOISI:-bureautique}" | tr '[:upper:]' '[:lower:]' | sed 's/é/e/g')"
case "$USAGE_CHOISI" in bureautique|developpement) ;; *) echo "Usage inconnu : $USAGE_CHOISI" >&2; exit 2 ;; esac

if [ "$LISTE" -eq 1 ] && [ "$TSV" -eq 1 ]; then
  # Sortie tabulée pour les assistants : id, catégorie, défaut bureautique, défaut développement, libellé
  for c in "${COMPOSANTS[@]}"; do IFS='|' read -r id lib cat db dd <<<"$c"; printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$cat" "$db" "$dd" "$lib"; done
  exit 0
fi
if [ "$LISTE" -eq 1 ]; then
  printf '%-15s %-16s %-4s %-4s %s\n' "COMPOSANT" "CATÉGORIE" "BUR." "DEV." "DESCRIPTION"
  for c in "${COMPOSANTS[@]}"; do
    IFS='|' read -r id lib cat db dd <<<"$c"
    printf '%-15s %-16s %-4s %-4s %s\n' "$id" "$cat" "$([ "$db" = 1 ] && echo oui || echo -)" "$([ "$dd" = 1 ] && echo oui || echo -)" "$lib"
  done
  exit 0
fi

# ----------------------------------------------------------------------------- droits, journal
if [ "$SIMULATION" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "Droits administrateur nécessaires : relance avec sudo…"
  relance=(-u "$USAGE_CHOISI")
  [ -n "$COMPOSANTS_DEMANDES" ] && relance+=(-c "$COMPOSANTS_DEMANDES")
  [ "$TOUT" -eq 1 ] && relance+=(-t)
  [ "$OUI" -eq 1 ] && relance+=(-y)
  exec sudo -E bash "$0" "${relance[@]}"
fi

UTILISATEUR="${SUDO_USER:-$(id -un)}"
HOME_UTILISATEUR="$(getent passwd "$UTILISATEUR" | cut -d: -f6)"
HORODATAGE="$(date +%Y%m%d-%H%M%S)"
if [ "$SIMULATION" -eq 1 ]; then JOURNAL="/tmp/kit-poste-$HORODATAGE.log"
else mkdir -p /var/log/kit-poste; JOURNAL="/var/log/kit-poste/poste-$HORODATAGE.log"; fi
exec > >(tee -a "$JOURNAL") 2>&1

# ----------------------------------------------------------------------------- distribution
# shellcheck disable=SC1091
. /etc/os-release
DISTRO="${ID:-inconnu}"
case " ${ID:-} ${ID_LIKE:-} " in
  *" fedora "*|*" rhel "*) FAMILLE="rpm" ;;
  *" debian "*|*" ubuntu "*) FAMILLE="deb" ;;
  *) echo "Distribution non prise en charge : ${PRETTY_NAME:-$DISTRO} (familles Debian/Ubuntu et Fedora)." >&2; exit 4 ;;
esac
# Dépôts tiers : codename Ubuntu pour Ubuntu et Mint (UBUNTU_CODENAME), Debian pour Debian
if [ "$DISTRO" = "debian" ]; then UPSTREAM="debian"; CODENAME="${VERSION_CODENAME:-trixie}"
else UPSTREAM="ubuntu"; CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}"; fi
ARCH="$(uname -m)"; DEB_ARCH="amd64"; [ "$ARCH" = "aarch64" ] && DEB_ARCH="arm64"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export DEBIAN_FRONTEND=noninteractive

vert() { printf '\033[32m%s\033[0m\n' "$*"; }
jaune() { printf '\033[33m%s\033[0m\n' "$*"; }
rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
etape() { printf '\n\033[36m== %s\033[0m\n' "$*"; }

# ----------------------------------------------------------------------------- utilitaires
# Exécute une commande, ou l'affiche seulement en simulation
lancer() { if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] $*"; else "$@"; fi; }

# Commande exécutée en tant qu'utilisateur (outils installés dans le dossier personnel).
# Elle part du dossier personnel : le dossier courant (celui de root, ex. /root ou le dépôt
# cloné) peut être inaccessible à l'utilisateur, ce qui fait échouer Podman, nvm, rustup…
en_utilisateur() {
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] ($UTILISATEUR) $*"; return 0; fi
  sudo -u "$UTILISATEUR" -H bash -lc "cd ~ || exit; $*"
}

# Commande dans la SESSION de l'utilisateur (Podman sans root, D-Bus utilisateur)
en_session() {
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] ($UTILISATEUR, session) $*"; return 0; fi
  local uid; uid="$(id -u "$UTILISATEUR")"
  # L'écran est transmis (FreeRDP en a besoin pour installer et afficher Office)
  local ecran=()
  [ -n "${DISPLAY:-}" ] && ecran+=("DISPLAY=$DISPLAY")
  [ -n "${WAYLAND_DISPLAY:-}" ] && ecran+=("WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
  [ -n "${XAUTHORITY:-}" ] && ecran+=("XAUTHORITY=$XAUTHORITY")
  # Dossiers propres à l'utilisateur (aucune configuration héritée d'un autre compte)
  sudo -u "$UTILISATEUR" -H env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u CONTAINERS_CONF -u CONTAINERS_STORAGE_CONF \
    HOME="$HOME_UTILISATEUR" XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "${ecran[@]}" bash -lc "cd ~ || exit; $*"
}

PAQ_A_JOUR=0
paq_maj() {
  [ "$PAQ_A_JOUR" -eq 1 ] && return 0
  if [ "$FAMILLE" = "deb" ]; then lancer apt-get update -qq; else lancer dnf -y -q makecache; fi
  PAQ_A_JOUR=1
}

paq_present() { if [ "$FAMILLE" = "deb" ]; then dpkg -s "$1" >/dev/null 2>&1; else rpm -q "$1" >/dev/null 2>&1; fi; }
paq_existe() { if [ "$FAMILLE" = "deb" ]; then apt-cache show "$1" >/dev/null 2>&1; else dnf -q info "$1" >/dev/null 2>&1; fi; }

# paquets "<noms famille deb>" "<noms famille rpm>" : installe ce qui manque et existe
paquets() {
  local liste="$1"; [ "$FAMILLE" = "rpm" ] && liste="${2:-}"
  [ -z "$liste" ] && return 0
  paq_maj
  local manquants=() p
  for p in $liste; do
    paq_present "$p" && continue
    if paq_existe "$p"; then manquants+=("$p")
    elif [ "$SIMULATION" -eq 1 ]; then manquants+=("$p")   # dépôt tiers pas encore ajouté en simulation
    else jaune "  (paquet indisponible sur $DISTRO : $p)"; fi
  done
  [ "${#manquants[@]}" -eq 0 ] && { echo "  déjà installé : $liste"; return 0; }
  if [ "$FAMILLE" = "deb" ]; then lancer apt-get install -y --no-install-recommends "${manquants[@]}"
  else lancer dnf install -y "${manquants[@]}"; fi
}

# Version de dépôt disponible : codename de la distribution, sinon la version stable précédente
suite_dispo() {
  local base="$1" repli="noble"; [ "$UPSTREAM" = "debian" ] && repli="bookworm"
  if curl -fsI "$base/dists/$CODENAME/Release" >/dev/null 2>&1; then echo "$CODENAME"; else echo "$repli"; fi
}

# Dépôt apt signé (clé dans /etc/apt/keyrings), idempotent
depot_apt() {
  local nom="$1" cle="$2" ligne="$3" armure="${4:-oui}"
  local trousseau="/etc/apt/keyrings/$nom.gpg" liste="/etc/apt/sources.list.d/$nom.list"
  [ -f "$liste" ] && [ -f "$trousseau" ] && return 0
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] dépôt apt $nom : ${ligne//@CLE@/$trousseau}"; return 0; fi
  install -d -m 0755 /etc/apt/keyrings
  if [ "$armure" = "oui" ]; then curl -fsSL "$cle" | gpg --dearmor --yes -o "$trousseau"; else curl -fsSL "$cle" -o "$trousseau"; fi
  chmod 0644 "$trousseau"
  echo "${ligne//@CLE@/$trousseau}" > "$liste"
  PAQ_A_JOUR=0
}

# Dépôt dnf : fichier .repo officiel (URL) ou contenu fourni
depot_rpm() {
  local nom="$1" source="$2"
  local fichier="/etc/yum.repos.d/$nom.repo"
  [ -f "$fichier" ] && return 0
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] dépôt dnf $nom : $source"; return 0; fi
  case "$source" in
    http*) curl -fsSL "$source" -o "$fichier" ;;
    *) printf '%s\n' "$source" > "$fichier" ;;
  esac
  PAQ_A_JOUR=0
}

flatpak_installer() {
  command -v flatpak >/dev/null 2>&1 || comp_flatpak
  local id
  for id in "$@"; do
    if [ "$SIMULATION" -eq 0 ] && flatpak info "$id" >/dev/null 2>&1; then echo "  déjà installé : $id"; continue; fi
    lancer flatpak install -y --noninteractive --system flathub "$id"
  done
}

# Télécharge un paquet .deb / .rpm officiel et l'installe (dépendances résolues)
fichier_paquet() {
  local nom="$1" url="$2" paquet="${3:-}" ext="deb"; [ "$FAMILLE" = "rpm" ] && ext="rpm"
  if [ -n "$paquet" ] && paq_present "$paquet"; then echo "  déjà installé : $paquet"; return 0; fi
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] $url -> installation de $nom.$ext"; return 0; fi
  curl -fL --retry 3 -o "$TMP/$nom.$ext" "$url"
  paq_maj
  if [ "$FAMILLE" = "deb" ]; then apt-get install -y "$TMP/$nom.$ext"; else dnf install -y "$TMP/$nom.$ext"; fi
}

# Jeton GitHub facultatif (GITHUB_TOKEN) : évite la limite de 60 requêtes/heure de l'API
github_auth() { if [ -n "${GITHUB_TOKEN:-}" ]; then printf '%s\n' -H "Authorization: Bearer $GITHUB_TOKEN"; fi; }

# Étiquette de la dernière release STABLE : API GitHub, sinon redirection de /releases/latest (sans API)
github_tag() {
  local depot="$1" tag="" auth=()
  mapfile -t auth < <(github_auth)
  tag="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$depot/releases/latest" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("" if d.get("draft") or d.get("prerelease") else d["tag_name"])' 2>/dev/null || true)"
  if [ -z "$tag" ]; then
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$depot/releases/latest" 2>/dev/null | sed -n 's#.*/releases/tag/##p')"
  fi
  printf '%s\n' "$tag"
}

# URL du fichier d'une release GitHub STABLE correspondant au motif (regex) : API, sinon page des assets
github_dernier() {
  local depot="$1" motif="$2" tag url auth=()
  mapfile -t auth < <(github_auth)
  url="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$depot/releases/latest" 2>/dev/null | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
if data.get("draft") or data.get("prerelease"): sys.exit(1)
for a in data.get("assets", []):
    if re.search(sys.argv[1], a["name"]):
        print(a["browser_download_url"]); break
' "$motif" 2>/dev/null || true)"
  if [ -z "$url" ]; then
    tag="$(github_tag "$depot")"; [ -z "$tag" ] && return 1
    url="$(curl -fsSL "https://github.com/$depot/releases/expanded_assets/$tag" 2>/dev/null | python3 -c '
import re, sys
for path in re.findall(r"href=\"(/[^\"]+/releases/download/[^\"]+)\"", sys.stdin.read()):
    if re.search(sys.argv[1], path.rsplit("/", 1)[-1]):
        print("https://github.com" + path); break
' "$motif" || true)"
  fi
  [ -n "$url" ] && printf '%s\n' "$url"
}

# Installe le paquet d'une release GitHub (.deb ou .rpm selon la distribution)
github_paquet() {
  local depot="$1" nom="$2" url motif
  if [ "$FAMILLE" = "deb" ]; then motif="$3"; else motif="$4"; fi
  url="$(github_dernier "$depot" "$motif" || true)"
  if [ -n "$url" ]; then fichier_paquet "$nom" "$url" "$nom"; else jaune "  $nom : aucune release stable pour $FAMILLE"; fi
}

CLE_MS="https://packages.microsoft.com/keys/microsoft.asc"

# ----------------------------------------------------------------------------- composants
comp_base() {
  paq_maj
  if [ "$FAMILLE" = "deb" ]; then lancer apt-get -y full-upgrade; else lancer dnf -y upgrade --refresh; fi
  paquets "curl wget ca-certificates gnupg apt-transport-https git unzip p7zip-full zip tree htop btop jq python3 ncdu" \
          "curl wget2-wget ca-certificates gnupg2 dnf-plugins-core git unzip 7zip zip tree htop btop jq python3 ncdu"
  if [ -n "${KIT_TZ:-}" ]; then lancer timedatectl set-timezone "$KIT_TZ" || true; fi
}

# Mémoire d'échange compressée en RAM (zram, zstd, 50 % de la RAM, prioritaire sur le fichier d'échange)
comp_zram() {
  if paq_present zram-config || paq_present zram-tools; then echo "  zram déjà géré par zram-config / zram-tools : conservé"; return 0; fi
  paquets "systemd-zram-generator" "zram-generator"
  if [ -f /etc/systemd/zram-generator.conf ]; then echo "  /etc/systemd/zram-generator.conf existant : conservé"; return 0; fi
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] /etc/systemd/zram-generator.conf : zram-size = ram / 2, zstd, priorité 100"
  else
    cat > /etc/systemd/zram-generator.conf <<'EOF'
# Alchemist : mémoire d'échange compressée en RAM
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
  fi
  lancer systemctl daemon-reload
  lancer systemctl restart systemd-zram-setup@zram0.service || jaune "  zram actif au prochain démarrage"
}

# Btrfs : dossier sans copie à l'écriture (disques de machines virtuelles : évite la fragmentation).
# N'agit que sur Btrfs et sur les fichiers créés ensuite ; sans effet sur ext4.
sans_cow() {
  local dossier="$1"
  [ "$(stat -f -c %T "$(dirname "$dossier")" 2>/dev/null)" = "btrfs" ] || return 0
  lancer install -d -m 0755 "$dossier"
  if lancer chattr +C "$dossier"; then echo "  $dossier : sans copie à l'écriture (Btrfs)"; fi
}

comp_flatpak() {
  paquets "flatpak" "flatpak"
  [ "$DISTRO" = "ubuntu" ] && paquets "gnome-software-plugin-flatpak" ""
  lancer flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  # Fedora active un Flathub filtré : on retire le filtre pour avoir tout le catalogue
  [ "$FAMILLE" = "rpm" ] && lancer flatpak remote-modify --system --no-filter --enable flathub || true
}

comp_pilotes() {
  paquets "fwupd" "fwupd"
  case "$DISTRO" in
    ubuntu|linuxmint) paquets "ubuntu-drivers-common" ""; lancer ubuntu-drivers install || jaune "  aucun pilote supplémentaire recommandé" ;;
    debian) paquets "firmware-linux-free" "" ;;
    fedora) jaune "  Fedora : pilotes NVIDIA via RPM Fusion (composant codecs) puis « dnf install akmod-nvidia »" ;;
  esac
  lancer fwupdmgr refresh --force || true
  lancer fwupdmgr update -y --no-reboot-check || jaune "  pas de mise à jour de micrologiciel"
}

rpmfusion() {
  local v; v="$(rpm -E %fedora 2>/dev/null || echo 0)"
  paq_present rpmfusion-free-release && return 0
  lancer dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$v.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$v.noarch.rpm"
  PAQ_A_JOUR=0
}

comp_codecs() {
  case "$DISTRO" in
    ubuntu)
      [ "$SIMULATION" -eq 1 ] || echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
      paquets "ubuntu-restricted-extras vlc" "" ;;
    linuxmint) paquets "mint-meta-codecs vlc" "" ;;
    debian) paquets "vlc ffmpeg gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav" "" ;;
    *) rpmfusion
       lancer dnf swap -y ffmpeg-free ffmpeg --allowerasing || true
       paquets "" "vlc gstreamer1-plugins-bad-free gstreamer1-plugin-libav" ;;
  esac
}

comp_polices() {
  if [ "$FAMILLE" = "deb" ]; then
    [ "$SIMULATION" -eq 1 ] || echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
  fi
  paquets "ttf-mscorefonts-installer fonts-crosextra-carlito fonts-crosextra-caladea fonts-liberation fonts-noto-color-emoji fonts-firacode" \
          "google-carlito-fonts google-crosextra-caladea-fonts liberation-fonts-all google-noto-emoji-fonts fira-code-fonts"
}

comp_bureau() {
  case "${XDG_CURRENT_DESKTOP:-}${DISTRO}" in
    *Cinnamon*|*linuxmint*) echo "  Linux Mint (Cinnamon) : réglages intégrés, rien à ajouter." ;;
    *) paquets "gnome-tweaks gnome-shell-extension-manager" "gnome-tweaks gnome-extensions-app" ;;
  esac
}

comp_securite() {
  paquets "clamav clamav-daemon clamtk keepassxc ufw" "clamav clamav-update clamav-freshclam clamtk keepassxc firewalld"
  if [ "$FAMILLE" = "deb" ]; then
    lancer ufw default deny incoming; lancer ufw default allow outgoing; lancer ufw --force enable
    lancer systemctl enable --now clamav-freshclam || true
  else
    lancer systemctl enable --now firewalld || true
    lancer freshclam || true
  fi
}

# Timeshift : configuré en mode Btrfs (instantanés immédiats) quand / est le sous-volume « @ » ;
# sinon laissé à configurer (mode rsync : disque externe conseillé). Configuration existante conservée.
comp_sauvegarde() {
  paquets "timeshift" "timeshift"
  local conf=/etc/timeshift/timeshift.json defaut=/etc/timeshift/default.json uuid
  if [ -f "$conf" ]; then echo "  configuration Timeshift existante : conservée"; return 0; fi
  if [ "$(findmnt -no FSTYPE /)" != "btrfs" ] || [ "$(findmnt -no FSROOT /)" != "/@" ]; then
    jaune "  Timeshift : / n'est pas un sous-volume Btrfs « @ » ; à configurer (mode rsync, disque externe conseillé)"; return 0
  fi
  case "$(findmnt -no SOURCE /)" in /dev/mapper/*)
    jaune "  Timeshift : système chiffré ; choisir le volume dans Timeshift au premier lancement"; return 0 ;;
  esac
  uuid="$(findmnt -no UUID /)"
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] $conf : Btrfs ($uuid), 5 quotidiens + 3 hebdomadaires"; return 0; fi
  [ -f "$defaut" ] || { jaune "  Timeshift : $defaut introuvable, configuration au premier lancement"; return 0; }
  python3 - "$defaut" "$conf" "$uuid" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
c.update({"backup_device_uuid": sys.argv[3], "parent_device_uuid": "", "do_first_run": "false",
          "btrfs_mode": "true", "include_btrfs_home": "false",
          "schedule_daily": "true", "count_daily": "5", "schedule_weekly": "true", "count_weekly": "3"})
json.dump(c, open(sys.argv[2], "w"), indent=2)
EOF
  echo "  Timeshift : mode Btrfs, 5 instantanés quotidiens + 3 hebdomadaires (hors /home)"
}

comp_chrome() {
  if [ "$FAMILLE" = "deb" ]; then
    depot_apt google-chrome https://dl.google.com/linux/linux_signing_key.pub \
      "deb [arch=amd64 signed-by=@CLE@] https://dl.google.com/linux/chrome/deb/ stable main"
  else
    depot_rpm google-chrome "[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub"
  fi
  paquets "google-chrome-stable" "google-chrome-stable"
}

depot_microsoft_rpm() {
  local nom="$1" chemin="$2"
  depot_rpm "$nom" "[$nom]
name=$nom
baseurl=https://packages.microsoft.com/yumrepos/$chemin
enabled=1
gpgcheck=1
gpgkey=$CLE_MS"
}

comp_edge() {
  if [ "$FAMILLE" = "deb" ]; then
    depot_apt microsoft-edge "$CLE_MS" "deb [arch=amd64 signed-by=@CLE@] https://packages.microsoft.com/repos/edge stable main"
  else depot_microsoft_rpm microsoft-edge edge; fi
  paquets "microsoft-edge-stable" "microsoft-edge-stable"
}

# Microsoft 365 en applications web (Edge --app) : Word, Excel, PowerPoint, Outlook, Teams, OneDrive
comp_m365web() {
  command -v microsoft-edge >/dev/null 2>&1 || comp_edge
  local apps=(
    "teams|Teams|https://teams.microsoft.com/|internet-group-chat"
    "onedrive|OneDrive|https://www.office.com/launch/onedrive|folder-remote"
    "office|Microsoft 365 (portail en ligne)|https://www.office.com/|applications-office"
    "word|Word (en ligne)|https://www.office.com/launch/word|x-office-document"
    "excel|Excel (en ligne)|https://www.office.com/launch/excel|x-office-spreadsheet"
    "powerpoint|PowerPoint (en ligne)|https://www.office.com/launch/powerpoint|x-office-presentation"
    "outlook|Outlook (en ligne)|https://outlook.office.com/mail/|mail-client"
  )
  local a id nom url icone fichier
  for a in "${apps[@]}"; do
    IFS='|' read -r id nom url icone <<<"$a"
    fichier="/usr/share/applications/kit-m365-$id.desktop"
    if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] raccourci $nom -> $url"; continue; fi
    cat > "$fichier" <<EOF
[Desktop Entry]
Type=Application
Name=$nom
Comment=Microsoft 365 dans une fenêtre dédiée (Microsoft Edge)
Exec=microsoft-edge --app=$url
Icon=$icone
Categories=Office;Network;
StartupNotify=true
EOF
    chmod 0644 "$fichier"
  done
  echo "  Connectez-vous avec le compte Microsoft 365 de l'utilisateur : fidélité totale des documents."
}

# Microsoft 365 de bureau INTÉGRAL via LinOffice (github.com/eylenburg/linoffice, AGPL) :
# Windows minimal (dockur/windows) en conteneur Podman + KVM, applications affichées par FreeRDP
# comme des applications Linux. Windows et Office viennent directement de Microsoft.
# Licence Microsoft 365 requise (connexion au compte = Office 365 activé).
comp_office365() {
  local ram libre tag
  if [ "$SIMULATION" -eq 0 ]; then
    if [ ! -e /dev/kvm ] && ! grep -Eqw 'vmx|svm' /proc/cpuinfo; then
      jaune "  Virtualisation indisponible : activez Intel VT-x / AMD-V dans le BIOS, puis relancez."; return 1
    fi
    ram="$(awk '/MemTotal/ {print int($2/1048576 + 0.5)}' /proc/meminfo)"
    if [ "$ram" -lt 8 ]; then jaune "  8 Go de RAM minimum requis (ce poste : $ram Go)."; return 1; fi
    libre="$(df -BG --output=avail "$HOME_UTILISATEUR" | tail -1 | tr -dc '0-9')"
    if [ "$libre" -lt 64 ]; then jaune "  64 Go libres requis dans $HOME_UTILISATEUR (disponible : $libre Go)."; return 1; fi
  else
    echo "  [simulation] vérifications : virtualisation (KVM), 8 Go de RAM, 64 Go libres"
  fi
  paquets "podman podman-compose freerdp3-x11 freerdp3-wayland python3 python3-pyside6.qtwidgets python3-pyside6.qtuitools python3-pyside6.qtcore" \
          "podman podman-compose freerdp python3 python3-pyside6"
  lancer usermod -aG kvm "$UTILISATEUR"
  # Podman sans root : identifiants subordonnés (/etc/subuid, /etc/subgid) pour l'utilisateur
  if ! grep -q "^$UTILISATEUR:" /etc/subuid 2>/dev/null; then
    lancer usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$UTILISATEUR"
  fi
  # Session systemd de l'utilisateur (requise par Podman sans root), y compris hors connexion graphique
  lancer loginctl enable-linger "$UTILISATEUR" || true
  if [ "$SIMULATION" -eq 0 ]; then
    local uid; uid="$(id -u "$UTILISATEUR")"
    lancer systemctl start "user@$uid.service" || true
    for _ in $(seq 1 30); do [ -S "/run/user/$uid/bus" ] && break; sleep 1; done
    # Disque virtuel de Windows sur Btrfs : sans copie à l'écriture (créé avant le stockage Podman)
    en_session "mkdir -p ~/.local/share && [ \"\$(stat -f -c %T ~/.local/share)\" = btrfs ] && mkdir -p ~/.local/share/containers && chattr +C ~/.local/share/containers || true"
    en_session "podman system migrate >/dev/null 2>&1 || true"
    if ! en_session "podman info >/dev/null 2>&1"; then
      rouge "  Podman sans root ne fonctionne pas pour $UTILISATEUR :"
      en_session "podman info 2>&1 | tail -n 8" || true
      return 1
    fi
    echo "  Podman sans root : opérationnel"
  fi
  tag="$(github_tag eylenburg/linoffice)"
  [ -z "$tag" ] && { jaune "  LinOffice : version introuvable"; return 1; }
  echo "  LinOffice $tag : installation dans ~/.local/bin/linoffice"
  en_session "mkdir -p ~/.local/bin && cd ~/.local/bin && if [ -d linoffice ]; then mv linoffice \"linoffice.ancien-\$(date +%s)\"; fi && curl -fsSL https://github.com/eylenburg/linoffice/archive/refs/tags/$tag.tar.gz | tar -xz && mv linoffice-* linoffice && chmod +x linoffice/*.sh"
  echo "  Téléchargement de Windows et de Microsoft Office depuis Microsoft (plusieurs Go, 30 à 60 min)…"
  en_session "cd ~/.local/bin/linoffice && ./setup.sh"
  echo "  Terminé : Word, Excel, PowerPoint, Outlook et OneNote sont dans le menu des applications."
  echo "  Ouvrez Word et connectez-vous avec le compte Microsoft 365 : Office passe en version 365 activée."
  echo "  Mises à jour : ~/.local/bin/linoffice/linoffice.sh update — Désinstallation : ~/.local/bin/linoffice/uninstall.sh"
}

comp_onlyoffice() { flatpak_installer org.onlyoffice.desktopeditors; }
comp_libreoffice() { paquets "libreoffice libreoffice-l10n-fr libreoffice-help-fr hunspell-fr" "libreoffice libreoffice-langpack-fr hunspell-fr"; }

comp_pdf() {
  github_paquet storytold/pdfcraft pdfcraft 'pdfcraft-[0-9.]+-linux-x86_64\.deb$' 'pdfcraft-[0-9.]+-linux-x86_64\.rpm$'
  paquets "okular xournalpp" "okular xournalpp"
  flatpak_installer com.github.jeromerobert.pdfarranger
}

comp_zoom() {
  if [ "$FAMILLE" = "deb" ]; then fichier_paquet zoom https://zoom.us/client/latest/zoom_amd64.deb zoom
  else fichier_paquet zoom https://zoom.us/client/latest/zoom_x86_64.rpm zoom; fi
}

comp_messagerie() { flatpak_installer com.slack.Slack com.discordapp.Discord; }

comp_devbase() {
  if [ "$FAMILLE" = "rpm" ]; then lancer dnf group install -y development-tools || true; fi
  paquets "build-essential pkg-config libssl-dev cmake gdb make shellcheck direnv ripgrep fd-find fzf bat eza tmux neovim httpie yq zsh tealdeer" \
          "gcc gcc-c++ make pkgconf-pkg-config openssl-devel cmake gdb ShellCheck direnv ripgrep fd-find fzf bat eza tmux neovim httpie yq zsh tealdeer"
}

comp_git() {
  paquets "git git-lfs meld" "git git-lfs meld"
  if [ "$FAMILLE" = "deb" ]; then
    depot_apt github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      "deb [arch=$DEB_ARCH signed-by=@CLE@] https://cli.github.com/packages stable main" non
  else depot_rpm gh-cli https://cli.github.com/packages/rpm/gh-cli.repo; fi
  paquets "gh" "gh"
  lancer git lfs install --system || true
  if ! command -v lazygit >/dev/null 2>&1; then
    local url; url="$(github_dernier jesseduffield/lazygit 'lazygit_[0-9.]+_[Ll]inux_x86_64\.tar\.gz$' || true)"
    if [ -n "$url" ] && [ "$SIMULATION" -eq 0 ]; then curl -fsSL "$url" | tar -xz -C /usr/local/bin lazygit
    elif [ -n "$url" ]; then echo "  [simulation] lazygit <- $url"; fi
  fi
}

comp_vscode() {
  if [ "$FAMILLE" = "deb" ]; then
    depot_apt vscode "$CLE_MS" "deb [arch=amd64,arm64,armhf signed-by=@CLE@] https://packages.microsoft.com/repos/code stable main"
  else depot_microsoft_rpm vscode vscode; fi
  paquets "code" "code"
}

comp_docker() {
  if [ "$FAMILLE" = "deb" ]; then
    local suite; suite="$(suite_dispo "https://download.docker.com/linux/$UPSTREAM")"
    depot_apt docker "https://download.docker.com/linux/$UPSTREAM/gpg" \
      "deb [arch=$DEB_ARCH signed-by=@CLE@] https://download.docker.com/linux/$UPSTREAM $suite stable"
  else depot_rpm docker-ce https://download.docker.com/linux/fedora/docker-ce.repo; fi
  paquets "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" \
          "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  lancer usermod -aG docker "$UTILISATEUR"
  lancer systemctl enable --now docker || true
  # Rotation des journaux des conteneurs ; un daemon.json existant (réglages locaux) est conservé
  if [ -f /etc/docker/daemon.json ]; then echo "  /etc/docker/daemon.json existant : conservé"; return 0; fi
  if [ "$SIMULATION" -eq 1 ]; then
    echo "  [simulation] /etc/docker/daemon.json : journaux json-file (10 Mo x 3), live-restore"
  else
    install -d -m 0755 /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
  fi
  lancer systemctl restart docker || true
}

comp_virtualisation() {
  if [ "$FAMILLE" = "rpm" ]; then lancer dnf group install -y virtualization || true; fi
  paquets "qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virt-manager bridge-utils ovmf" \
          "qemu-kvm libvirt virt-manager virt-install edk2-ovmf"
  lancer usermod -aG kvm,libvirt "$UTILISATEUR"
  lancer systemctl enable --now libvirtd || true
  sans_cow /var/lib/libvirt/images
}

# Podman Desktop (Flathub, Apache 2.0) : pilote le Docker Engine natif (/var/run/docker.sock) et Podman
comp_podmandesktop() {
  command -v flatpak >/dev/null 2>&1 || comp_flatpak
  paq_present docker-ce || comp_docker
  flatpak_installer io.podman_desktop.PodmanDesktop
  # Accès au socket Docker, limité à Podman Desktop (déjà prévu par Flathub, réaffirmé ici)
  lancer flatpak override --system --filesystem=/run/docker.sock --filesystem=/var/run/docker.sock io.podman_desktop.PodmanDesktop
  echo "  Podman Desktop voit aussi les conteneurs LinOffice/WinBoat : ne pas les supprimer."
}

# Trivy (dépôt officiel Aqua Security) : CVE des images et dépendances, secrets, mauvaises configurations, SBOM
comp_trivy() {
  if [ "$FAMILLE" = "deb" ]; then
    depot_apt trivy https://aquasecurity.github.io/trivy-repo/deb/public.key \
      "deb [signed-by=@CLE@] https://aquasecurity.github.io/trivy-repo/deb generic main"
  else
    # shellcheck disable=SC2016
    depot_rpm trivy '[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key'
  fi
  paquets "trivy" "trivy"
  # Base de vulnérabilités dans le cache de l'utilisateur (non bloquant : téléchargée au premier scan sinon)
  en_utilisateur "trivy image --download-db-only --quiet" || jaune "  base Trivy non téléchargée : elle le sera au premier scan"
}

comp_dockerdesktop() {
  paq_present docker-ce-cli || comp_docker
  comp_virtualisation
  paquets "pass gnupg2" "pass gnupg2"
  if [ "$FAMILLE" = "deb" ]; then fichier_paquet docker-desktop https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb docker-desktop
  else fichier_paquet docker-desktop https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm docker-desktop; fi
  echo "  Docker Desktop et Docker Engine cohabitent : « docker context use desktop-linux » / « default »."
  echo "  Licence : Docker Desktop est payant pour les administrations et les organisations de plus de"
  echo "  250 salariés ou 10 M\$ de chiffre d'affaires (Docker Engine reste libre). Alternative : podmandesktop."
}

comp_python() {
  paquets "python3-full python3-pip python3-venv pipx" "python3 python3-pip pipx"
  en_utilisateur "pipx ensurepath >/dev/null && (pipx install uv || pipx upgrade uv)"
}

comp_node() {
  local tag
  tag="$(github_tag nvm-sh/nvm)"; [ -z "$tag" ] && { jaune "  nvm : version introuvable"; return 1; }
  en_utilisateur "export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] || curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/$tag/install.sh | bash; . \"\$NVM_DIR/nvm.sh\"; nvm install --lts && nvm alias default 'lts/*' && corepack enable"
}

comp_java() {
  paq_maj
  if [ "$FAMILLE" = "deb" ]; then
    if paq_existe openjdk-25-jdk; then paquets "openjdk-25-jdk maven" ""; else paquets "default-jdk maven" ""; fi
  else
    if paq_existe java-25-openjdk-devel; then paquets "" "java-25-openjdk-devel maven"; else paquets "" "java-latest-openjdk-devel maven"; fi
  fi
}

comp_dotnet() {
  paq_maj
  local v
  for v in 10.0 9.0 8.0; do
    if paq_existe "dotnet-sdk-$v"; then paquets "dotnet-sdk-$v" "dotnet-sdk-$v"; return 0; fi
  done
  jaune "  .NET SDK : aucun paquet officiel trouvé pour $DISTRO"
}

comp_go() {
  local info fichier sha
  info="$(curl -fsSL 'https://go.dev/dl/?mode=json' | python3 -c '
import json, sys
for rel in json.load(sys.stdin):
    if not rel.get("stable"): continue
    for f in rel["files"]:
        if f["os"] == "linux" and f["arch"] == "amd64" and f["kind"] == "archive":
            print(f["filename"], f["sha256"]); sys.exit(0)
')"
  read -r fichier sha <<<"$info"
  if [ -x /usr/local/go/bin/go ] && /usr/local/go/bin/go version | grep -q "${fichier%.linux-amd64.tar.gz} "; then echo "  déjà à jour : $fichier"; return 0; fi
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] $fichier (sha256 $sha) -> /usr/local/go"; return 0; fi
  curl -fL --retry 3 -o "$TMP/$fichier" "https://go.dev/dl/$fichier"
  echo "$sha  $TMP/$fichier" | sha256sum -c -
  rm -rf /usr/local/go && tar -C /usr/local -xzf "$TMP/$fichier"
  # shellcheck disable=SC2016
  echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' > /etc/profile.d/kit-go.sh
}

comp_rust() {
  en_utilisateur "command -v rustup >/dev/null 2>&1 && rustup update || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
}

comp_api() { flatpak_installer com.usebruno.Bruno; }
comp_bdd() { flatpak_installer io.dbeaver.DBeaverCommunity; }

comp_jetbrains() {
  if [ -e /usr/local/bin/jetbrains-toolbox ]; then echo "  déjà installé : JetBrains Toolbox"; return 0; fi
  local url
  url="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | python3 -c 'import json,sys; print(json.load(sys.stdin)["TBA"][0]["downloads"]["linux"]["link"])')"
  if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] $url -> /opt/jetbrains-toolbox"; return 0; fi
  paquets "libfuse2t64" "fuse-libs"
  mkdir -p /opt/jetbrains-toolbox
  curl -fsSL "$url" | tar -xz -C /opt/jetbrains-toolbox --strip-components=1
  ln -sf "$(find /opt/jetbrains-toolbox -type f -name 'jetbrains-toolbox' | head -1)" /usr/local/bin/jetbrains-toolbox
  echo "  Lancez « jetbrains-toolbox » une fois pour l'installer dans votre session."
}

comp_devops() {
  # kubectl et Helm : binaires officiels (identiques sur toutes les distributions)
  if ! command -v kubectl >/dev/null 2>&1; then
    local v; v="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] kubectl $v -> /usr/local/bin"
    else
      curl -fsSLo "$TMP/kubectl" "https://dl.k8s.io/release/$v/bin/linux/amd64/kubectl"
      echo "$(curl -fsSL "https://dl.k8s.io/release/$v/bin/linux/amd64/kubectl.sha256")  $TMP/kubectl" | sha256sum -c -
      install -m 0755 "$TMP/kubectl" /usr/local/bin/kubectl
    fi
  fi
  if ! command -v helm >/dev/null 2>&1; then
    if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] Helm (script officiel get-helm-3)"
    else curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi
  fi
  if ! command -v aws >/dev/null 2>&1; then
    if [ "$SIMULATION" -eq 1 ]; then echo "  [simulation] AWS CLI v2 (installeur officiel)"
    else curl -fsSLo "$TMP/awscli.zip" https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip && unzip -q "$TMP/awscli.zip" -d "$TMP" && "$TMP/aws/install"; fi
  fi
  if [ "$FAMILLE" = "deb" ]; then
    local suite; suite="$(suite_dispo https://apt.releases.hashicorp.com)"
    depot_apt hashicorp https://apt.releases.hashicorp.com/gpg "deb [arch=$DEB_ARCH signed-by=@CLE@] https://apt.releases.hashicorp.com $suite main"
    suite="$(suite_dispo https://packages.microsoft.com/repos/azure-cli)"
    depot_apt azure-cli "$CLE_MS" "deb [arch=$DEB_ARCH signed-by=@CLE@] https://packages.microsoft.com/repos/azure-cli/ $suite main"
  else
    depot_rpm hashicorp https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
    depot_microsoft_rpm azure-cli azure-cli
  fi
  paquets "terraform ansible azure-cli" "terraform ansible azure-cli"
}

comp_winboat() {
  paq_present docker-ce || comp_docker
  comp_virtualisation
  paquets "freerdp3-x11" "freerdp"
  github_paquet TibixDev/winboat winboat 'winboat-[0-9.]+-amd64\.deb$' 'winboat-[0-9.]+-x86_64\.rpm$'
  echo "  WinBoat installe Windows dans un conteneur : Word, Excel, PowerPoint s'ouvrent ensuite comme des"
  echo "  applications Linux (licence Windows/Office requise, 8 Go de RAM conseillés)."
}

comp_creation() {
  flatpak_installer org.gimp.GIMP org.inkscape.Inkscape org.kde.krita org.kde.kdenlive \
    com.obsproject.Studio org.audacityteam.Audacity fr.handbrake.ghb
  echo "  DaVinci Resolve (montage pro, natif Linux) : téléchargement manuel sur blackmagicdesign.com."
}

comp_artcraft() {
  local app
  for app in photocraft vectorcraft filmcraft lightcraft effectcraft designcraft; do
    github_paquet "storytold/$app" "$app" "$app-[0-9.]+-linux-x86_64\\.deb\$" "$app-[0-9.]+-linux-x86_64\\.rpm\$"
  done
}

# ----------------------------------------------------------------------------- sélection
defaut_pour() { if [ "$USAGE_CHOISI" = "developpement" ]; then echo "$2"; else echo "$1"; fi; }

declare -a SELECTION=()
if [ -n "$COMPOSANTS_DEMANDES" ]; then
  IFS=',' read -r -a SELECTION <<<"$COMPOSANTS_DEMANDES"
elif [ "$TOUT" -eq 1 ]; then
  for c in "${COMPOSANTS[@]}"; do SELECTION+=("${c%%|*}"); done
else
  for c in "${COMPOSANTS[@]}"; do
    IFS='|' read -r id _ _ db dd <<<"$c"
    [ "$(defaut_pour "$db" "$dd")" = 1 ] && SELECTION+=("$id")
  done
  # Menu à cases à cocher (terminal) si interactif
  if [ "$OUI" -eq 0 ] && [ -t 0 ] && command -v whiptail >/dev/null 2>&1; then
    args=()
    for c in "${COMPOSANTS[@]}"; do
      IFS='|' read -r id lib cat db dd <<<"$c"
      etat=OFF; [ "$(defaut_pour "$db" "$dd")" = 1 ] && etat=ON
      args+=("$id" "[$cat] $lib" "$etat")
    done
    if choix="$(whiptail --title "Alchemist — ${PRETTY_NAME:-Linux} ($USAGE_CHOISI)" --separate-output \
        --checklist "Espace : cocher/décocher — Entrée : valider" 30 110 22 "${args[@]}" 3>&1 1>&2 2>&3)"; then
      mapfile -t SELECTION <<<"$choix"
    else
      echo "Annulé."; exit 1
    fi
  fi
fi

for s in "${SELECTION[@]}"; do
  [ -z "$s" ] && continue
  declare -F "comp_$s" >/dev/null || { rouge "Composant inconnu : $s (voir --liste)"; exit 2; }
done

# ----------------------------------------------------------------------------- exécution
etape "Alchemist v$KIT_VERSION — ${PRETTY_NAME:-$DISTRO} (famille $FAMILLE, dépôts $UPSTREAM/$CODENAME) — usage : $USAGE_CHOISI$([ "$SIMULATION" -eq 1 ] && echo ' — SIMULATION')"
echo "Utilisateur : $UTILISATEUR — journal : $JOURNAL"
if [ "$SIMULATION" -eq 0 ] && ! curl -fsI https://flathub.org >/dev/null 2>&1; then
  rouge "Pas d'accès à Internet : la post-installation Linux utilise les dépôts officiels en ligne."
  exit 3
fi

declare -a BILAN=()
ECHECS=0
for c in "${COMPOSANTS[@]}"; do
  IFS='|' read -r id lib _ _ _ <<<"$c"
  printf '%s\n' "${SELECTION[@]}" | grep -qx "$id" || continue
  etape "$lib"
  set +e
  ( set -Eeuo pipefail; "comp_$id" )
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then BILAN+=("OK      $id — $lib"); vert "  OK"
  else BILAN+=("ÉCHEC   $id — $lib (code $rc)"); ECHECS=$((ECHECS + 1)); rouge "  ÉCHEC (code $rc)"; fi
done

etape "BILAN"
printf '%s\n' "${BILAN[@]}"
if [ "$SIMULATION" -eq 0 ]; then
  cp "$JOURNAL" "$HOME_UTILISATEUR/" 2>/dev/null && chown "$UTILISATEUR": "$HOME_UTILISATEUR/$(basename "$JOURNAL")" || true
  # Double démarrage : Windows doit garder l'horloge en UTC et ne pas « hiberner » son NTFS
  if compgen -G "/boot/efi/EFI/[Mm]icrosoft/Boot/bootmgfw.efi" >/dev/null; then
    jaune "Double démarrage avec Windows détecté. Sous Windows, en administrateur, une seule fois :"
    jaune "  reg add HKLM\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation /v RealTimeIsUniversal /t REG_DWORD /d 1 /f"
    jaune "  powercfg /hibernate off      (démarrage rapide désactivé : NTFS lisible sans risque depuis Linux)"
    jaune "  (fait automatiquement par la post-installation Windows d'Alchemist si Linux est installé en premier)"
  fi
  echo "Redémarrez (ou déconnectez-vous) pour appliquer les groupes docker / kvm / libvirt et les chemins :"
  echo "d'ici là, « docker » sans sudo et Podman Desktop n'accèdent pas au Docker Engine."
fi
if [ "$ECHECS" -eq 0 ]; then vert "Terminé sans échec."; else rouge "$ECHECS échec(s) : relancez le script (ce qui est fait est sauté)."; fi
exit "$ECHECS"
