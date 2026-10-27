# Contribuer

Merci de votre intérêt ! Le kit doit rester **fiable, sûr et simple** pour les techniciens.

## Méthode de travail

### Branches : GitHub Flow

- `main` est **toujours stable et publiable** ; on n'y pousse jamais directement.
- Une branche par évolution, créée depuis `main` :
  - `feat/<sujet>` : nouvelle fonctionnalité (ex. `feat/profil-developpement`)
  - `fix/<sujet>` : correction (ex. `fix/detection-office`)
  - `docs/<sujet>`, `chore/<sujet>`, `refactor/<sujet>`
- Ouverture d'une **Pull Request** vers `main` : l'analyse automatique (CI) doit être verte et la
  description doit indiquer ce qui a été testé.

### Messages de commit : Conventional Commits

Format : `type(portée): résumé à l'impératif`, en français.

| Type | Usage | Effet sur la version |
| --- | --- | --- |
| `feat` | nouvelle fonctionnalité | MINEUR |
| `fix` | correction de bug | CORRECTIF |
| `docs` | documentation | — |
| `refactor` | restructuration sans changement de comportement | — |
| `perf` | performance | CORRECTIF |
| `test`, `ci`, `chore` | tests, intégration continue, maintenance | — |
| `feat!` / `BREAKING CHANGE:` | changement incompatible | MAJEUR |

Portées usuelles : `moteur`, `interface`, `poste`, `profil`, `langue`, `ci`, `doc`.
Exemple : `feat(profil): ajouter le profil développement`.

### Versions : SemVer

- Source unique : le fichier [`VERSION`](VERSION) (`MAJEUR.MINEUR.CORRECTIF`).
- **MAJEUR** : changement incompatible (paramètres, format de profil, structure de la clé).
- **MINEUR** : nouvelle fonctionnalité compatible (logiciel, profil, langue, option).
- **CORRECTIF** : correction sans nouvelle fonctionnalité.

### Publier une version

1. Mettre à jour `VERSION` et déplacer les entrées de « Non publié » vers une nouvelle section
   datée du [CHANGELOG](CHANGELOG.md) (format Keep a Changelog).
2. Commit : `chore(release): vX.Y.Z`.
3. Étiquette annotée : `git tag -a vX.Y.Z -m "vX.Y.Z"` puis `git push origin main --follow-tags`.
4. Le workflow *Publication* crée automatiquement la **GitHub Release** avec l'archive du kit et
   les notes extraites du CHANGELOG.

## Règles techniques

1. **Sources officielles uniquement** (éditeur, Microsoft, dépôt winget, releases GitHub officielles,
   sites des distributions). Jamais d'ISO modifiée, de logiciel « cracké » ni d'outil d'activation.
2. **Aucun binaire dans le dépôt** : le kit télécharge tout au moment de préparer une clé.
3. Compatibilité **Windows PowerShell 5.1 et PowerShell 7**, `Set-StrictMode -Version Latest`.
4. Fichiers `.ps1/.psm1/.psd1` en **UTF-8 avec BOM** (sinon les accents sont abîmés sous 5.1).
5. `Invoke-ScriptAnalyzer -Settings PSScriptAnalyzerSettings.psd1` sans erreur ni avertissement.
6. Ne jamais formater / repartitionner la clé ; ne toucher qu'aux fichiers listés dans le MANIFEST.
7. Tester au minimum `./tests/moteur/Test-Moteur.ps1` (sans réseau, Windows 5.1 / 7 et Linux) et
   `./Build-Kit.ps1 -DryRun` ; fenêtre classique : `-TestSansAffichage -Capture <png>`.
8. Scripts Linux : `shellcheck -S warning` sans remarque. Avec Docker : `bash tests/moteur/test-cle-factice.sh`
   (clé factice, assistants universels), `bash tests/moteur/test-ventoy-reel.sh` (création réelle et démarrage
   BIOS/UEFI dans QEMU), `bash tests/linux/test-installation-reelle.sh` (post-installation réelle). GitHub
   Actions exécute la clé factice (`tests-linux.yml`) et les essais sous Windows pour chaque destination
   (`tests-windows.yml`) ; les deux tests réels se lancent à la main (plusieurs centaines de Mo téléchargés).
9. Assistant universel (`web/alchemist.html`) : une seule page pour les deux systèmes ; toute nouvelle route
   d'API est ajoutée aux trois serveurs (`Assistant-Web.ps1`, `Assistant-Poste-Web.ps1`, `assistant-poste.py`)
   et protégée par le jeton.
10. Composant Linux : prévoir les deux familles (`paquets "noms apt" "noms dnf"`).
11. GitHub Actions : épingler chaque action par **SHA de commit complet**, version en commentaire
    (`uses: owner/action@<sha> # vX.Y.Z`) ; une étiquette peut être déplacée vers un code malveillant.
    Dependabot (`.github/dependabot.yml`) propose chaque lundi une PR groupée avec les nouveaux SHA :
    vérifier les notes de version des actions avant de la fusionner.

## Ajouter un logiciel

Ajoutez un bloc dans `config\profils\<profil>.psd1` (voir l'en-tête du fichier et le README), puis :

```powershell
.\Build-Kit.ps1 -Only MonLogiciel -DryRun
.\Build-Kit.ps1 -Only MonLogiciel
```

## Ajouter une langue d'interface

Copiez `lang\fr.psd1` et `payload\windows\postinstall\lang\fr.psd1` en `<code>.psd1` (ex. `es.psd1`)
et traduisez les valeurs (pas les clés).
