# Contribuer

## Flux de travail

1. Prendre (ou créer) le ticket de la tâche dans le Kanban et le passer en **En cours**.
2. Travailler sur une branche `phase-N/sujet` (ex. `phase-3/reseau-openstack`), ou directement
   sur `main` pour de la documentation simple.
3. Messages de commit en français, avec le numéro du ticket : `Ajoute le réseau ows-net (#4)`.
4. Fermer le ticket (`Closes #N`) quand le critère « Terminé quand » est atteint : il passe en **Fait**.

## Où ranger quoi

- Un dossier = un domaine (voir le README principal). Chaque dossier a un `README.md` qui
  décrit son contenu : le mettre à jour quand on y ajoute des fichiers.
- Scripts : `scripts/NN-verbe-objet.sh`, en Bash, `set -euo pipefail`, idempotents si possible.
- Documentation : `docs/NN-sujet.md`, en français ; schémas dans `docs/images/`.

## Secrets

Jamais de secret versionné. Fournir un fichier `*.example` avec des valeurs factices et lire
les vraies valeurs depuis l'environnement, `~/.config/openstack/clouds.yaml` ou Vault.
