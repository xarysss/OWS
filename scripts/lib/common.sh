#!/usr/bin/env bash
# Fonctions partagées (poste d'administration ET nœuds).
set -Eeuo pipefail

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[ATTENTION]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERREUR]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "à lancer en root (sudo)"; }

# "nom=ip nom=ip" -> lignes "nom ip"
pairs() { tr ' ' '\n' <<<"$1" | sed '/^$/d' | tr '=' ' '; }
