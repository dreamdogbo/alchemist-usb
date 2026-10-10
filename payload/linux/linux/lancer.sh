#!/usr/bin/env bash
# =============================================================================
#  lancer.sh — Assistant graphique de post-installation Linux (zenity)
#  Alchemist by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
#
#  Sur le poste fraîchement installé : ouvrir le dossier « linux » de la clé, clic droit
#  « Ouvrir dans un terminal », puis :   bash lancer.sh
#  (la clé est en exFAT : les scripts se lancent toujours avec « bash »)
# =============================================================================
set -Euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/installer-poste.sh"
KIT_USAGE="bureautique"
# shellcheck disable=SC1091
[ -f "$DIR/kit.conf" ] && . "$DIR/kit.conf"
USAGE="$(echo "${KIT_USAGE:-bureautique}" | tr '[:upper:]' '[:lower:]')"

# Sans interface graphique ou sans zenity : menu du terminal (whiptail)
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || ! command -v zenity >/dev/null 2>&1; then
  exec sudo bash "$SCRIPT" -u "$USAGE"
fi

TITRE="Alchemist — installation du poste"
choix_usage="$(zenity --list --radiolist --title="$TITRE" --width=520 --height=260 \
  --text="Usage du poste :" --column="" --column="Usage" --column="Contenu" \
  "$([ "$USAGE" = bureautique ] && echo TRUE || echo FALSE)" bureautique "Bureautique, navigateurs, Microsoft 365, PDF, sécurité" \
  "$([ "$USAGE" = developpement ] && echo TRUE || echo FALSE)" developpement "Bureautique + VS Code, Git, Docker, langages, outils" \
  2>/dev/null)" || exit 1
[ -n "$choix_usage" ] && USAGE="$choix_usage"

# Liste des composants avec leur coche par défaut pour l'usage choisi
lignes=()
while IFS=$'\t' read -r id cat bur dev lib; do
  [ -z "$id" ] && continue
  defaut="$bur"; [ "$USAGE" = developpement ] && defaut="$dev"
  lignes+=("$([ "$defaut" = 1 ] && echo TRUE || echo FALSE)" "$id" "$cat" "$lib")
done < <(bash "$SCRIPT" --liste-tsv)

selection="$(zenity --list --checklist --title="$TITRE" --width=980 --height=720 \
  --text="Cochez ce qu'il faut installer (usage : $USAGE). Internet est nécessaire." \
  --column="" --column="Composant" --column="Catégorie" --column="Description" \
  --separator=, "${lignes[@]}" 2>/dev/null)" || exit 1
[ -z "$selection" ] && { zenity --info --text="Aucun composant choisi." 2>/dev/null; exit 0; }

# Exécution dans un terminal (mot de passe sudo, progression, bilan)
commande="sudo bash '$SCRIPT' -u '$USAGE' -c '$selection' -y; echo; read -rp 'Appuyez sur Entrée pour fermer…'"
for terminal in gnome-terminal kgx konsole xfce4-terminal x-terminal-emulator xterm; do
  if command -v "$terminal" >/dev/null 2>&1; then
    case "$terminal" in
      gnome-terminal|kgx) exec "$terminal" -- bash -c "$commande" ;;
      *) exec "$terminal" -e bash -c "$commande" ;;
    esac
  fi
done
bash -c "$commande"
