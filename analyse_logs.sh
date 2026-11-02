#!/bin/bash
# J4 - analyse les connexions SSH (journalctl -u <unite>) et produit un rapport :
#   echecs d'authentification par IP, comptes vises, connexions reussies.
# Renvoie un code != 0 si une IP depasse le seuil d'alerte (brute-force probable).
# Lance en root via sudo par le compte support : arguments valides strictement.
# usage : analyse_logs.sh [-s seuil] [-u unite]

set -euo pipefail
export LC_ALL=C

SEUIL=10        # echecs par IP au-dela desquels on alerte (justifie dans le dossier)
UNITE=ssh       # unite systemd analysee

erreur() { echo "ERREUR : $*" >&2; exit 2; }
usage() {
    cat >&2 <<EOF
usage : $0 [-s seuil] [-u unite]
  -s seuil   nombre d'echecs par IP declenchant l'alerte (defaut : $SEUIL)
  -u unite   unite systemd analysee (defaut : $UNITE)
EOF
    exit 2
}

# --- validation stricte des arguments (script root via sudo : aucune injection) ---
while getopts ':s:u:h' opt; do
    case $opt in
        s) SEUIL=$OPTARG ;;
        u) UNITE=$OPTARG ;;
        h) usage ;;
        :) erreur "option -$OPTARG : argument manquant" ;;
        \?) erreur "option invalide : -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || erreur "argument inattendu : $*"
[[ $SEUIL =~ ^[0-9]+$ ]] || erreur "seuil invalide (entier >= 0 attendu) : '$SEUIL'"
[[ $UNITE =~ ^[A-Za-z0-9._@-]+$ ]] || erreur "unite invalide : '$UNITE'"
[[ $EUID -eq 0 ]] || erreur "ce script doit etre lance en root (via sudo)"

# --- lecture du journal une seule fois (-o cat : uniquement le message) ---
journal="$(journalctl -u "$UNITE" --no-pager -o cat 2>/dev/null || true)"

# --- analyse et rapport ; code de sortie 1 si au moins une IP depasse le seuil ---
awk -v seuil="$SEUIL" -v unite="$UNITE" '
    BEGIN { PROCINFO["sorted_in"] = "@val_num_desc" }   # tri par nombre decroissant (gawk)

    # echec : nom d utilisateur inconnu
    /^Invalid user [^ ]+ from / { ech[$5]++; cible[$3]++; nech++; next }

    # echec : mot de passe errone (utilisateur valide ou "invalid user")
    /^Failed password for / {
        if ($4 == "invalid" && $5 == "user") { u = $6; ip = $8 } else { u = $4; ip = $6 }
        ech[ip]++; cible[u]++; nech++; next
    }

    # echec : utilisateur valide, authentification (par cle) avortee
    /^Connection closed by authenticating user [^ ]+ / { ech[$7]++; cible[$6]++; nech++; next }

    # succes
    /^Accepted (publickey|password) for [^ ]+ from / { succ[$4 " @ " $6]++; nok++; next }

    END {
        print "=== Analyse SSH (unite : " unite ") ==="
        print ""
        print "-- Echecs d authentification par IP (seuil d alerte : " seuil ") --"
        depasse = 0
        if (nech == 0) print "  (aucun echec)"
        for (ip in ech) {
            marque = (ech[ip] > seuil) ? "  <== ALERTE" : ""
            printf "  %5d  %s%s\n", ech[ip], ip, marque
            if (ech[ip] > seuil) depasse++
        }
        print "  total echecs : " nech + 0
        print ""
        print "-- Comptes vises --"
        if (length(cible) == 0) print "  (aucun)"
        for (u in cible) printf "  %5d  %s\n", cible[u], u
        print ""
        print "-- Connexions reussies (compte @ IP) --"
        if (nok == 0) print "  (aucune)"
        for (k in succ) printf "  %5d  %s\n", succ[k], k
        print "  total reussies : " nok + 0
        print ""
        if (depasse > 0) {
            print "RESULTAT : ALERTE - " depasse " IP au-dessus du seuil (" seuil ")"
            exit 1
        }
        print "RESULTAT : OK - aucune IP au-dessus du seuil (" seuil ")"
        exit 0
    }
' <<<"$journal"
