# Feuille de route d'Alchemist

Objectif : **une clé, un assistant**, pour transformer n'importe quel PC en poste prêt à l'emploi —
Windows ou Linux — selon le **système**, l'**usage** et le **profil de l'utilisateur**, avec une attention
particulière aux développeurs qui passent de Windows à Linux.

Versions : [SemVer](https://semver.org/lang/fr/). Avancement réel : [CHANGELOG](CHANGELOG.md).

## Fait

- [x] **v1.0** — Windows 11 hors ligne, Microsoft 365 ou suites gratuites, logiciels, pilotes, ClamAV,
      assistants graphiques FR/EN, multiboot Linux.
- [x] **v1.1** — Installation et mise à jour de Ventoy depuis le kit, avec garde-fous.
- [x] **v1.2** — Alchemist : parcours Système → Usage → Versions, profils hérités, stack développeur Windows,
      post-installation Linux multi-distributions (Ubuntu, Mint, Debian, Fedora), Microsoft 365 sous Linux,
      création (GIMP, Inkscape, Krita, Kdenlive, ArtCraft…), moteur et assistant sous Linux, tests Linux en CI.
- [x] **v1.3** — Microsoft 365 de bureau intégral sous Linux (LinOffice : Windows minimal, Podman sans root, KVM),
      installation réelle de la stack Linux et d'Office 365 testée sur GitHub Actions.
- [x] **v1.4** — Conteneurs sans licence payante : Docker Engine natif + Podman Desktop + Trivy à la place de
      Docker Desktop (Linux et Windows), rotation des journaux Docker, analyse Trivy du dépôt en CI.

## v1.5 — Linux sans effort

- [ ] **Installation Linux automatisée** depuis le menu Ventoy : Ubuntu *autoinstall* (cloud-init), Fedora
      *kickstart*, Debian *preseed* — langue, clavier, compte, usage pré-réglés.
- [ ] Lancement automatique de la post-installation au premier démarrage.
- [ ] **Paquets Linux hors ligne** sur la clé (.deb / .rpm / Flatpak bundles) pour les postes sans Internet.
- [ ] Noms lisibles dans le menu Ventoy (`menu_alias`) et persistance pour les systèmes « live ».

## v1.6 — Nouveaux usages

| Usage | Contenu envisagé |
| --- | --- |
| Statistiques / données | R + RStudio, Python data (Jupyter, pandas, Polars via uv), JASP, PSPP, QGIS, DuckDB, DBeaver |
| Graphisme / vidéo | Création par défaut : GIMP, Krita, Inkscape, Kdenlive, Blender, OBS, DaVinci Resolve (guidé) |
| Enseignement / école | suites bureautiques, outils pédagogiques, contrôle parental |

## v2.0 — Migration et interface universelle

- [ ] **Assistant de migration Windows → Linux** : données utilisateur, navigateurs, clés SSH, `.gitconfig`,
      extensions VS Code, liste des logiciels Windows → équivalents Linux proposés automatiquement.
- [ ] Interface graphique unique multiplateforme (Avalonia UI ou interface web locale) remplaçant WinForms
      et zenity ; la ligne de commande reste identique.
- [ ] Préparer aussi les clés Windows complètes depuis Linux (sources directes sans winget).
- [ ] Autres langues d'interface (ES, DE, PT, AR…) et traduction des journaux.

## Idées

- Profils d'entreprise (domaine, VPN, imprimantes), inventaire matériel exporté (CSV/JSON).
- Packs de pilotes hors ligne sélectifs (réseau, chipset) pour SDIO.
- Signature des archives de release (Sigstore / cosign).
