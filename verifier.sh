#!/bin/bash
# teste chaque exigence, sortie 0 si tout est conforme, 1 sinon
# toute fonction test_* est lancee automatiquement
# usage : sudo verifier.sh

# pas de -e (les tests echouent exprès) ni pipefail (SIGPIPE avec grep -q)
set -u
export LC_ALL=C

ICI="$(cd "$(dirname "$0")" && pwd)"
if [[ -f $ICI/comptes.csv ]]; then CSV="$ICI/comptes.csv"; else CSV=/usr/local/share/xti302/comptes.csv; fi
REUSSIS=0
TOTAL=0

ok() { echo "[OK] $1 $2"; REUSSIS=$((REUSSIS + 1)); TOTAL=$((TOTAL + 1)); }
ko() { echo "[KO] $1 $2"; TOTAL=$((TOTAL + 1)); }

lignes_csv() { tail -n +2 "$CSV" | tr -d '\r' | grep -v '^$'; }
membre() { lignes_csv | awk -F';' -v g="$1" '$3 == g { print $1; exit }'; }
comptes_humains() { getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1 }'; }
# OpenSSH 10 ecrit les cles de sshd -T en CamelCase
sshd_val() { sshd -T 2>/dev/null | awk -v k="$1" 'tolower($1) == k { $1 = ""; sub(/^ /, ""); print; exit }'; }

# C1

test_C1_comptes() {
    local login nom principal secondaires g manque
    while IFS=';' read -r login nom principal secondaires; do
        if ! id "$login" >/dev/null 2>&1; then
            ko "C1" "compte $login absent"; continue
        fi
        manque=""
        [[ $(id -gn "$login") == "$principal" ]] || manque+=" principal=$principal"
        for g in ${secondaires//,/ }; do
            id -nG "$login" | grep -qw "$g" || manque+=" $g"
        done
        if [[ -z $manque ]]; then ok "C1" "compte $login conforme au CSV"
        else ko "C1" "compte $login : groupes manquants :$manque"; fi
    done < <(lignes_csv)
}

test_C1_groupes_metier() {
    local g n absents=""
    for g in admins support acces_ssh dev design commercial freelance; do
        getent group "$g" >/dev/null || absents+=" $g"
    done
    for g in dev design commercial freelance; do
        n=$(lignes_csv | awk -F';' -v g="$g" '$3 == g' | wc -l)
        [[ $n -ge 2 ]] || absents+=" $g(<2 membres)"
    done
    if [[ -z $absents ]]; then ok "C1" "groupes présents, 2 membres au moins par groupe métier"
    else ko "C1" "groupes incorrects :$absents"; fi
}

test_C1_freelance_expiration() {
    local login bad=""
    for login in $(lignes_csv | awk -F';' '$3 == "freelance" { print $1 }'); do
        chage -l "$login" 2>/dev/null | grep -i '^account expires' | grep -qv never || bad+=" $login"
    done
    if [[ -z $bad ]]; then ok "C1" "comptes freelance avec date d'expiration"
    else ko "C1" "freelance sans expiration :$bad"; fi
}

# C2

# droit <ID> <groupe> <-r|-w> <chemin> <oui|non>
droit() {
    local u verbe
    u=$(membre "$2")
    [[ $3 == -r ]] && verbe="lire" || verbe="écrire"
    if [[ -z $u ]]; then ko "$1" "aucun membre de $2 dans le CSV"; return; fi
    if sudo -u "$u" test "$3" "$4"; then
        [[ $5 == oui ]] && ok "$1" "$2 ($u) peut $verbe $4" || ko "$1" "$2 ($u) peut $verbe $4 (attendu : refusé)"
    else
        [[ $5 == non ]] && ok "$1" "$2 ($u) ne peut pas $verbe $4" || ko "$1" "$2 ($u) ne peut pas $verbe $4 (attendu : autorisé)"
    fi
}

test_C2_projets() {
    droit C2 dev        -w /srv/projets oui
    droit C2 design     -r /srv/projets oui
    droit C2 design     -w /srv/projets non
    droit C2 commercial -r /srv/projets non
    droit C2 freelance  -r /srv/projets non
}

test_C2_externe() {
    droit C2 freelance  -w /srv/projets/externe oui
    droit C2 design     -w /srv/projets/externe non
    droit C2 commercial -r /srv/projets/externe non
}

test_C2_maquettes() {
    droit C2 design     -w /srv/maquettes oui
    droit C2 commercial -r /srv/maquettes oui
    droit C2 commercial -w /srv/maquettes non
    droit C2 freelance  -r /srv/maquettes non
}

test_C2_clients() {
    droit C2 commercial -w /srv/clients oui
    droit C2 dev        -r /srv/clients non
}

test_C2_acl_defaut() {
    local d sans=""
    for d in /srv/projets /srv/projets/externe /srv/maquettes /srv/clients; do
        getfacl -p "$d" 2>/dev/null | grep -q '^default:group:' || sans+=" $d"
    done
    if [[ -z $sans ]]; then ok "C2" "ACL par défaut présentes sur /srv"
    else ko "C2" "pas d'ACL par défaut :$sans"; fi
}

test_C2_heritage() {
    local dev design com f
    dev=$(membre dev); design=$(membre design); com=$(membre commercial)
    # touch et pas mktemp : mktemp cree en 0600, ce qui masquerait l'heritage
    f="/srv/projets/.verifier.$$"
    sudo -u "$dev" touch "$f" 2>/dev/null \
        || { ko "C2" "$dev ne peut pas créer de fichier dans /srv/projets"; return; }
    if sudo -u "$design" test -r "$f" && ! sudo -u "$design" test -w "$f" && ! sudo -u "$com" test -r "$f"; then
        ok "C2" "nouveau fichier de /srv/projets : design lit, commercial refusé"
    else
        ko "C2" "nouveau fichier de /srv/projets : droits non hérités"
    fi
    rm -f "$f"
}

# C3

test_C3_admins() {
    local login
    for login in $(lignes_csv | awk -F';' '$3 == "admins" { print $1 }'); do
        if sudo -l -U "$login" 2>/dev/null | grep -q '(ALL : ALL) ALL'; then ok "C3" "$login (admins) a sudo"
        else ko "C3" "$login (admins) n'a pas sudo"; fi
    done
}

test_C3_support() {
    local regles
    regles=$(sudo -l -U support 2>/dev/null | sed -n '/may run the following/,$p' | tail -n +2 | grep -v '^[[:space:]]*$')
    if [[ $(echo "$regles" | wc -l) -eq 1 && $regles == *"/usr/local/sbin/analyse_logs.sh" ]]; then
        ok "C3" "le compte support ne peut lancer que analyse_logs.sh"
    else
        ko "C3" "règles sudo de support incorrectes : ${regles:-aucune}"
    fi
}

test_C3_aucun_autre() {
    local u admins trop=""
    admins=" $(lignes_csv | awk -F';' '$3 == "admins" { printf "%s ", $1 }') support "
    for u in $(comptes_humains); do
        [[ $admins == *" $u "* ]] && continue
        sudo -l -U "$u" 2>/dev/null | grep -q 'is not allowed to run sudo' || trop+=" $u"
    done
    if [[ -z $trop ]]; then ok "C3" "aucun autre compte n'a sudo (freelance compris)"
    else ko "C3" "comptes avec sudo en trop :$trop"; fi
}

test_C3_script_root() {
    local s=/usr/local/sbin/analyse_logs.sh
    if [[ -f $s && $(stat -c '%U' "$s") == root && $(( 0$(stat -c '%a' "$s") & 022 )) -eq 0 ]]; then
        ok "C3" "analyse_logs.sh appartient à root et n'est modifiable que par lui"
    else
        ko "C3" "$s absent ou modifiable par un autre que root"
    fi
}

# C4

test_C4_root() {
    if [[ $(passwd -S root | awk '{print $2}') == L ]]; then ok "C4" "compte root verrouillé"
    else ko "C4" "compte root non verrouillé"; fi
}

test_C4_homes() {
    local u h ouverts=""
    for u in $(comptes_humains); do
        h=$(getent passwd "$u" | cut -d: -f6)
        [[ -d $h ]] || continue
        [[ $(( 0$(stat -c '%a' "$h") & 07 )) -eq 0 ]] || ouverts+=" $h"
    done
    if [[ -z $ouverts ]]; then ok "C4" "répertoires personnels illisibles par les autres"
    else ko "C4" "répertoires personnels ouverts :$ouverts"; fi
}

# S1 à S5

test_S1_config() {
    if [[ $(sshd_val passwordauthentication) == no && $(sshd_val pubkeyauthentication) == yes \
          && $(sshd_val kbdinteractiveauthentication) == no ]]; then
        ok "S1" "authentification par clé uniquement"
    else
        ko "S1" "mot de passe ou keyboard-interactive encore autorisé"
    fi
}

test_S1_methodes() {
    local rep
    rep=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -o PreferredAuthentications=none -o ConnectTimeout=5 verifier@127.0.0.1 true 2>&1)
    if [[ $rep == *"Permission denied (publickey)"* ]]; then ok "S1" "le serveur ne propose que publickey"
    else ko "S1" "méthodes proposées : ${rep##*Permission denied }"; fi
}

test_S2() {
    if [[ $(sshd_val permitrootlogin) == no ]]; then ok "S2" "connexion root refusée"
    else ko "S2" "PermitRootLogin n'est pas à 'no'"; fi
}

test_S3() {
    if [[ $(sshd_val allowgroups) == acces_ssh ]]; then ok "S3" "seul le groupe acces_ssh peut se connecter"
    else ko "S3" "AllowGroups vaut '$(sshd_val allowgroups)' (attendu : acces_ssh)"; fi
}

test_S4_essais() {
    local n
    n=$(sshd_val maxauthtries)
    if [[ -n $n && $n -le 4 ]]; then ok "S4" "MaxAuthTries = $n (<= 4)"
    else ko "S4" "MaxAuthTries = ${n:-?} (attendu : <= 4)"; fi
}

en_secondes() {
    local v=$1
    case $v in
        *h) echo $(( ${v%h} * 3600 )) ;;
        *m) echo $(( ${v%m} * 60 )) ;;
        *s) echo "${v%s}" ;;
        *)  echo "$v" ;;
    esac
}

test_S4_inactivite() {
    local v s
    v=$(sshd_val channeltimeout | grep -o 'session=[0-9]*[smh]\?' | head -n1)
    v=${v#session=}
    s=$( [[ -n $v ]] && en_secondes "$v" )
    if [[ -n $s && $s -gt 0 && $s -le 900 ]]; then ok "S4" "session inactive fermée après ${s}s (<= 900)"
    else ko "S4" "pas de ChannelTimeout session <= 15 min (valeur : ${v:-aucune})"; fi
}

test_S5() {
    if ls /etc/ssh/sshd_config.d/*.conf >/dev/null 2>&1 && sshd -t 2>/dev/null; then
        ok "S5" "configuration dans sshd_config.d/ et validée par sshd -t"
    else
        ko "S5" "pas de fichier dans sshd_config.d/ ou sshd -t en erreur"
    fi
}

# partie 2

# J1

test_J1_service() {
    if systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null 2>&1; then
        ok "J1" "fail2ban actif et jail sshd en place"
    else
        ko "J1" "fail2ban inactif ou jail sshd absente"
    fi
}

test_J1_parametres() {
    local maxretry actions
    maxretry=$(fail2ban-client get sshd maxretry 2>/dev/null)
    actions=$(fail2ban-client get sshd actions 2>/dev/null)
    if [[ -n $maxretry && $maxretry -le 5 ]] && echo "$actions" | grep -qi nft; then
        ok "J1" "maxretry=$maxretry et bannissement via nftables"
    else
        ko "J1" "parametres J1 incorrects (maxretry=${maxretry:-?}, actions=${actions:-aucune})"
    fi
}

# J2

test_J2_politique() {
    if nft list chain inet filtre entree 2>/dev/null | grep -q 'policy drop'; then
        ok "J2" "politique par defaut drop en entree"
    else
        ko "J2" "pas de politique drop sur l'entree"
    fi
}

test_J2_ssh_ouvert() {
    if nft list chain inet filtre entree 2>/dev/null | grep -qE 'tcp dport 22 accept'; then
        ok "J2" "SSH (22/tcp) autorise en entree"
    else
        ko "J2" "la regle d'acceptation SSH est absente"
    fi
}

test_J2_service() {
    if systemctl is-enabled --quiet nftables; then
        ok "J2" "nftables active au demarrage (survit au reboot)"
    else
        ko "J2" "nftables non active au demarrage"
    fi
}

# partie 3

main() {
    [[ $EUID -eq 0 ]] || { echo "ERREUR : ce script doit être lancé en root" >&2; exit 2; }
    [[ -r $CSV ]] || { echo "ERREUR : comptes.csv introuvable ($CSV)" >&2; exit 2; }
    local t
    for t in $(compgen -A function test_); do "$t"; done
    echo "--- $REUSSIS / $TOTAL tests réussis"
    [[ $REUSSIS -eq $TOTAL ]]
}

main "$@"
