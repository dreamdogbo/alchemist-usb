# Politique de sécurité

## Versions prises en charge

| Version | Corrections de sécurité |
| --- | --- |
| 1.x (dernière) | ✅ |
| < 1.0 | ❌ |

## Signaler une vulnérabilité

Merci de **ne pas ouvrir d'issue publique** pour une faille de sécurité.
Utilisez le signalement privé de GitHub : onglet **Security → Report a vulnerability** du dépôt.
Une réponse est donnée sous 7 jours ; un correctif et une version (`fix`) sont publiés dès que possible.

## Principes du kit

- Téléchargements uniquement depuis les **sources officielles**, en HTTPS.
- Intégrité : **SHA256 publiés** (winget, GitHub, distributions Linux) toujours vérifiés ; signatures
  Authenticode contrôlées (désactivables par l'opérateur, ce qui est tracé dans le journal).
- Aucune ISO modifiée, aucun outil d'activation ou de contournement de licence.
- La clé n'est jamais formatée ; seuls les fichiers du kit (listés dans `MANIFEST.sha256`) sont modifiés.
