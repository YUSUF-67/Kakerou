# Partie 2 — Journaux et défense (J1–J4, D1)

Projet **XTI302-CYB** « Durcir un serveur Linux et le prouver » — contexte A (agence web Pixelia).
Cible : **VM Kali Rolling**. Cette partie ajoute la défense (fail2ban, pare-feu nftables), le journal
persistant, l'analyse des connexions SSH et les mises à jour de sécurité automatiques. Elle s'intègre à
la partie 1 (comptes, ACL, sudo, durcissement SSH).

## Contenu de la partie

| Exigence | Fichier(s) | Rôle |
|---|---|---|
| Compte admin | `comptes.csv`, `config/cles/mchang.pub` | compte `mchang` (groupes `admins`, `acces_ssh`) + clé publique |
| **J1** | `config/fail2ban/jail.d/sshd.conf` | fail2ban bannit les IP qui échouent trop sur SSH |
| **J2** | `config/nftables.conf` | pare-feu : entrée refusée par défaut, sauf SSH |
| **J3** | `config/journald.conf.d/persistant.conf` | journal système persistant (survit au reboot) |
| **J4** | `analyse_logs.sh` | rapport des connexions SSH + code de sortie selon un seuil |
| **D1** | `config/apt/50unattended-upgrades`, `config/apt/20auto-upgrades` | mises à jour de sécurité automatiques |

Chaque exigence ajoute une fonction dans `installer.sh` (sous le marqueur `# partie 2`) et ses tests dans
`verifier.sh` (`test_J*`, `test_D1*`).

## Prérequis

- VM **Kali** avec le serveur SSH actif.
- Partie 1 déjà en place (comptes, ACL, sudo, durcissement SSH).
- Uniquement des paquets des dépôts officiels Kali. Commandes lancées en **root**.

## Installation

Toute la configuration est reconstruite depuis le dépôt par `installer.sh` :

```bash
sudo ./installer.sh
```

Pour la partie 2, il installe les paquets `fail2ban nftables unattended-upgrades`, puis appelle
`installer_fail2ban`, `installer_nftables`, `installer_journald` et `installer_maj_auto`. Le script est
idempotent (relançable sans danger).

## Vérification

```bash
sudo ./verifier.sh
```

Tests de la partie 2 (doivent afficher `[OK]`) :

- **J1** : service fail2ban + jail `sshd` actifs ; `maxretry` et action nftables.
- **J2** : politique `drop` en entrée ; SSH (22) autorisé ; service activé au démarrage.
- **J3** : `/var/log/journal` présent ; `Storage=persistent` effectif.
- **J4** : seuil haut → pas d'alerte ; seuil 0 → code ≠ 0 ; argument non numérique refusé.
- **D1** : unattended-upgrades installé + timer actif ; MAJ activées ; Origins-Pattern cible Kali.

## Utilisation de `analyse_logs.sh`

Lancé en root (via `sudo`) par le compte `support` :

```bash
sudo analyse_logs.sh            # seuil d'alerte par défaut : 10
sudo analyse_logs.sh -s 5       # seuil personnalisé
sudo analyse_logs.sh -u ssh     # unité systemd analysée
```

Produit un rapport : **échecs par IP**, **comptes visés**, **connexions réussies**.
Le **code de sortie est ≠ 0** si au moins une IP dépasse le seuil (exploitable par un script de surveillance).

## Choix techniques

- **J1** : `backend = systemd` (logs SSH dans journald sur Kali), `banaction = nftables`,
  `maxretry = 4` (lié à `MaxAuthTries 3`), `bantime = 15m` (court pour la démo).
  Débannir : `fail2ban-client set sshd unbanip <ip>`.
- **J2** : politique `drop` ; autorisé : `lo`, `established,related`, `tcp dport 22`.
  **Pas de `flush ruleset`** → les bans fail2ban survivent à `systemctl reload nftables`.
- **J3** : `Storage=persistent` pour garder l'historique SSH après un reboot.
- **J4** : lecture de `journalctl -u ssh` ; arguments validés strictement (`getopts` + regex) car le
  script tourne en root via sudo ; propriété `root:root 0755`.
- **D1** : Kali n'a pas de dépôt « Debian-Security » → `Origins-Pattern "origin=Kali,codename=kali-rolling"` ;
  `OnlyOnACPower "false"` (une VM est parfois vue « sur batterie »).
