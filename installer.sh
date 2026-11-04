#!/bin/bash
# reconstruit toute la configuration sur la VM vierge, relancable
# usage : sudo ./installer.sh

set -euo pipefail

DEPOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$DEPOT/config"
PAQUETS=(acl sudo openssh-server fail2ban nftables unattended-upgrades rsync)
# copies root:root 0755 hors du depot : personne d'autre ne peut les modifier
SCRIPTS=(analyse_logs.sh sauvegarde.sh verifier.sh)
DISQUE=/dev/sdb
SAUVEGARDES=/sauvegardes

erreur() { echo "ERREUR : $*" >&2; exit 1; }
etape()  { echo "==> $*"; }
# admins lus dans le CSV : un groupe principal n'apparait pas dans getent group
admins() { awk -F';' '$3 == "admins" { print $1 }' "$DEPOT/comptes.csv"; }

installer_paquets() {
    etape "paquets : ${PAQUETS[*]}"
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PAQUETS[@]}"
}

installer_comptes() {
    etape "comptes, groupes, /srv (C1, C2)"
    bash "$DEPOT/creer_comptes.sh" "$DEPOT/comptes.csv"
}

installer_scripts() {
    etape "scripts dans /usr/local/sbin"
    local s
    for s in "${SCRIPTS[@]}"; do
        [[ -f $DEPOT/$s ]] && install -o root -g root -m 0755 "$DEPOT/$s" "/usr/local/sbin/$s"
    done
    install -d -o root -g root -m 0755 /usr/local/share/xti302
    install -o root -g root -m 0644 "$DEPOT/comptes.csv" /usr/local/share/xti302/comptes.csv
}

installer_sudo() {
    etape "sudoers (C3)"
    visudo -cf "$CONFIG/sudoers.d/xti302" >/dev/null || erreur "config/sudoers.d/xti302 invalide"
    install -o root -g root -m 0440 "$CONFIG/sudoers.d/xti302" /etc/sudoers.d/xti302
}

# sans cle admin, AllowGroups nous bloquerait dehors
verifier_cle_admin() {
    local login home
    for login in $(admins); do
        id -nG "$login" | grep -qw acces_ssh || continue
        home="$(getent passwd "$login" | cut -d: -f6)"
        [[ -s $home/.ssh/authorized_keys ]] && return 0
    done
    return 1
}

installer_ssh() {
    etape "SSH (S1-S5)"
    verifier_cle_admin || erreur "aucun administrateur n'a de clé dans config/cles/ : SSH non modifié"
    install -o root -g root -m 0644 "$CONFIG"/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config.d/
    if ! sshd -t; then
        rm -f /etc/ssh/sshd_config.d/10-durcissement.conf
        erreur "sshd -t a échoué : configuration retirée, SSH inchangé"
    fi
    systemctl enable ssh
    systemctl restart ssh
}

verifier_admin_mdp() {
    local login
    for login in $(admins); do
        [[ $(passwd -S "$login" | awk '{print $2}') == P ]] && return 0
    done
    return 1
}

restreindre_root_et_sudo() {
    etape "sudo réservé à admins, root verrouillé, homes privés (C3, C4)"
    verifier_admin_mdp || erreur "aucun administrateur n'a de mot de passe : root et sudo laissés intacts"
    # le compte cree a l'installation est dans sudo (et kali-trusted sur Kali)
    local g u
    for g in sudo kali-trusted wheel; do
        getent group "$g" >/dev/null || continue
        for u in $(getent group "$g" | cut -d: -f4 | tr , ' '); do
            gpasswd -d "$u" "$g"
        done
    done
    passwd -l root
    chmod go-rwx /home/*/
}

# --- partie 2 : journaux et defense ---

installer_fail2ban() {
    etape "fail2ban : protection SSH contre le bruteforce (J1)"
    install -d -o root -g root -m 0755 /etc/fail2ban/jail.d
    install -o root -g root -m 0644 "$CONFIG/fail2ban/jail.d/sshd.conf" /etc/fail2ban/jail.d/sshd.conf
    systemctl enable fail2ban
    systemctl restart fail2ban
}

installer_nftables() {
    etape "pare-feu nftables : politique drop sauf SSH (J2)"
    nft -c -f "$CONFIG/nftables.conf" || erreur "config/nftables.conf invalide"
    install -o root -g root -m 0644 "$CONFIG/nftables.conf" /etc/nftables.conf
    systemctl enable nftables
    nft -f /etc/nftables.conf          # sans flush : bans fail2ban preserves
}

installer_journald() {
    etape "journal systemd persistant (J3)"
    install -d -o root -g root -m 0755 /etc/systemd/journald.conf.d
    install -o root -g root -m 0644 "$CONFIG/journald.conf.d/persistant.conf" /etc/systemd/journald.conf.d/persistant.conf
    systemctl restart systemd-journald
}

installer_maj_auto() {
    etape "mises a jour de securite automatiques (D1)"
    install -o root -g root -m 0644 "$CONFIG/apt/50unattended-upgrades" /etc/apt/apt.conf.d/50unattended-upgrades
    install -o root -g root -m 0644 "$CONFIG/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
    systemctl enable --now unattended-upgrades
    systemctl enable --now apt-daily-upgrade.timer
}

# --- partie 3 : sauvegarde et systeme ---

preparer_disque() {
    etape "second disque $DISQUE monté sur $SAUVEGARDES (B1)"
    [[ -b $DISQUE ]] || erreur "$DISQUE absent : ajouter le disque de 2 Go à la VM"
    # blkid echoue sur un disque vierge : on ne formate jamais un disque deja utilise
    if ! blkid "$DISQUE" >/dev/null; then
        mkfs.ext4 -q -L sauvegardes "$DISQUE"
    fi
    local uuid type
    uuid="$(blkid -s UUID -o value "$DISQUE" || true)"
    type="$(blkid -s TYPE -o value "$DISQUE" || true)"
    [[ -n $uuid && -n $type ]] || erreur "$DISQUE contient des partitions ou un format inconnu : non modifié"
    mkdir -p "$SAUVEGARDES"
    # UUID : stable meme si le disque change de nom ; nofail : demarrage meme sans le disque
    sed -i "\|[[:space:]]$SAUVEGARDES[[:space:]]|d" /etc/fstab
    echo "UUID=$uuid $SAUVEGARDES $type defaults,nofail,nodev,nosuid,noexec 0 2" >> /etc/fstab
    systemctl daemon-reload
    mountpoint -q "$SAUVEGARDES" || mount "$SAUVEGARDES"
}

installer_timer() {
    etape "sauvegarde planifiée chaque nuit, journalisée (B2)"
    install -o root -g root -m 0644 "$CONFIG"/systemd/sauvegarde.{service,timer} /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now sauvegarde.timer
    # premiere version tout de suite, sans attendre 2h
    systemctl start sauvegarde.service
}

main() {
    [[ $EUID -eq 0 ]] || erreur "ce script doit être lancé en root"
    [[ $# -eq 0 ]] || erreur "usage : $0 (sans argument)"
    installer_paquets
    installer_comptes
    installer_scripts
    installer_sudo
    installer_ssh
    restreindre_root_et_sudo
    # partie 2
    installer_fail2ban
    installer_nftables
    installer_journald
    installer_maj_auto
    # partie 3
    preparer_disque
    installer_timer
    etape "terminé : lancer sudo verifier.sh"
}

main "$@"
