#!/bin/bash
# sauvegarde incrementale de /srv et /etc, une version datee par execution (B1)
# usage : sudo sauvegarde.sh

set -euo pipefail
shopt -s nullglob

DEST=/sauvegardes
SOURCES=(/srv /etc)
GARDER=7
# version interrompue, reprise par l'execution suivante
EN_COURS="$DEST/en_cours"

erreur() { echo "ERREUR : $*" >&2; exit 1; }
info()   { echo "[sauvegarde] $*"; }

main() {
    [[ $EUID -eq 0 ]] || erreur "ce script doit être lancé en root"
    [[ $# -eq 0 ]] || erreur "usage : $0 (sans argument)"
    # disque absent : on remplirait / a la place
    mountpoint -q "$DEST" || erreur "$DEST n'est pas monté"

    local version versions precedente=() i
    version="$DEST/$(date +%Y-%m-%d_%H%M%S)"
    [[ ! -e $version ]] || erreur "$version existe déjà"
    # tri par nom = tri chronologique
    versions=("$DEST"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9])
    # fichiers inchanges : lien dur vers la version precedente, rien n'est recopie
    [[ ${#versions[@]} -eq 0 ]] || precedente=(--link-dest="${versions[-1]}")

    rsync -aAXH --numeric-ids --delete "${precedente[@]}" "${SOURCES[@]}" "$EN_COURS/" \
        || erreur "rsync a échoué (code $?), version incomplète laissée dans $EN_COURS"
    mv "$EN_COURS" "$version"
    info "version ${version##*/} créée"

    versions+=("$version")
    for (( i = 0; i < ${#versions[@]} - GARDER; i++ )); do
        rm -rf -- "${versions[i]}"
        info "version ${versions[i]##*/} supprimée (on garde les $GARDER dernières)"
    done
}

main "$@"
