#!/usr/bin/env bash
# =============================================================================
#  test-conteneurs.sh — Tests de la post-installation Linux
#    1. shellcheck sur les scripts Linux du kit
#    2. simulation (-n) de la stack « développement » dans des conteneurs
#       Ubuntu, Debian, Fedora, Linux Mint (rien n'est installé : affichage seul)
#  Usage : bash tests/linux/test-conteneurs.sh [image ...]
#  Prérequis : Docker. shellcheck est téléchargé dans ~/.local/bin s'il manque.
# =============================================================================
set -Eeuo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS=("$RACINE/payload/linux/linux/installer-poste.sh" "$RACINE/payload/linux/linux/lancer.sh" "$RACINE/tests/linux/test-conteneurs.sh")
IMAGES=("$@")
[ "${#IMAGES[@]}" -eq 0 ] && IMAGES=(ubuntu:26.04 ubuntu:24.04 debian:trixie fedora:latest linuxmintd/mint22-amd64)

echo "== shellcheck"
if ! command -v shellcheck >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/koalaman/shellcheck/releases/latest/download/shellcheck-$(curl -fsSL https://api.github.com/repos/koalaman/shellcheck/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])').linux.x86_64.tar.xz" \
    | tar -xJ -C "$HOME/.local/bin" --strip-components=1 --wildcards '*/shellcheck'
  export PATH="$HOME/.local/bin:$PATH"
fi
shellcheck -S warning "${SCRIPTS[@]}"
echo "shellcheck : OK"

ECHECS=0
for image in "${IMAGES[@]}"; do
  echo
  echo "== $image : simulation de la stack développement"
  # Prérequis présents sur un poste de bureau (curl, python3, sudo) ajoutés au conteneur minimal
  prepa='if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq curl python3 sudo ca-certificates >/dev/null; else dnf install -y -q curl python3 sudo >/dev/null; fi'
  if docker run --rm -v "$RACINE/payload/linux/linux:/kit:ro" "$image" bash -c "$prepa && useradd -m testeur && SUDO_USER=testeur bash /kit/installer-poste.sh -u developpement -n -y" >"/tmp/kit-test-${image//[:\/]/_}.log" 2>&1; then
    grep -E '^== |^OK |ÉCHEC|Terminé' "/tmp/kit-test-${image//[:\/]/_}.log" | tail -n 40
  else
    echo "ÉCHEC — journal : /tmp/kit-test-${image//[:\/]/_}.log"; tail -n 25 "/tmp/kit-test-${image//[:\/]/_}.log"
    ECHECS=$((ECHECS + 1))
  fi
done
echo
[ "$ECHECS" -eq 0 ] && echo "Tous les tests sont passés." || echo "$ECHECS image(s) en échec."
exit "$ECHECS"
