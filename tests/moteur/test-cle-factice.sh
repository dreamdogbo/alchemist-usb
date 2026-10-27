#!/usr/bin/env bash
# =============================================================================
#  test-cle-factice.sh — Préparation RÉELLE d'une clé Ventoy factice depuis Linux
#
#  Une image disque (exFAT « Ventoy » + VTOYEFI) est montée en boucle dans un conteneur
#  PowerShell 7 jetable et privilégié : aucun disque de l'ordinateur n'est touché.
#  Scénarios : clé Linux, clé Windows préparée depuis Linux, clé double système en deux passes,
#  relance sans réécriture, fichiers personnels intacts, refus d'une clé non Ventoy, refus
#  d'effacer un disque non USB, post-installation Linux lancée depuis la clé.
#
#  Assistant universel (page web locale) : API de création (PowerShell) et de post-installation
#  Linux (Python), sécurité (jeton, hôte), et INSTALLATION RÉELLE de composants Linux par l'assistant.
#
#  Usage : bash tests/moteur/test-cle-factice.sh [--reseau]
#    --reseau : ajoute des simulations (-DryRun) qui interrogent les sources officielles
#               (Ubuntu, Debian, Fedora, Mint, Microsoft via Fido) ; rien de lourd n'est téléchargé.
#  Prérequis : Docker (conteneurs privilégiés autorisés), ~2 Go libres (image creuse).
# =============================================================================
set -Eeuo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESEAU=0; [ "${1:-}" = "--reseau" ] && RESEAU=1
IMAGE="${PWSH_IMAGE:-mcr.microsoft.com/powershell:latest}"
TRAVAIL="$(mktemp -d)"
trap 'rm -rf "$TRAVAIL"' EXIT

cat > "$TRAVAIL/dedans.sh" <<'DEDANS'
#!/usr/bin/env bash
set -Euo pipefail
RESEAU="$1"
apt-get update -qq >/dev/null && apt-get install -y -qq exfatprogs dosfstools fdisk python3 curl >/dev/null 2>&1 || { echo "outils de test non installés"; exit 1; }
cp -r /src /kit && cd /kit
OK=0; KO=0; ECHECS=()
ok() { echo "  OK     $1"; OK=$((OK + 1)); }
ko() { echo "  ÉCHEC  $1"; KO=$((KO + 1)); ECHECS+=("$1"); }
verifier() { local nom="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$nom"; else ko "$nom"; fi; }
etape() { printf '\n== %s\n' "$*"; }

# Sans udev, lsblk ne connaît ni libellé ni système de fichiers : complétés avec blkid (comme udev)
cat > /usr/local/bin/lsblk <<'EOF'
#!/usr/bin/env python3
import json, subprocess, sys
out = subprocess.run(["/usr/bin/lsblk"] + sys.argv[1:], capture_output=True, text=True)
if "-J" not in sys.argv[1:]:
    sys.stdout.write(out.stdout); sys.exit(out.returncode)
d = json.loads(out.stdout or '{"blockdevices": []}')
def fill(n):
    p = n.get("path") or "/dev/" + n.get("name", "")
    if n.get("type") == "part":
        r = subprocess.run(["blkid", "-o", "export", p], capture_output=True, text=True).stdout
        kv = dict(l.split("=", 1) for l in r.splitlines() if "=" in l)
        if "label" in n and not n["label"]: n["label"] = kv.get("LABEL")
        if "fstype" in n and not n["fstype"]: n["fstype"] = kv.get("TYPE")
    for c in n.get("children") or []: fill(c)
for b in d["blockdevices"]: fill(b)
print(json.dumps(d))
EOF
chmod +x /usr/local/bin/lsblk

CLE=/media/testeur/Ventoy
# Disque en boucle toujours détaché, même si le test s'arrête en route (il est global à la machine hôte)
trap 'umount "$CLE" 2>/dev/null; [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null' EXIT
creer_cle() {   # $1 = libellé de la partition de données, $2 = avec VTOYEFI (oui/non)
  umount "$CLE" 2>/dev/null; [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null
  rm -f /img/cle.img; truncate -s 12G /img/cle.img
  if [ "$2" = oui ]; then printf 'label: dos\n,12160M,7\n,32M,ef\n' | sfdisk -q /img/cle.img
  else printf 'label: dos\n,12160M,7\n' | sfdisk -q /img/cle.img; fi
  LOOP="$(losetup -f)"; local n; n="$(basename "$LOOP")"
  [ -e "$LOOP" ] || mknod "$LOOP" b 7 "${n#loop}"
  losetup -P "$LOOP" /img/cle.img
  for p in /sys/block/"$n"/"$n"p*; do local b; b="$(basename "$p")"; IFS=: read -r ma mi < "$p/dev"; rm -f "/dev/$b"; mknod "/dev/$b" b "$ma" "$mi"; done
  mkfs.exfat -L "$1" "${LOOP}p1" >/dev/null
  [ "$2" = oui ] && mkfs.vfat -n VTOYEFI "${LOOP}p2" >/dev/null
  mkdir -p "$CLE" && mount "${LOOP}p1" "$CLE"
}
moteur() { pwsh -NoProfile -File ./Build-Kit.ps1 "$@" -KeyPath "$CLE" >/tmp/moteur.log 2>&1; echo $? > /tmp/code; }
code() { cat /tmp/code; }
manifeste_valide() { (cd "$CLE" && sha256sum -c --quiet MANIFEST.sha256); }
sans_jeton() { ! grep -rl '{{[A-Z0-9_]*}}' "$CLE/postinstall" "$CLE/ventoy" "$CLE/linux" "$CLE"/*.txt 2>/dev/null | grep -q .; }

# ------------------------------------------------------------------------- 1. clé Linux
etape "Clé Linux (développement) préparée depuis Linux"
creer_cle Ventoy oui
mkdir -p "$CLE/Perso" && echo "mes notes" > "$CLE/Perso/notes.txt" && echo "doc" > "$CLE/LISEZ-MOI-PERSO.txt"
moteur -Systeme Linux -Usage Developpement -SkipDownload
verifier "préparation terminée (code 0)" test "$(code)" = 0
verifier "post-installation Linux sur la clé" test -f "$CLE/linux/installer-poste.sh"
verifier "kit.conf : usage développement" grep -qx 'KIT_USAGE=Developpement' "$CLE/linux/kit.conf"
verifier "kit.conf : fuseau au format Linux" grep -qx 'KIT_TZ=Africa/Abidjan' "$CLE/linux/kit.conf"
verifier "scripts en LF sur la clé exFAT" python3 -c "import glob; assert not [f for f in glob.glob('$CLE/linux/*') if b'\\r' in open(f, 'rb').read()]"
verifier "MANIFEST.sha256 vérifiable avec sha256sum -c" manifeste_valide
verifier "aucun jeton {{…}} laissé dans les fichiers" sans_jeton
verifier "pas de post-installation Windows sans ISO Windows" test ! -e "$CLE/postinstall"
verifier "fichiers personnels intacts" sh -c "grep -qx 'mes notes' '$CLE/Perso/notes.txt' && test -f '$CLE/LISEZ-MOI-PERSO.txt'"
verifier "VS Code dans la stack développement (composant coché)" sh -c "bash '$CLE/linux/installer-poste.sh' --liste-tsv | awk -F'\t' '\$1==\"vscode\" && \$4==1' | grep -q ."
verifier "script de la clé lancé avec bash (exFAT sans droit d'exécution)" bash "$CLE/linux/installer-poste.sh" --liste
cp "$CLE/MANIFEST.sha256" /tmp/manifeste-1

etape "Relance identique : rien n'est réécrit"
moteur -Systeme Linux -Usage Developpement -SkipDownload
verifier "relance terminée (code 0)" test "$(code)" = 0
verifier "MANIFEST inchangé" cmp -s /tmp/manifeste-1 "$CLE/MANIFEST.sha256"
verifier "aucun fichier réécrit" grep -q '0 fichier(s) écrit(s)' /tmp/moteur.log

# ------------------------------------------------------------------------- 2. clé Windows depuis Linux
etape "Clé Windows (bureautique, anglais) préparée depuis Linux"
moteur -Systeme Windows -Usage Bureautique -Langue en -SkipDownload
verifier "préparation terminée (code 0)" test "$(code)" = 0
verifier "message : logiciels installés en ligne sur le poste" grep -q 'préparée depuis Linux' /tmp/moteur.log
verifier "post-installation Windows sur la clé" test -f "$CLE/postinstall/Install-Poste.ps1"
verifier "catalogue.json lisible" python3 -c "import json; json.load(open('$CLE/postinstall/catalogue.json', encoding='utf-8-sig'))"
verifier "catalogue : Office avec repli winget" python3 -c "
import json; c = json.load(open('$CLE/postinstall/catalogue.json', encoding='utf-8-sig'))
o = [i for i in c['Items'] if i['Name'] == 'Office365'][0]; assert o['WingetId'] == 'Microsoft.Office' and not o['Installer']"
# (les releases GitHub sans paquet winget, ex. PDFCraft, vont sur la clé quand leur SHA256 est publié)
verifier "catalogue : chaque logiciel winget / Office / Url absent a un repli winget" python3 -c "
import json; c = json.load(open('$CLE/postinstall/catalogue.json', encoding='utf-8-sig'))
manque = [i['Name'] for i in c['Items'] if i['Mode'] == 'Auto' and i['Type'] != 'GitHub' and not (i['WingetId'] or i['Installer'])]
assert not manque, manque"
verifier "catalogue : fuseau au format Windows" python3 -c "
import json; c = json.load(open('$CLE/postinstall/catalogue.json', encoding='utf-8-sig')); assert c['Settings']['TimeZone'] == 'Greenwich Standard Time'"
verifier "ventoy.json : installation automatique de l'ISO anglaise" grep -q '/ISO/Windows11_EN_x64.iso' "$CLE/ventoy/ventoy.json"
verifier "fichier de réponse : langue en-US et clavier américain" sh -c "grep -q 'en-US' '$CLE/ventoy/script/Windows11_HorsLigne.xml' && grep -q '0409:00000409' '$CLE/ventoy/script/Windows11_HorsLigne.xml'"
verifier "fichier de réponse : XML valide" python3 -c "import xml.dom.minidom as m; m.parse('$CLE/ventoy/script/Windows11_HorsLigne.xml')"
verifier "aucun jeton {{…}} laissé dans les fichiers" sans_jeton
verifier "MANIFEST.sha256 vérifiable" manifeste_valide
verifier "fichiers personnels intacts" grep -qx 'mes notes' "$CLE/Perso/notes.txt"

# ------------------------------------------------------------------------- 3. clé double système
etape "Clé double système : ISO Linux déjà sur la clé, puis passe Windows"
mkdir -p /kit/fausse-iso && truncate -s 2M /kit/fausse-iso/ubuntu.iso && printf 'CD001' | dd of=/kit/fausse-iso/ubuntu.iso bs=1 seek=32769 conv=notrunc 2>/dev/null
mkdir -p "$CLE/ISO/Linux/Ubuntu" && cp /kit/fausse-iso/ubuntu.iso "$CLE/ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso"
printf '%s *%s\n' "$(sha256sum < "$CLE/ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso" | cut -d' ' -f1)" 'ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso' >> "$CLE/MANIFEST.sha256"
moteur -Systeme Windows -Usage Developpement -SkipDownload
verifier "préparation terminée (code 0)" test "$(code)" = 0
verifier "post-installation Windows présente" test -f "$CLE/postinstall/Install-Poste.ps1"
verifier "post-installation Linux conservée (Ubuntu est sur la clé)" test -f "$CLE/linux/installer-poste.sh"
verifier "kit.conf : usage développement, fuseau au format Linux (Zone/Ville)" sh -c "grep -qx 'KIT_USAGE=Developpement' '$CLE/linux/kit.conf' && grep -Eqx 'KIT_TZ=[A-Za-z_]+/[A-Za-z_]+' '$CLE/linux/kit.conf'"
verifier "VS Code au catalogue Windows avec ses extensions" python3 -c "
import json; c = json.load(open('$CLE/postinstall/catalogue.json', encoding='utf-8-sig'))
v = [i for i in c['Items'] if i['Name'] == 'VSCode'][0]; assert v['PostAction'] == 'VSCodeExtensions' and v['WingetId']"
verifier "LISEZMOI du système principal (Windows)" grep -q 'Windows' "$CLE/LISEZMOI.txt"
verifier "ISO Linux intacte" test -f "$CLE/ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso"

# ------------------------------------------------------------------------- 4. garde-fous
etape "Garde-fous"
LOOP_KIT="$LOOP"
moteur -Systeme Linux -Usage Bureautique -InstallerVentoy -Disque "$LOOP_KIT" -ConfirmerEffacement "EFFACER-$(basename "$LOOP_KIT")"
verifier "effacement d'un disque non USB refusé (code 2)" test "$(code)" = 2
verifier "message de refus explicite" grep -q "refusé" /tmp/moteur.log
verifier "données intactes après le refus" grep -qx 'mes notes' "$CLE/Perso/notes.txt"
moteur -Systeme Linux -Usage Bureautique -InstallerVentoy -Disque "$LOOP_KIT" -ConfirmerEffacement "EFFACER"
verifier "confirmation incomplète refusée (code 2)" test "$(code)" = 2
creer_cle DONNEES non
echo "important" > "$CLE/compta.ods"
moteur -Systeme Linux -Usage Bureautique -SkipDownload
verifier "clé non Ventoy refusée (code 2)" test "$(code)" = 2
verifier "rien écrit sur la clé non Ventoy" sh -c "test ! -e '$CLE/MANIFEST.sha256' && test ! -e '$CLE/linux' && grep -qx important '$CLE/compta.ods'"
creer_cle MACLE oui
moteur -Systeme Linux -Usage Bureautique -SkipDownload
verifier "clé Ventoy renommée reconnue grâce à VTOYEFI (code 0)" test "$(code)" = 0

# ------------------------------------------------------------------------- 5. assistant universel
etape "Assistant universel : création de clé (PowerShell, même page que sous Windows)"
creer_cle Ventoy oui
pwsh -NoProfile -File ./Assistant-Web.ps1 -SansNavigateur -Port 8765 -Jeton jeton-test -Simuler > /tmp/web.log 2>&1 &
WEB=$!
for _ in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:8765/ && break; sleep 0.5; done
J=(-H 'X-Alchemist-Jeton: jeton-test')
api() { curl -s "${J[@]}" "$@"; }
statut() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
verifier "page servie" sh -c "curl -s http://127.0.0.1:8765/ | grep -q 'Alchemist'"
verifier "API refusée sans jeton (403)" test "$(statut http://127.0.0.1:8765/api/etat)" = 403
verifier "API refusée avec un mauvais jeton (403)" test "$(statut -H 'X-Alchemist-Jeton: faux' http://127.0.0.1:8765/api/etat)" = 403
verifier "API refusée depuis un autre hôte (403, DNS rebinding)" test "$(statut "${J[@]}" -H 'Host: attaquant.example:8765' http://127.0.0.1:8765/api/etat)" = 403
verifier "état : mode création, hôte Linux" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-test' http://127.0.0.1:8765/api/etat | grep -q '\"mode\":\"creer\".*\"hote\":\"Linux\"'"
verifier "profils : Windows et Linux, éléments « installés en ligne » signalés" python3 -c "
import json, subprocess
d = json.loads(subprocess.run(['curl', '-s', '-H', 'X-Alchemist-Jeton: jeton-test', 'http://127.0.0.1:8765/api/profils'], capture_output=True, text=True).stdout)
p = {x['Profil']: x for x in d['profils']}
assert set(p) == {'linux-bureautique', 'linux-developpement', 'windows11-bureautique', 'windows11-developpement'}
w = p['windows11-bureautique']; assert any(i['SurLePoste'] for i in w['Items']) and not any(i['SurLePoste'] for i in w['Items'] if i['Type'] == 'WindowsIso')
assert [l['Code'] for l in w['Langues']] == ['de', 'en', 'es', 'fr', 'pt']"
verifier "clés : la clé Ventoy factice est trouvée" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-test' http://127.0.0.1:8765/api/cles | grep -q '$CLE'"
verifier "lancer : profil forgé refusé" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-test' -d '{\"profil\":\"../../etc\",\"elements\":[\"Ubuntu\"],\"cle\":{\"mode\":\"existante\",\"racine\":\"$CLE\"}}' http://127.0.0.1:8765/api/lancer | grep -q 'Profil inconnu'"
verifier "lancer : effacement d'un disque non USB refusé" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-test' -d '{\"profil\":\"linux-bureautique\",\"elements\":[\"Ubuntu\"],\"cle\":{\"mode\":\"neuve\",\"disque\":\"$LOOP\",\"confirmation\":\"EFFACER\"}}' http://127.0.0.1:8765/api/lancer | grep -q 'refusé'"
verifier "lancer : effacement sans confirmation refusé" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-test' -d '{\"profil\":\"linux-bureautique\",\"elements\":[\"Ubuntu\"],\"cle\":{\"mode\":\"neuve\",\"disque\":\"$LOOP\",\"confirmation\":\"oui\"}}' http://127.0.0.1:8765/api/lancer | grep -q 'EFFACER'"
api -d "{\"profil\":\"windows11-bureautique\",\"elements\":[\"Windows11\",\"Firefox\",\"Ubuntu\"],\"langue\":\"de\",\"cle\":{\"mode\":\"existante\",\"racine\":\"$CLE\"}}" http://127.0.0.1:8765/api/lancer >/tmp/lancer.json
verifier "lancer : préparation démarrée" grep -q '"ok":true' /tmp/lancer.json
for _ in $(seq 1 240); do api 'http://127.0.0.1:8765/api/journal?depuis=0' > /tmp/journal.json; grep -q '"actif":false' /tmp/journal.json && break; sleep 1; done
verifier "journal suivi jusqu'à la fin, avec le rapport du moteur" python3 -c "
import json; d = json.load(open('/tmp/journal.json')); assert not d['actif'] and d['code'] in (0, 1, 3), d['code']
t = '\n'.join(d['lignes']); assert 'RAPPORT FINAL' in t and 'Langue du contenu : de' in t and 'SIMULATION' in t, t[-800:]"
verifier "simulation : rien écrit sur la clé" test ! -e "$CLE/MANIFEST.sha256"
kill "$WEB" 2>/dev/null

etape "Assistant universel : post-installation Linux (Python, sans PowerShell sur le poste)"
moteur -Systeme Linux -Usage Developpement -SkipDownload
verifier "assistant de post-installation sur la clé" sh -c "test -f '$CLE/linux/assistant-poste.py' && test -f '$CLE/linux/alchemist.html'"
verifier "même page que l'assistant de création" cmp -s "$CLE/linux/alchemist.html" /kit/web/alchemist.html
python3 "$CLE/linux/assistant-poste.py" --sans-navigateur --port 8766 --jeton jeton-poste > /tmp/poste.log 2>&1 &
POSTE=$!
for _ in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:8766/ && break; sleep 0.5; done
P=(-H 'X-Alchemist-Jeton: jeton-poste')
verifier "poste : API refusée sans jeton (403)" test "$(statut http://127.0.0.1:8766/api/etat)" = 403
verifier "poste : API refusée depuis un autre hôte (403)" test "$(statut "${P[@]}" -H 'Host: attaquant.example:8766' http://127.0.0.1:8766/api/etat)" = 403
verifier "poste : usage lu dans kit.conf (développement)" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-poste' http://127.0.0.1:8766/api/etat | grep -q '\"usage\": \"developpement\"'"
verifier "poste : composants avec choix par défaut (VS Code coché en développement)" python3 -c "
import json, subprocess
d = json.loads(subprocess.run(['curl', '-s', '-H', 'X-Alchemist-Jeton: jeton-poste', 'http://127.0.0.1:8766/api/composants'], capture_output=True, text=True).stdout)
c = {x['id']: x for x in d['composants']}; assert len(c) > 30 and c['vscode']['defautDev'] and not c['vscode']['defautBur']"
verifier "poste : composant inconnu refusé" sh -c "curl -s -H 'X-Alchemist-Jeton: jeton-poste' -d '{\"elements\":[\"rm -rf\"],\"usage\":\"bureautique\"}' http://127.0.0.1:8766/api/lancer | grep -q 'Aucun composant'"
useradd -m testeur 2>/dev/null || true
curl -s "${P[@]}" -d '{"elements":["sauvegarde","polices"],"usage":"bureautique"}' http://127.0.0.1:8766/api/lancer > /tmp/lancer-poste.json
verifier "poste : installation RÉELLE lancée (Timeshift, polices)" grep -q '"ok": true' /tmp/lancer-poste.json
for _ in $(seq 1 600); do curl -s "${P[@]}" 'http://127.0.0.1:8766/api/journal?depuis=0' > /tmp/journal-poste.json; grep -q '"actif": false' /tmp/journal-poste.json && break; sleep 1; done
verifier "poste : installation terminée sans échec (code 0)" python3 -c "
import json; d = json.load(open('/tmp/journal-poste.json')); assert d['code'] == 0, '\n'.join(d['lignes'][-25:])"
verifier "poste : Timeshift réellement installé" command -v timeshift
verifier "poste : polices compatibles Office installées (Carlito)" sh -c "fc-list 2>/dev/null | grep -qi carlito || dpkg -s fonts-crosextra-carlito"
verifier "poste : journal sans codes de couleur" sh -c "! grep -q 'u001b' /tmp/journal-poste.json"
kill "$POSTE" 2>/dev/null

# ------------------------------------------------------------------------- 6. sources officielles (option)
if [ "$RESEAU" = 1 ]; then
  etape "Sources officielles (simulation, rien n'est téléchargé)"
  moteur -Systeme Linux -Usage Developpement -Only Ubuntu,Ubuntu2404,LinuxMint,Debian,Fedora -DryRun
  verifier "Linux : 5 distributions résolues (code 0)" test "$(code)" = 0
  grep -E 'Ubuntu|Debian|Mint|Fedora' /tmp/moteur.log | grep -E 'A_TELECHARGER|à télécharger' | sed 's/^/         /' | head -8
  moteur -Systeme Windows -Usage Bureautique -DryRun
  if [ "$(code)" = 0 ]; then ok "Windows depuis Linux : lien officiel Microsoft obtenu (Fido)"
  else
    if grep -qE 'Sentinel|715-123130' /tmp/moteur.log && ! grep -q 'not recognized' /tmp/moteur.log; then echo "  INFO   Windows : Microsoft a refusé Fido (715-123130, blocage connu) : lien manuel dans l'assistant"; else ko "Windows depuis Linux (simulation)"; tail -n 15 /tmp/moteur.log; fi
  fi
fi

umount "$CLE"; losetup -d "$LOOP" 2>/dev/null
echo
if [ "$KO" -eq 0 ]; then echo "Tous les tests sont passés ($OK)."
else echo "$KO test(s) en échec sur $((OK + KO)) :"; printf '  - %s\n' "${ECHECS[@]}"; echo "Dernier journal du moteur :"; tail -n 25 /tmp/moteur.log; fi
exit "$KO"
DEDANS

mkdir -p "$TRAVAIL/img"
docker run --rm --privileged -v "$RACINE:/src:ro" -v "$TRAVAIL:/t" -v "$TRAVAIL/img:/img" "$IMAGE" bash /t/dedans.sh "$RESEAU"
