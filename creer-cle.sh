#!/usr/bin/env bash
# =============================================================================
#  creer-cle.sh — Alchemist sous Linux : préparer une clé Ventoy (fenêtres zenity)
#  by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
#
#  Même moteur que sous Windows (Build-Kit.ps1, PowerShell 7). Depuis Linux on prépare les
#  profils Linux (Ubuntu, Mint, Debian, Fedora… + ISO Windows facultative) ; les profils
#  Windows complets (winget, Office) se préparent depuis Windows.
#
#  Usage :  bash creer-cle.sh
#  Ligne de commande directe :
#    pwsh ./Build-Kit.ps1 -Systeme Linux -Usage Developpement -KeyPath /media/$USER/Ventoy
#    sudo pwsh ./Build-Kit.ps1 -Systeme Linux -Usage Developpement -InstallerVentoy -Disque /dev/sdb -ConfirmerEffacement EFFACER-sdb
# =============================================================================
set -Euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TITRE="Alchemist — préparer une clé"

erreur() { if command -v zenity >/dev/null 2>&1; then zenity --error --title="$TITRE" --text="$1" 2>/dev/null; else echo "ERREUR : $1" >&2; fi; exit 1; }
command -v zenity >/dev/null 2>&1 || { echo "zenity est requis (sudo apt install zenity / sudo dnf install zenity)." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || erreur "python3 est requis."

# ----------------------------------------------------------------------------- PowerShell 7
if ! command -v pwsh >/dev/null 2>&1; then
  if zenity --question --title="$TITRE" --text="PowerShell 7 (moteur d'Alchemist) n'est pas installé.\nL'installer maintenant (snap officiel de Microsoft) ?" 2>/dev/null; then
    if command -v snap >/dev/null 2>&1; then pkexec snap install powershell --classic || erreur "Installation de PowerShell impossible."
    else erreur "Installez PowerShell 7 : https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"; fi
  else exit 1; fi
fi
json() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# ----------------------------------------------------------------------------- 1. usage
usage="$(zenity --list --radiolist --title="$TITRE" --width=560 --height=260 --text="Système : Linux\nUsage du poste :" \
  --column="" --column="Usage" --column="Contenu" \
  TRUE Bureautique "Bureautique, Microsoft 365 web, PDF, sécurité" \
  FALSE Developpement "Bureautique + VS Code, Git, Docker, langages" 2>/dev/null)" || exit 1

# ----------------------------------------------------------------------------- 2. versions
elements="$(pwsh -NoProfile -File "$DIR/Build-Kit.ps1" -Systeme Linux -Usage "$usage" -ListerElements)" || erreur "Lecture du profil impossible."
profil="$(json 'print(d["Profil"])' <<<"$elements")"
mapfile -t lignes < <(json 'print("\n".join(("TRUE" if i["Default"] else "FALSE")+"\t"+i["Name"]+"\t"+i["Category"]+"\t"+str(i["SizeMB"]) for i in d["Items"]))' <<<"$elements")
args=()
for l in "${lignes[@]}"; do IFS=$'\t' read -r c n cat s <<<"$l"; args+=("$c" "$n" "$cat" "$s Mo"); done
versions="$(zenity --list --checklist --title="$TITRE" --width=620 --height=420 --text="Systèmes à mettre sur la clé :" \
  --column="" --column="Élément" --column="Catégorie" --column="Taille" --separator=, "${args[@]}" 2>/dev/null)" || exit 1
[ -z "$versions" ] && erreur "Cochez au moins un système."

# ----------------------------------------------------------------------------- 3. clé
cle_args=()
ventoy="$(lsblk -J -o PATH,LABEL,MOUNTPOINT | json 'print("\n".join(c["mountpoint"] for b in d["blockdevices"] for c in [b]+b.get("children",[]) if c.get("label")=="Ventoy" and c.get("mountpoint")))')"
choix_cle="$(zenity --list --radiolist --title="$TITRE" --width=640 --height=300 --text="Clé :" --column="" --column="Choix" --column="Détail" \
  "$([ -n "$ventoy" ] && echo TRUE || echo FALSE)" existante "Clé Ventoy déjà prête : ${ventoy:-aucune détectée}" \
  "$([ -z "$ventoy" ] && echo TRUE || echo FALSE)" neuve "Clé neuve : installer Ventoy (EFFACE la clé)" 2>/dev/null)" || exit 1
sudo_cmd=""
if [ "$choix_cle" = "existante" ]; then
  [ -z "$ventoy" ] && erreur "Aucune clé Ventoy montée. Branchez-la ou choisissez « Clé neuve »."
  cle_args=(-KeyPath "$(head -1 <<<"$ventoy")")
else
  # Disques USB/SD amovibles, hors disque système (mêmes garde-fous que le moteur)
  mapfile -t disques < <(lsblk -J -b -o PATH,TYPE,TRAN,SIZE,MODEL,RM,MOUNTPOINT | json '
for b in d["blockdevices"]:
    if b["type"]!="disk" or (b.get("tran") not in ("usb","mmc") and not b.get("rm")): continue
    m=[c.get("mountpoint") for c in b.get("children",[]) if c.get("mountpoint")]
    if any(x in ("/","/boot","/boot/efi","/home") for x in m): continue
    print(b["path"]+"\t"+(b.get("model") or "").strip()+"\t"+str(round(int(b["size"])/1e9,1))+" Go")')
  [ "${#disques[@]}" -eq 0 ] && erreur "Aucune clé USB éligible détectée."
  dargs=(); for l in "${disques[@]}"; do IFS=$'\t' read -r p m s <<<"$l"; dargs+=(FALSE "$p" "$m" "$s"); done
  dargs[0]=TRUE
  disque="$(zenity --list --radiolist --title="$TITRE" --width=620 --height=300 --text="Clé à EFFACER puis préparer :" \
    --column="" --column="Disque" --column="Modèle" --column="Taille" "${dargs[@]}" 2>/dev/null)" || exit 1
  nom="$(basename "$disque")"
  saisie="$(zenity --entry --title="$TITRE" --text="Toutes les données de $disque seront DÉFINITIVEMENT effacées.\nTapez EFFACER pour confirmer :" 2>/dev/null)" || exit 1
  [ "$saisie" = "EFFACER" ] || erreur "Confirmation incorrecte : rien n'a été effacé."
  cle_args=(-InstallerVentoy -Disque "$disque" -ConfirmerEffacement "EFFACER-$nom")
  sudo_cmd="sudo -E"
fi

# ----------------------------------------------------------------------------- 4. exécution
journal="$DIR/logs/creer-cle-$(date +%Y%m%d-%H%M%S).log"; mkdir -p "$DIR/logs"
commande="$sudo_cmd pwsh -NoProfile -File '$DIR/Build-Kit.ps1' -Profil '$profil' -Only '$versions' ${cle_args[*]@Q} -LogFile '$journal'; echo; read -rp 'Appuyez sur Entrée pour fermer…'"
for terminal in gnome-terminal kgx konsole xfce4-terminal x-terminal-emulator xterm; do
  if command -v "$terminal" >/dev/null 2>&1; then
    case "$terminal" in
      gnome-terminal|kgx) exec "$terminal" -- bash -c "$commande" ;;
      *) exec "$terminal" -e bash -c "$commande" ;;
    esac
  fi
done
bash -c "$commande"
