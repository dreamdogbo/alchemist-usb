#!/usr/bin/env bash
# =============================================================================
#  test-installation-reelle.sh — Post-installation Linux RÉELLE dans des conteneurs jetables
#
#  Installe réellement des composants (dépôts officiels) comme sur un poste fraîchement installé,
#  pour un utilisateur ordinaire (SUDO_USER), puis vérifie que chaque outil répond.
#  Rien n'est installé sur l'ordinateur qui lance le test.
#
#  Usage : bash tests/linux/test-installation-reelle.sh [composants] [image ...]
#    composants : défaut git,vscode,python,trivy,dotnet
#    images     : défaut ubuntu:24.04 debian:trixie
#  Prérequis : Docker et Internet.
# =============================================================================
set -Euo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSANTS="${1:-git,vscode,python,trivy,dotnet}"
shift || true
IMAGES=("$@")
[ "${#IMAGES[@]}" -eq 0 ] && IMAGES=(ubuntu:24.04 debian:trixie)

ECHECS=0
for image in "${IMAGES[@]}"; do
  echo
  echo "== $image : installation réelle de $COMPOSANTS"
  journal="$(mktemp)"
  if docker run --rm -e GITHUB_TOKEN -v "$RACINE/payload/linux/linux:/kit:ro" "$image" bash -c "
      set -e
      # Poste de bureau minimal : sudo et un utilisateur ordinaire (curl absent : installé par le script)
      if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq sudo >/dev/null; else dnf install -y -q sudo >/dev/null; fi
      useradd -m -s /bin/bash testeur
      SUDO_USER=testeur bash /kit/installer-poste.sh -u developpement -c '$COMPOSANTS' -y
      echo '== vérifications'
      ok() { if \"\$@\" >/dev/null 2>&1; then echo \"  OK     \$*\"; else echo \"  ÉCHEC  \$*\"; exit 1; fi; }
      case ',$COMPOSANTS,' in *,git,*) ok git --version; ok git lfs version; ok gh --version ;; esac
      case ',$COMPOSANTS,' in *,vscode,*) ok sudo -u testeur -H code --version --no-sandbox
        sudo -u testeur -H code --list-extensions 2>/dev/null | sed 's/^/         extension : /' ;; esac
      case ',$COMPOSANTS,' in *,python,*) ok python3 --version; ok sudo -u testeur -H bash -lc 'uv --version' ;; esac
      case ',$COMPOSANTS,' in *,trivy,*) ok trivy --version ;; esac
      case ',$COMPOSANTS,' in *,dotnet,*) ok dotnet --list-sdks; dotnet --list-sdks | sed 's/^/         SDK : /' ;; esac
      echo '== idempotence (second passage)'
      SUDO_USER=testeur bash /kit/installer-poste.sh -u developpement -c '$COMPOSANTS' -y | grep -E '^(OK|ÉCHEC)|déjà' | head -20
    " >"$journal" 2>&1; then
    grep -E '^== |^  (OK|ÉCHEC)|extension :|SDK :|^OK |^ÉCHEC|Terminé|déjà' "$journal"
  else
    echo "ÉCHEC — fin du journal :"; tail -n 40 "$journal"; ECHECS=$((ECHECS + 1))
  fi
  rm -f "$journal"
done
echo
[ "$ECHECS" -eq 0 ] && echo "Installation réelle réussie sur ${#IMAGES[@]} image(s)." || echo "$ECHECS image(s) en échec."
exit "$ECHECS"
