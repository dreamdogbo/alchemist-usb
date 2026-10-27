#!/usr/bin/env bash
# =============================================================================
#  test-ventoy-reel.sh — Création RÉELLE d'une clé depuis Linux, puis démarrage dans une VM
#
#  1. Conteneur PowerShell 7 jetable et privilégié, disque factice VIERGE (image de 8 Go) :
#     - Ventoy officiel téléchargé (dernière release stable GitHub, SHA256 publié vérifié),
#     - installé par Ventoy2Disk.sh via le moteur (Invoke-KitVentoy2Disk), clé montée
#       (Wait-KitVentoyVolume) comme pour une clé neuve,
#     - préparation réelle par Build-Kit.ps1 : clé Windows + Linux (double système), avec de VRAIS
#       téléchargements vérifiés (Chocolatey : SHA256 GitHub ; pack WMF 5.1 : empreinte fixée),
#       post-installations Windows et Linux, image personnelle.
#  2. La clé obtenue démarre dans QEMU (BIOS, et UEFI si OVMF est présent) : capture du menu Ventoy.
#
#  Le garde-fou « clé USB uniquement » n'est contourné qu'ici (disque en boucle, impossible à
#  confondre avec un disque réel) : Assert-KitVentoyTarget le refuse, ce qu'un autre test vérifie.
#
#  Usage : bash tests/moteur/test-ventoy-reel.sh [dossier des captures]
#  Prérequis : Docker (privilégié), Internet, QEMU (facultatif : sinon pas de test de démarrage).
# =============================================================================
set -Eeuo pipefail
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAPTURES="${1:-$RACINE/logs/captures-ventoy}"
IMAGE="${PWSH_IMAGE:-mcr.microsoft.com/powershell:latest}"
TRAVAIL="$(mktemp -d)"
trap 'rm -rf "$TRAVAIL"' EXIT
mkdir -p "$CAPTURES" "$TRAVAIL/img"

cat > "$TRAVAIL/dedans.sh" <<'DEDANS'
#!/usr/bin/env bash
set -Euo pipefail
apt-get update -qq >/dev/null && apt-get install -y -qq exfatprogs dosfstools fdisk parted xz-utils python3 >/dev/null 2>&1 || { echo "outils non installés"; exit 1; }
cp -r /src /kit && cd /kit
sed -n '/^cat > \/usr\/local\/bin\/lsblk/,/^EOF$/p' /kit/tests/moteur/test-cle-factice.sh | sed '1d;$d' > /usr/local/bin/lsblk && chmod +x /usr/local/bin/lsblk
OK=0; KO=0
ok() { echo "  OK     $1"; OK=$((OK + 1)); }
ko() { echo "  ÉCHEC  $1"; KO=$((KO + 1)); }
verifier() { local nom="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$nom"; else ko "$nom"; fi; }

truncate -s 8G /img/cle.img
LOOP="$(losetup -f)"; n="$(basename "$LOOP")"; [ -e "$LOOP" ] || mknod "$LOOP" b 7 "${n#loop}"
losetup -P "$LOOP" /img/cle.img
# Sans udev : nœuds des partitions créés dès que Ventoy2Disk les écrit
# (Ventoy recrée les partitions : numéros de périphérique nouveaux, nœud recréé s'il ne correspond plus)
( while true; do for p in /sys/block/"$n"/"$n"p*; do
    [ -e "$p" ] || continue; b="$(basename "$p")"; IFS=: read -r ma mi < "$p/dev" || continue
    [ "$(stat -c '%t %T' "/dev/$b" 2>/dev/null)" = "$(printf '%x %x' "$ma" "$mi")" ] || { rm -f "/dev/$b"; mknod "/dev/$b" b "$ma" "$mi" 2>/dev/null; }
  done; sleep 0.05; done ) &
NOEUDS=$!

echo "== Ventoy officiel : téléchargement vérifié et installation sur un disque vierge"
pwsh -NoProfile -Command "
  \$ErrorActionPreference = 'Stop'
  foreach (\$m in 'Report','Drive','Download','Ventoy') { Import-Module ./modules/\$m.psm1 -DisableNameChecking }
  [void](Initialize-KitLog -LogDirectory /tmp/logs)
  Initialize-KitNetwork
  \$v = Save-KitVentoy -ToolsDir /tmp/ventoy
  Invoke-KitVentoy2Disk -Exe \$v.Exe -Mode Install -Disk '$LOOP' -Label Ventoy -Confirm:\$false
  \$root = Wait-KitVentoyVolume -Disk '$LOOP' -Label Ventoy -TimeoutSec 60
  Set-Content /tmp/racine -Value \$root -NoNewline
  Set-Content /tmp/version -Value \$v.Version -NoNewline
" > /tmp/ventoy.log 2>&1
code=$?
verifier "Ventoy téléchargé (SHA256 officiel) et installé (code 0)" test "$code" = 0
grep -E 'Ventoy [0-9.]+ vérifié|terminée' /tmp/ventoy.log | sed 's/^/         /'
[ "$code" = 0 ] || { tail -n 25 /tmp/ventoy.log; kill "$NOEUDS"; exit 1; }
RACINE_CLE="$(cat /tmp/racine)"
verifier "partition VTOYEFI créée" sh -c "blkid -s LABEL -o value ${LOOP}p2 | grep -qx VTOYEFI"
verifier "partition de données exFAT « Ventoy » montée ($RACINE_CLE)" sh -c "findmnt -no FSTYPE '${RACINE_CLE%/}' | grep -qx exfat"

echo
echo "== Préparation réelle : clé Windows + Linux depuis Linux (vrais téléchargements)"
mkdir -p /tmp/iso && truncate -s 4M /tmp/iso/Outil-Depannage.iso && printf 'CD001' | dd of=/tmp/iso/Outil-Depannage.iso bs=1 seek=32769 conv=notrunc 2>/dev/null
pwsh -NoProfile -File ./Build-Kit.ps1 -Systeme Windows -Usage Developpement -Only Chocolatey,Win7_WMF51,VSCode,Office365 -IsoPersonnelle /tmp/iso/Outil-Depannage.iso -KeyPath "$RACINE_CLE" > /tmp/build.log 2>&1
code=$?
verifier "préparation terminée sans échec (code 0)" test "$code" = 0
grep -E '(OK|ÉCHEC|IGNORÉ) +[0-9.]' /tmp/build.log | grep -v '^\s*$' | sed 's/^/         /' | head -12
verifier "Chocolatey téléchargé (SHA256 publié par GitHub vérifié)" sh -c "ls '$RACINE_CLE'Logiciels/Chocolatey/chocolatey-*.msi"
verifier "pack WMF 5.1 téléchargé (empreinte fixée vérifiée)" sh -c "ls '$RACINE_CLE'Windows7/2-WMF51/*.zip"
verifier "MANIFEST.sha256 : chaque fichier vérifié par sha256sum -c" sh -c "cd '$RACINE_CLE' && sha256sum -c --quiet MANIFEST.sha256"
verifier "post-installation Windows (assistant universel inclus)" sh -c "test -f '$RACINE_CLE'postinstall/Assistant-Poste-Web.ps1 && test -f '$RACINE_CLE'postinstall/alchemist.html"
verifier "VS Code et Office au catalogue, installés en ligne sur le poste" python3 -c "
import json; c = json.load(open('${RACINE_CLE}postinstall/catalogue.json', encoding='utf-8-sig'))
n = {i['Name']: i for i in c['Items']}; assert n['VSCode']['WingetId'] and n['Office365']['WingetId'] == 'Microsoft.Office'"
verifier "image personnelle copiée dans ISO/Personnel" test -f "${RACINE_CLE}ISO/Personnel/Outil-Depannage.iso"
verifier "installation automatique de Windows déclarée à Ventoy" test -f "${RACINE_CLE}ventoy/ventoy.json"
# Ubuntu ajouté comme le ferait une passe précédente (ISO réelle trop lourde pour un test) : la passe
# suivante doit embarquer la post-installation Linux à côté de celle de Windows
mkdir -p "${RACINE_CLE}ISO/Linux/Ubuntu" && cp /tmp/iso/Outil-Depannage.iso "${RACINE_CLE}ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso"
printf '%s *ISO/Linux/Ubuntu/ubuntu-26.04-desktop-amd64.iso\n' "$(sha256sum < /tmp/iso/Outil-Depannage.iso | cut -d' ' -f1)" >> "${RACINE_CLE}MANIFEST.sha256"
pwsh -NoProfile -File ./Build-Kit.ps1 -Systeme Windows -Usage Developpement -Only Chocolatey,Win7_WMF51,VSCode,Office365 -KeyPath "$RACINE_CLE" > /tmp/build2.log 2>&1
verifier "relance : rien de retéléchargé (code 0)" sh -c "test $? = 0 && grep -q 'déjà à jour' /tmp/build2.log"
verifier "double système : post-installation Linux ajoutée" sh -c "test -f '${RACINE_CLE}linux/installer-poste.sh' && test -f '${RACINE_CLE}linux/assistant-poste.py'"

echo
echo "== Mise à jour de Ventoy sur la clé, données conservées"
pwsh -NoProfile -Command "
  \$ErrorActionPreference = 'Stop'
  foreach (\$m in 'Report','Drive','Download','Ventoy') { Import-Module ./modules/\$m.psm1 -DisableNameChecking }
  [void](Initialize-KitLog -LogDirectory /tmp/logs)
  \$v = Save-KitVentoy -ToolsDir /tmp/ventoy
  Invoke-KitVentoy2Disk -Exe \$v.Exe -Mode Update -Disk '$LOOP' -Confirm:\$false
  [void](Wait-KitVentoyVolume -Disk '$LOOP' -Label Ventoy -TimeoutSec 60)
" > /tmp/maj.log 2>&1
verifier "mise à jour de Ventoy (code 0)" test $? = 0
RACINE_CLE="$(findmnt -no TARGET "${LOOP}p1" | head -1)/"
verifier "données intactes après la mise à jour" sh -c "cd '$RACINE_CLE' && sha256sum -c --quiet MANIFEST.sha256"

sync; umount "${LOOP}p1" 2>/dev/null; kill "$NOEUDS" 2>/dev/null; losetup -d "$LOOP"
echo "VENTOY=$(cat /tmp/version)"
echo "BILAN $OK $KO"
exit "$KO"
DEDANS

echo "== Conteneur : création réelle de la clé"
docker run --rm --privileged -e GITHUB_TOKEN -v "$RACINE:/src:ro" -v "$TRAVAIL:/t" -v "$TRAVAIL/img:/img" "$IMAGE" bash /t/dedans.sh | tee "$TRAVAIL/sortie.log"
code="${PIPESTATUS[0]}"
[ "$code" = 0 ] || { echo "Création de la clé en échec ($code)."; exit 1; }

# ----------------------------------------------------------------------------- démarrage de la clé
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then echo "QEMU absent : test de démarrage ignoré."; exit 0; fi
echo
echo "== Démarrage de la clé dans une machine virtuelle (QEMU)"
accel=(); [ -w /dev/kvm ] && accel=(-enable-kvm)
demarrer() {   # $1 = nom, reste = options du micrologiciel
  local nom="$1"; shift
  local qmp="$TRAVAIL/qmp-$nom.sock"
  qemu-system-x86_64 "${accel[@]}" -m 1024 -display none -qmp "unix:$qmp,server,nowait" \
    -drive "file=$TRAVAIL/img/cle.img,format=raw,if=ide,snapshot=on" "$@" >/dev/null 2>&1 &
  local vm=$!
  sleep 25
  python3 - "$qmp" "$TRAVAIL/$nom.ppm" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw")
f.readline()
for cmd in ({"execute": "qmp_capabilities"}, {"execute": "screendump", "arguments": {"filename": sys.argv[2]}}):
    f.write(json.dumps(cmd) + "\n"); f.flush(); f.readline()
PY
  kill "$vm" 2>/dev/null; wait "$vm" 2>/dev/null
  # PPM -> PNG (Python seul) et contrôle : écran non uniforme (menu affiché)
  python3 - "$TRAVAIL/$nom.ppm" "$CAPTURES/demarrage-$nom.png" <<'PY'
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
parts = d.split(b"\n", 3); w, h = map(int, parts[1].split()); px = parts[3]
raw = b"".join(b"\x00" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
open(sys.argv[2], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
couleurs = len(set(px[i:i + 3] for i in range(0, len(px), 3 * 97)))
print("  OK     écran capturé (%dx%d, %d couleurs)" % (w, h, couleurs) if couleurs > 3 else "  ÉCHEC  écran vide")
sys.exit(0 if couleurs > 3 else 1)
PY
}
demarrer bios
if [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ]; then
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$TRAVAIL/vars.fd"
  demarrer uefi -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive "if=pflash,format=raw,file=$TRAVAIL/vars.fd"
fi
echo "Captures : $CAPTURES"
