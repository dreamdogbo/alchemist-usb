#!/usr/bin/env bash
# =============================================================================
#  creer-cle.sh — Alchemist sous Linux : préparer une clé Ventoy (fenêtres zenity)
#  by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
#
#  Même moteur que sous Windows (Build-Kit.ps1, PowerShell 7). Depuis Linux on prépare :
#    - une clé LINUX (Ubuntu, Mint, Debian, Fedora + ISO Windows facultative) : complète ;
#    - une clé WINDOWS (Windows 11 / 10 + post-installation) : ISO officielle et logiciels sur la
#      clé (manifestes publics de winget, SHA256 vérifiés) ; seul Microsoft 365 (et les rares
#      fichiers sans empreinte publiée) est installé EN LIGNE par la post-installation.
#
#  Usage :  bash creer-cle.sh            assistant universel dans le navigateur (même interface que
#                                       sous Windows) ; repli automatique sur les fenêtres zenity
#           bash creer-cle.sh --zenity   fenêtres zenity
#  Ligne de commande directe :
#    pwsh ./Build-Kit.ps1 -Systeme Linux -Usage Developpement -KeyPath /media/$USER/Ventoy
#    pwsh ./Build-Kit.ps1 -Systeme Windows -Usage Bureautique -Langue fr -KeyPath /media/$USER/Ventoy
#    sudo pwsh ./Build-Kit.ps1 -Systeme Linux -Usage Developpement -InstallerVentoy -Disque /dev/sdb -ConfirmerEffacement EFFACER-sdb
# =============================================================================
set -Euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TITRE="Alchemist — préparer une clé"

erreur() { if command -v zenity >/dev/null 2>&1; then zenity --error --title="$TITRE" --text="$1" 2>/dev/null; else echo "ERREUR : $1" >&2; fi; exit 1; }
question() {
  if command -v zenity >/dev/null 2>&1; then zenity --question --title="$TITRE" --text="$1" 2>/dev/null
  else local r; read -rp "$(echo -e "$1") [O/n] " r; case "$r" in [nN]*) return 1 ;; esac; fi
}
command -v lsblk >/dev/null 2>&1 || erreur "lsblk (util-linux) est requis."

# ----------------------------------------------------------------------------- PowerShell 7
if ! command -v pwsh >/dev/null 2>&1; then
  if question "PowerShell 7 (moteur d'Alchemist) n'est pas installé.\nL'installer maintenant (snap officiel de Microsoft) ?"; then
    if command -v snap >/dev/null 2>&1; then pkexec snap install powershell --classic || erreur "Installation de PowerShell impossible."
    else erreur "Installez PowerShell 7 : https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"; fi
    hash -r; export PATH="$PATH:/snap/bin"
    command -v pwsh >/dev/null 2>&1 || erreur "PowerShell 7 installé mais introuvable : fermez la session puis relancez."
  else exit 1; fi
fi

# ----------------------------------------------------------------------------- assistant universel
if [ "${1:-}" != "--zenity" ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
  # Assistant déjà lancé (onglet fermé entre-temps) : on rouvre sa page au lieu d'en démarrer un second
  if [ -f "$DIR/logs/assistant-ouvert.url" ]; then
    url="$(cat "$DIR/logs/assistant-ouvert.url")"; port="${url#http://127.0.0.1:}"; port="${port%%/*}"
    if [[ "$port" =~ ^[0-9]+$ ]] && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then xdg-open "$url"; exit 0; fi
  fi
  if pwsh -NoProfile -File "$DIR/Assistant-Web.ps1"; then exit 0; fi
  echo "Assistant universel indisponible : fenêtres zenity." >&2
fi

# ----------------------------------------------------------------------------- fenêtres zenity
command -v zenity >/dev/null 2>&1 || { echo "zenity est requis (sudo apt install zenity / sudo dnf install zenity)." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || erreur "python3 est requis."
json() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# Partitions de données Ventoy (libellé « Ventoy », ou 1re partition d'un disque portant VTOYEFI) :
# « chemin<TAB>point de montage » (point de montage vide si la clé n'est pas montée)
cles_ventoy() {
  lsblk -J -o NAME,PATH,TYPE,LABEL,MOUNTPOINT | python3 -c '
import json, sys
def parts(b): return [c for c in b.get("children") or [] if c.get("type") == "part"]
for b in json.load(sys.stdin)["blockdevices"]:
    p = parts(b)
    vtoy = any(c.get("label") == "VTOYEFI" for c in p)
    for i, c in enumerate(p):
        if c.get("label") == "Ventoy" or (vtoy and i == 0 and c.get("label") != "VTOYEFI"):
            print((c.get("path") or "/dev/" + c["name"]) + "\t" + (c.get("mountpoint") or ""))'
}

# ----------------------------------------------------------------------------- 1. système et usage
systeme="$(zenity --list --radiolist --title="$TITRE" --width=640 --height=260 --text="Système à installer avec la clé :" \
  --column="" --column="Système" --column="Contenu" \
  TRUE Linux "Ubuntu LTS, Mint, Debian, Fedora + stack installée depuis les dépôts officiels" \
  FALSE Windows "Windows 11 (ou 10) + logiciels installés par la post-installation (Internet requis)" \
  FALSE Double "Windows + Linux sur la même clé (Windows 11 et Ubuntu, chacun avec sa post-installation)" 2>/dev/null)" || exit 1
[ -z "$systeme" ] && exit 1
double=0; [ "$systeme" = Double ] && { double=1; systeme=Windows; }

usage="$(zenity --list --radiolist --title="$TITRE" --width=560 --height=260 --text="Système : $systeme\nUsage du poste :" \
  --column="" --column="Usage" --column="Contenu" \
  TRUE Bureautique "Bureautique, Microsoft 365, PDF, sécurité" \
  FALSE Developpement "Bureautique + VS Code, Git, conteneurs, langages" 2>/dev/null)" || exit 1
[ -z "$usage" ] && exit 1

# ----------------------------------------------------------------------------- 2. langue et éléments
elements="$(pwsh -NoProfile -File "$DIR/Build-Kit.ps1" -Systeme "$systeme" -Usage "$usage" -ListerElements)" || erreur "Lecture du profil impossible."
profil="$(json 'print(d["Profil"])' <<<"$elements")"
langue=""
if [ "$systeme" = Windows ]; then
  largs=()
  while read -r code; do largs+=("$([ "$code" = fr ] && echo TRUE || echo FALSE)" "$code"); done < <(json 'print("\n".join(d["Langues"]))' <<<"$elements")
  if [ "${#largs[@]}" -gt 0 ]; then
    langue="$(zenity --list --radiolist --title="$TITRE" --width=420 --height=320 --text="Langue de Windows et d'Office :" \
      --column="" --column="Langue" "${largs[@]}" 2>/dev/null)" || exit 1
  fi
fi
mapfile -t lignes < <(json 'print("\n".join(("TRUE" if i["Default"] else "FALSE")+"\t"+i["Name"]+"\t"+i["Category"]+"\t"+str(i["SizeMB"]) for i in d["Items"]))' <<<"$elements")
args=()
for l in "${lignes[@]}"; do
  IFS=$'\t' read -r c n cat s <<<"$l"
  [ "$double" = 1 ] && [ "$n" = Ubuntu ] && c=TRUE
  args+=("$c" "$n" "$cat" "$s Mo")
done
texte="Éléments à mettre sur la clé :"
[ "$systeme" = Windows ] && texte="Éléments de la clé Windows.\nDepuis Linux : l'ISO et les logiciels vont sur la clé ; seul Microsoft 365 est installé en ligne sur le poste."
versions="$(zenity --list --checklist --title="$TITRE" --width=720 --height=560 --text="$texte" \
  --column="" --column="Élément" --column="Catégorie" --column="Taille" --separator=, "${args[@]}" 2>/dev/null)" || exit 1
[ -z "$versions" ] && erreur "Cochez au moins un élément."

# ----------------------------------------------------------------------------- 3. clé
cle_args=()
mapfile -t trouvees < <(cles_ventoy)
# Clé Ventoy branchée mais non montée : montée pour l'utilisateur (udisks, comme le gestionnaire de fichiers)
for t in "${trouvees[@]}"; do
  IFS=$'\t' read -r dev mp <<<"$t"
  if [ -z "$mp" ] && command -v udisksctl >/dev/null 2>&1; then udisksctl mount -b "$dev" >/dev/null 2>&1 || true; fi
done
ventoy="$(cles_ventoy | cut -f2 | sed '/^$/d')"
nb_ventoy="$(grep -c . <<<"$ventoy" || true)"
choix_cle="$(zenity --list --radiolist --title="$TITRE" --width=640 --height=300 --text="Clé :" --column="" --column="Choix" --column="Détail" \
  "$([ -n "$ventoy" ] && echo TRUE || echo FALSE)" existante "Clé Ventoy déjà prête : $([ -n "$ventoy" ] && tr '\n' ' ' <<<"$ventoy" || echo 'aucune détectée')" \
  "$([ -z "$ventoy" ] && echo TRUE || echo FALSE)" neuve "Clé neuve : installer Ventoy (EFFACE la clé)" 2>/dev/null)" || exit 1
sudo_cmd=()
if [ "$choix_cle" = "existante" ]; then
  [ -z "$ventoy" ] && erreur "Aucune clé Ventoy montée. Branchez-la, ouvrez-la dans le gestionnaire de fichiers, ou choisissez « Clé neuve »."
  cle="$(head -1 <<<"$ventoy")"
  if [ "$nb_ventoy" -gt 1 ]; then
    vargs=(); first=TRUE
    while read -r m; do vargs+=("$first" "$m"); first=FALSE; done <<<"$ventoy"
    cle="$(zenity --list --radiolist --title="$TITRE" --width=520 --height=280 --text="Plusieurs clés Ventoy : laquelle préparer ?" \
      --column="" --column="Clé" "${vargs[@]}" 2>/dev/null)" || exit 1
  fi
  cle_args=(-KeyPath "$cle")
else
  # Disques USB/SD amovibles, hors disque système (mêmes garde-fous que le moteur)
  mapfile -t disques < <(lsblk -J -b -o PATH,TYPE,TRAN,SIZE,MODEL,RM,MOUNTPOINT | json '
def amovible(v): return v is True or str(v) == "1"
for b in d["blockdevices"]:
    if b["type"]!="disk" or (b.get("tran") not in ("usb","mmc") and not amovible(b.get("rm"))): continue
    m=[c.get("mountpoint") for c in b.get("children") or [] if c.get("mountpoint")]
    if any(x in ("/","/boot","/boot/efi","/home","[SWAP]") for x in m): continue
    print(b["path"]+"\t"+(b.get("model") or "").strip()+"\t"+str(round(int(b["size"])/1e9,1))+" Go")')
  [ "${#disques[@]}" -eq 0 ] && erreur "Aucune clé USB éligible détectée."
  dargs=(); for l in "${disques[@]}"; do IFS=$'\t' read -r p m s <<<"$l"; dargs+=(FALSE "$p" "$m" "$s"); done
  dargs[0]=TRUE
  disque="$(zenity --list --radiolist --title="$TITRE" --width=620 --height=300 --text="Clé à EFFACER puis préparer :" \
    --column="" --column="Disque" --column="Modèle" --column="Taille" "${dargs[@]}" 2>/dev/null)" || exit 1
  [ -z "$disque" ] && exit 1
  nom="$(basename "$disque")"
  saisie="$(zenity --entry --title="$TITRE" --text="Toutes les données de $disque seront DÉFINITIVEMENT effacées.\nTapez EFFACER pour confirmer :" 2>/dev/null)" || exit 1
  [ "$saisie" = "EFFACER" ] || erreur "Confirmation incorrecte : rien n'a été effacé."
  cle_args=(-InstallerVentoy -Disque "$disque" -ConfirmerEffacement "EFFACER-$nom")
  sudo_cmd=(sudo -E env "PATH=$PATH")
fi

# ----------------------------------------------------------------------------- 4. exécution
journal="$DIR/logs/creer-cle-$(date +%Y%m%d-%H%M%S).log"; mkdir -p "$DIR/logs"
moteur=("${sudo_cmd[@]}" pwsh -NoProfile -File "$DIR/Build-Kit.ps1" -Profil "$profil" -Only "$versions")
[ -n "$langue" ] && moteur+=(-Langue "$langue")
moteur+=("${cle_args[@]}" -LogFile "$journal")
commande="$(printf '%q ' "${moteur[@]}"); echo; read -rp 'Appuyez sur Entrée pour fermer…'"
for terminal in gnome-terminal kgx ptyxis konsole xfce4-terminal mate-terminal x-terminal-emulator xterm; do
  if command -v "$terminal" >/dev/null 2>&1; then
    case "$terminal" in
      gnome-terminal|kgx|ptyxis) exec "$terminal" -- bash -c "$commande" ;;
      *) exec "$terminal" -e bash -c "$commande" ;;
    esac
  fi
done
bash -c "$commande"
