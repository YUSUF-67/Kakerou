#!/bin/bash
# comptes, groupes, /srv + ACL et cles SSH depuis comptes.csv (C1, C2)
# usage : sudo ./creer_comptes.sh [comptes.csv]

set -euo pipefail

DEPOT="$(cd "$(dirname "$0")" && pwd)"
CSV="${1:-$DEPOT/comptes.csv}"
CLES="$DEPOT/config/cles"
ENTETE='login;nom;groupe_principal;groupes_secondaires'
EXPIRATION_FREELANCE="2027-01-31"

erreur() { echo "ERREUR : $*" >&2; exit 1; }
info()   { echo "[creer_comptes] $*"; }

verifier_prerequis() {
    [[ $EUID -eq 0 ]] || erreur "ce script doit être lancé en root"
    [[ $# -le 1 ]] || erreur "usage : $0 [comptes.csv]"
    [[ -r $CSV ]] || erreur "fichier introuvable : $CSV"
    command -v setfacl >/dev/null || erreur "paquet acl manquant (apt install acl)"
    local premiere
    premiere="$(head -n1 "$CSV" | tr -d '\r')"
    [[ $premiere == "$ENTETE" ]] || erreur "en-tête invalide dans $CSV (attendu : $ENTETE)"
}

creer_groupe() {
    getent group "$1" >/dev/null || { groupadd "$1"; info "groupe $1 créé"; }
}

installer_cle() {
    local login=$1 home
    [[ -f $CLES/$login.pub ]] || return 0
    home="$(getent passwd "$login" | cut -d: -f6)"
    install -d -m 700 -o "$login" -g "$(id -gn "$login")" "$home/.ssh"
    install -m 600 -o "$login" -g "$(id -gn "$login")" "$CLES/$login.pub" "$home/.ssh/authorized_keys"
}

creer_compte() {
    local login=$1 nom=$2 principal=$3 secondaires=$4
    [[ $login =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || erreur "login invalide : '$login'"
    creer_groupe "$principal"
    local g
    for g in ${secondaires//,/ }; do creer_groupe "$g"; done

    if id "$login" >/dev/null 2>&1; then
        usermod -g "$principal" -G "$secondaires" -c "$nom" "$login"
    else
        useradd -m -s /bin/bash -g "$principal" -G "$secondaires" -c "$nom" "$login"
        info "compte $login créé"
    fi
    chmod 700 "$(getent passwd "$login" | cut -d: -f6)"

    if [[ $principal == freelance ]]; then
        chage -E "$EXPIRATION_FREELANCE" "$login"
    fi
    installer_cle "$login"
}

# mot de passe admin pour sudo, demande a la console (jamais dans le depot)
demander_mdp_admins() {
    local login
    for login in $(awk -F';' '$3 == "admins" { print $1 }' "$CSV"); do
        if [[ $(passwd -S "$login" | awk '{print $2}') != P ]]; then
            if [[ -t 0 ]]; then
                info "définir le mot de passe de l'administrateur $login"
                passwd "$login"
            else
                echo "ATTENTION : $login n'a pas de mot de passe (lancer : passwd $login)" >&2
            fi
        fi
    done
}

# appliquer_acl <rep> <groupe:droits,...> (--set remplace toute l'ACL)
appliquer_acl() {
    local rep=$1 entrees=$2 acl="u::rwx,g::---,o::---,m::rwx" e
    mkdir -p "$rep"
    chown root:root "$rep"
    chmod 0770 "$rep"
    for e in ${entrees//,/ }; do acl+=",g:$e"; done
    setfacl --set "$acl" "$rep"
    setfacl -d --set "$acl" "$rep"
}

creer_repertoires() {
    appliquer_acl /srv/projets          "dev:rwx,design:r-x"
    appliquer_acl /srv/projets/externe  "dev:rwx,design:r-x,freelance:rwx"
    appliquer_acl /srv/maquettes        "dev:r-x,design:rwx,commercial:r-x"
    appliquer_acl /srv/clients          "commercial:rwx"
    # freelance traverse projets pour atteindre externe, sans le lister
    setfacl -m g:freelance:--x /srv/projets
    info "répertoires /srv et ACL en place"
}

main() {
    verifier_prerequis "$@"
    local login nom principal secondaires
    while IFS=';' read -r login nom principal secondaires; do
        secondaires="${secondaires%$'\r'}"
        [[ -z $login ]] && continue
        creer_compte "$login" "$nom" "$principal" "$secondaires"
    done < <(tail -n +2 "$CSV")
    creer_repertoires
    demander_mdp_admins
    info "terminé"
}

main "$@"
