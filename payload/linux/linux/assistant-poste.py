#!/usr/bin/env python3
# =============================================================================
#  assistant-poste.py — Assistant universel de post-installation Linux
#  Alchemist by dreamdogbo — https://github.com/dreamdogbo/alchemist-usb
#
#  Même interface que l'assistant de création de clé et que la post-installation Windows
#  (page web locale alchemist.html ouverte dans le navigateur). Python 3 seul (présent sur
#  Ubuntu, Linux Mint, Debian et Fedora de bureau) : PowerShell n'est pas nécessaire sur le poste.
#  Le travail est fait par installer-poste.sh (droits administrateur demandés par pkexec).
#  La page n'est accessible que depuis ce poste (127.0.0.1, jeton aléatoire).
#
#  Usage : bash lancer.sh      (ou : python3 assistant-poste.py [--sans-navigateur] [--port N])
# =============================================================================
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(DIR, "installer-poste.sh")
INACTIVITE = 180  # secondes sans appel de la page (et sans tâche) avant l'arrêt


def lire_conf():
    conf = {}
    try:
        with open(os.path.join(DIR, "kit.conf"), encoding="utf-8") as f:
            for ligne in f:
                if "=" in ligne and not ligne.lstrip().startswith("#"):
                    k, v = ligne.strip().split("=", 1)
                    conf[k] = v.strip().strip('"')
    except OSError:
        pass
    return conf


def distribution():
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            for ligne in f:
                if ligne.startswith("PRETTY_NAME="):
                    return ligne.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return "Linux"


def internet():
    import socket
    for hote in ("flathub.org", "github.com", "deb.debian.org"):
        try:
            socket.create_connection((hote, 443), timeout=4).close()
            return True
        except OSError:
            continue
    return False


class Tache:
    """Processus installer-poste.sh, sortie lue au fil de l'eau."""

    def __init__(self):
        self.verrou = threading.Lock()
        self.proc = None
        self.lignes = []
        self.code = None
        self.fini = True
        self.arretee = False

    def actif(self):
        return not self.fini

    def lancer(self, commande):
        with self.verrou:
            if self.actif():
                raise RuntimeError("Une installation est déjà en cours.")
            self.lignes, self.code, self.fini, self.arretee = [], None, False, False
            env = dict(os.environ, TERM="dumb")
            self.proc = subprocess.Popen(commande, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                         env=env, start_new_session=True)
        threading.Thread(target=self._lire, daemon=True).start()

    def _lire(self):
        ansi = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
        for brut in iter(self.proc.stdout.readline, b""):
            ligne = ansi.sub("", brut.decode("utf-8", "replace")).rstrip("\r\n")
            with self.verrou:
                self.lignes.append(ligne)
        code = self.proc.wait()
        with self.verrou:
            self.code = None if self.arretee else code
            self.fini = True

    def etat(self, depuis):
        with self.verrou:
            if depuis < 0 or depuis > len(self.lignes):
                depuis = 0
            return {"lignes": self.lignes[depuis:], "suivant": len(self.lignes), "actif": not self.fini, "code": self.code}

    def arreter(self):
        if not self.proc or self.fini:
            return
        self.arretee = True
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except PermissionError:
            raise RuntimeError("Arrêt impossible : l'installation tourne en administrateur. Fermez la fenêtre de terminal ou attendez la fin.")
        except ProcessLookupError:
            pass


TACHE = Tache()
CONF = lire_conf()
JETON = ""
PORT = 0
DERNIER_APPEL = time.time()
INTERNET = None


def composants():
    sortie = subprocess.run(["bash", SCRIPT, "--liste-tsv"], capture_output=True, text=True, check=True).stdout
    liste = []
    for ligne in sortie.splitlines():
        champs = ligne.split("\t")
        if len(champs) < 5:
            continue
        cid, cat, bur, dev, lib = champs[:5]
        liste.append({"id": cid, "nom": cid, "categorie": cat, "description": lib, "etat": "", "classe": "",
                      "outil": False, "defautBur": bur == "1", "defautDev": dev == "1"})
    return liste


def commande_installation(ids, usage):
    base = ["bash", SCRIPT, "-u", usage, "-c", ",".join(ids), "-y"]
    if os.geteuid() == 0:
        return base
    if not shutil.which("pkexec"):
        raise RuntimeError("pkexec est introuvable : lancez « sudo bash installer-poste.sh » dans un terminal.")
    # pkexec : environnement minimal ; l'utilisateur et sa session sont transmis au script
    import pwd
    env = ["env", "SUDO_USER=" + pwd.getpwuid(os.getuid()).pw_name, "PATH=" + os.environ.get("PATH", "/usr/sbin:/usr/bin:/sbin:/bin")]
    for k in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "LANG", "GITHUB_TOKEN"):
        if os.environ.get(k):
            env.append(k + "=" + os.environ[k])
    return ["pkexec"] + env + base


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "Alchemist"

    def log_message(self, *args):
        pass

    def _repondre(self, statut, corps, type_="application/json; charset=utf-8"):
        donnees = corps.encode("utf-8") if isinstance(corps, str) else json.dumps(corps, ensure_ascii=False).encode("utf-8")
        self.send_response(statut)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(donnees)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(donnees)

    def _controle(self):
        if self.headers.get("Host", "") not in ("127.0.0.1:%d" % PORT, "localhost:%d" % PORT):
            self._repondre(403, {"erreur": "hôte refusé"})
            return False
        return True

    def _api(self):
        global DERNIER_APPEL
        if not secrets.compare_digest(self.headers.get("X-Alchemist-Jeton", ""), JETON):
            self._repondre(403, {"erreur": "jeton invalide : rouvrez l'assistant avec lancer.sh"})
            return False
        DERNIER_APPEL = time.time()
        return True

    def do_GET(self):
        global INTERNET
        if not self._controle():
            return
        chemin, _, requete = self.path.partition("?")
        if chemin in ("/", "/index.html"):
            page = trouver_page()
            with open(page, encoding="utf-8") as f:
                return self._repondre(200, f.read(), "text/html; charset=utf-8")
        if not chemin.startswith("/api/"):
            return self._repondre(404, {"erreur": "introuvable"})
        if not self._api():
            return
        try:
            if chemin == "/api/ping":
                return self._repondre(200, {"ok": True})
            if chemin == "/api/etat":
                if INTERNET is None:
                    INTERNET = internet()
                usage = CONF.get("KIT_USAGE", "bureautique").lower().replace("é", "e")
                return self._repondre(200, {"mode": "poste", "hote": "Linux", "version": CONF.get("KIT_VERSION", ""),
                                            "distribution": distribution(), "usage": usage, "usages": True,
                                            "internet": INTERNET, "options": [], "travail": TACHE.etat(0)})
            if chemin == "/api/composants":
                usage = CONF.get("KIT_USAGE", "bureautique").lower().replace("é", "e")
                return self._repondre(200, {"composants": composants(), "usage": usage})
            if chemin == "/api/journal":
                m = re.search(r"depuis=(\d+)", requete)
                return self._repondre(200, TACHE.etat(int(m.group(1)) if m else 0))
            return self._repondre(404, {"erreur": "introuvable"})
        except Exception as e:  # erreur renvoyée à la page, l'assistant reste ouvert
            return self._repondre(400, {"erreur": str(e)})

    def do_POST(self):
        if not self._controle() or not self._api():
            return
        try:
            n = int(self.headers.get("Content-Length", "0") or 0)
            d = json.loads(self.rfile.read(n).decode("utf-8") or "{}") if 0 < n <= 1048576 else {}
            chemin = self.path.partition("?")[0]
            if chemin == "/api/lancer":
                connus = {c["id"] for c in composants()}
                ids = [str(x) for x in d.get("elements", []) if str(x) in connus]
                if not ids:
                    raise RuntimeError("Aucun composant choisi.")
                usage = str(d.get("usage") or "bureautique")
                if usage not in ("bureautique", "developpement"):
                    raise RuntimeError("Usage inconnu.")
                TACHE.lancer(commande_installation(ids, usage))
                return self._repondre(200, {"ok": True})
            if chemin == "/api/arreter":
                TACHE.arreter()
                return self._repondre(200, {"ok": True})
            if chemin == "/api/ouvrir":
                cible = "/var/log/kit-poste" if os.path.isdir("/var/log/kit-poste") else os.path.expanduser("~")
                subprocess.Popen(["xdg-open", cible], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return self._repondre(200, {"ok": True})
            return self._repondre(404, {"erreur": "introuvable"})
        except Exception as e:
            return self._repondre(400, {"erreur": str(e)})


def trouver_page():
    for p in (os.path.join(DIR, "alchemist.html"), os.path.join(DIR, "..", "..", "..", "web", "alchemist.html")):
        if os.path.isfile(p):
            return p
    raise FileNotFoundError("alchemist.html introuvable à côté de l'assistant")


def ouvrir_navigateur(url):
    commande = ["xdg-open", url]
    # Lancé avec sudo : le navigateur s'ouvre pour l'utilisateur du bureau, pas pour root
    if os.geteuid() == 0 and os.environ.get("SUDO_USER"):
        commande = ["sudo", "-u", os.environ["SUDO_USER"]] + commande
    try:
        subprocess.Popen(commande, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        print("Ouvrez cette adresse dans le navigateur : " + url)


def main():
    global JETON, PORT
    args = sys.argv[1:]
    sans_navigateur = "--sans-navigateur" in args
    port = int(args[args.index("--port") + 1]) if "--port" in args else 0
    JETON = args[args.index("--jeton") + 1] if "--jeton" in args else secrets.token_hex(16)
    trouver_page()
    serveur = ThreadingHTTPServer(("127.0.0.1", port), Gestionnaire)
    PORT = serveur.server_address[1]
    url = "http://127.0.0.1:%d/#%s" % (PORT, JETON)
    print("ALCHEMIST-URL " + url, flush=True)
    if not sans_navigateur:
        ouvrir_navigateur(url)
    threading.Thread(target=serveur.serve_forever, daemon=True).start()
    try:
        while time.time() - DERNIER_APPEL < INACTIVITE or TACHE.actif():
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    serveur.shutdown()


if __name__ == "__main__":
    main()
