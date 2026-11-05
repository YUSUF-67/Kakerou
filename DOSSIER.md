Dossier projet XTI302-CYB groupe Kakerou
Yusuf Bouibridene, Maxime Chang, Charles Crosnier
contexte A agence web Pixelia, VM Kali dans VirtualBox


1. Tableau de conformité

pour chaque exigence ce qu'on a fait, le ou les tests de verifier.sh et la reco ANSSI quand on en a trouvé une (guide BP-028 pour linux et guide OpenSSH, numeros relevés dans la v2 du guide linux)

| ID | ce qu'on a fait | test verifier.sh | ANSSI |
|---|---|---|---|
| C1 | creer_comptes.sh lit comptes.csv, vérifie l'en-tête et les logins, crée groupes et comptes seulement s'ils existent pas, usermod -G remet les groupes comme dans le csv. les freelance expirent le 31/01/2027 avec chage -E | test_C1_comptes test_C1_groupes_metier test_C1_freelance_expiration | R30 |
| C2 | dossiers de /srv en root:root 0770 + ACL d'accès et ACL par défaut posées avec setfacl --set | test_C2_projets test_C2_externe test_C2_maquettes test_C2_clients test_C2_acl_defaut test_C2_heritage | R50 |
| C3 | config/sudoers.d/xti302 vérifié par visudo -c, %admins a tout, support a seulement /usr/local/sbin/analyse_logs.sh. installer.sh vide les groupes sudo et kali-trusted | test_C3_admins test_C3_support test_C3_aucun_autre test_C3_script_root | R39 a R44 |
| C4 | passwd -l root, homes en 700 | test_C4_root test_C4_homes | R33 |
| S1 | PasswordAuthentication no, KbdInteractiveAuthentication no, PubkeyAuthentication yes | test_S1_config test_S1_methodes | guide OpenSSH, authentification par clé |
| S2 | PermitRootLogin no | test_S2 | guide OpenSSH |
| S3 | AllowGroups acces_ssh | test_S3 | guide OpenSSH, restreindre les utilisateurs |
| S4 | MaxAuthTries 3, ChannelTimeout session=10m | test_S4_essais test_S4_inactivite | R32 |
| S5 | fichier config/ssh/sshd_config.d/10-durcissement.conf, sshd -t avant le restart sinon le fichier est retiré | test_S5 | |
| J1 | fail2ban jail sshd, backend systemd, banaction nftables, 4 essais en 10 min = 15 min de ban | test_J1_service test_J1_parametres | |
| J2 | config/nftables.conf, entrée et transfert en drop sauf lo, connexions établies, port 22 et icmp. service nftables activé au boot | test_J2_politique test_J2_ssh_ouvert test_J2_service | R65? (pare-feu local, a confirmer) |
| J3 | Storage=persistent dans journald.conf.d | test_J3_persistant test_J3_config | R71 |
| J4 | analyse_logs.sh lit journalctl -u ssh, compte les échecs par IP, les comptes visés et les connexions réussies, sort avec un code different de 0 si une IP passe le seuil (10 par defaut, option -s) | test_J4_seuil_haut test_J4_seuil_zero test_J4_arguments | R71 |
| D1 | unattended-upgrades avec un Origins-Pattern pour les depots Kali, 20auto-upgrades active le timer | test_D1_installe test_D1_active test_D1_origines_kali | R61 |
| B1 | sauvegarde.sh, rsync -aAXH --link-dest vers une version datée sur le 2e disque monté en /sauvegardes, on garde les 7 dernieres | test_B1_montage test_B1_versions test_B1_incrementale test_B1_acl | |
| B2 | timer systemd sauvegarde.timer tous les jours a 2h, Persistent=true, sortie dans journalctl -u sauvegarde | test_B2_timer test_B2_journal | |
| B3 | /sauvegardes en root:admins 0750 | test_B3_droits test_B3_acces | R50 |
| B4 | restauration testée (voir partie 4), verifier.sh restaure un fichier et un dossier avec ACL dans un dossier temporaire et compare | test_B4_fichier test_B4_acl | |
| D2 | seul le port 22 écoute (ss -tulpn), une liste de services réseau inutiles est masquée par installer.sh si ils sont présents | test_D2_ssh test_D2_autres | R62 |
| D3 | find -xdev qui enleve le droit o+w des fichiers hors /tmp et /var/tmp, liste des SUID plus bas | test_D3_modifiables test_D3_suid test_D3_suid_donnees | R54 R56 R57 |

au dernier passage depuis le snapshot vierge-propre on a 76 / 76 tests réussis (il faut lancer sauvegarde.sh une fois de plus apres installer.sh pour avoir 2 versions sinon test_B1_incrementale est KO, c'est normal)

les numeros ANSSI c'est ce qu'on a trouvé en lisant le guide, on les a pas tous recoupés donc ceux avec un ? sont a vérifier


2. Choix techniques

la VM
on a pris une Kali qu'on avait deja au lieu d'une Debian 13. c'est basé sur debian mais les depots sont ceux de kali donc ça change des trucs : pas de /var/log/auth.log les logs ssh sont que dans journald, un groupe kali-trusted qui donne sudo sans mot de passe (installer.sh le vide), et pas de depot debian-security pour les mises a jour auto. on sait que c'est pas exactement le sujet. la VM avait aussi des restes d'un ancien TP (comptes alice bob carole poste, un AllowGroups projet sudo, un sudoers tp-operateurs) qu'on a nettoyés avant de prendre le snapshot vierge-propre

comptes et droits
setfacl --set plutot que -m parce que --set remplace toute l'ACL, du coup si on relance on retombe exactement pareil et si quelqu'un a ajouté une entrée a la main elle saute
freelance a --x sur /srv/projets, ça lui permet de passer pour aller dans externe mais il peut pas lister ni lire projets
les homes sont en 700 et pas 750 parce que tous les membres d'un groupe métier ont le meme groupe principal, avec 750 un dev pourrait lire le home d'un autre dev
les admins sont lus dans comptes.csv et pas dans getent group admins, parce que admins est leur groupe principal et linux le met pas dans la liste des membres du groupe (on s'est fait avoir au premier test)
les mots de passe des admins sont jamais dans le depot, installer.sh les demande a la console a la premiere install. sans mot de passe sudo marche pas donc installer.sh refuse de verrouiller root et d'enlever les autres sudo tant qu'aucun admin en a un
pareil pour ssh, si aucun admin a de clé installer.sh touche pas a la config ssh sinon AllowGroups nous enfermerait dehors
support est en NOPASSWD parce qu'il a pas de mot de passe (connexion par clé seulement). le risque est limité parce que analyse_logs.sh est copié dans /usr/local/sbin en root:root 0755, si le script etait modifiable par support il pourrait mettre ce qu'il veut dedans et l'executer en root. analyse_logs.sh vérifie aussi ses arguments avec des regex pour qu'on puisse rien injecter

ssh
MaxAuthTries 3, une clé valide passe du premier coup et 3 ça laisse de la marge a un client qui propose plusieurs clés
ChannelTimeout session=10m, ClientAliveInterval tout seul ne coupe que les clients morts, une session ouverte mais où personne tape rien reste ouverte. ChannelTimeout coupe vraiment l'inactivité. le fichier commence par 10- parce que sshd garde la premiere valeur qu'il lit
attention OpenSSH 10 affiche les clés de sshd -T avec des majuscules (PermitRootLogin) donc verifier.sh compare sans tenir compte de la casse

fail2ban et pare-feu
maxretry 4 sur 10 min, c'est juste au dessus de MaxAuthTries donc une seule connexion ratée suffit pas mais deux oui. bantime 15 min c'est court exprès pour la démo vu que c'est notre propre PC qui se fait bannir. pour débannir : fail2ban-client set sshd unbanip <ip>
backend systemd parce que les logs ssh sont dans journald sur kali
dans nftables.conf on fait pas de flush ruleset, on supprime juste notre table, comme ça la table de fail2ban reste quand on recharge le pare-feu
on accepte icmp pour que ping et la découverte MTU marchent, le reste est en drop

journaux et analyse
journal persistant pour garder l'historique des connexions ssh apres un reboot sinon analyse_logs.sh voit plus rien
seuil de 10 échecs par IP : avec MaxAuthTries 3 quelqu'un qui se trompe de clé fait 3 echecs, 10 c'est clairement un script. fail2ban bannit avant mais analyse_logs regarde tout le journal donc ça sert a voir une attaque qui revient apres le ban

mises a jour
Origins-Pattern origin=Kali,codename=kali-rolling sinon unattended-upgrades fait rien sur kali. OnlyOnACPower false parce qu'une VM sur un portable est parfois vue sur batterie et les maj seraient bloquées. pas de reboot automatique pour pas couper la démo

sauvegarde
rsync --link-dest : les fichiers qui ont pas changé sont des liens durs vers la version d'avant donc ils prennent pas de place et sont pas recopiés, mais chaque version a l'air complète. -A et -X gardent les ACL et attributs, -H les liens durs, --numeric-ids pour pas mélanger les uid si on restaure ailleurs
7 versions = une semaine avec une sauvegarde par nuit
2h du matin parce que personne travaille a cette heure la, Persistent=true pour que si la VM etait eteinte la sauvegarde ratée se lance au démarrage
le disque est monté par UUID dans fstab (le nom sdb peut changer) avec nofail pour que la VM démarre quand meme sans le disque, et nodev nosuid noexec parce qu'on a rien a executer dans une sauvegarde
installer.sh formate le disque seulement si blkid trouve rien dessus, sinon relancer installer.sh effacerait toutes les sauvegardes
sauvegarde.sh s'arrete si /sauvegardes est pas monté, sinon il remplirait le disque systeme
/sauvegardes en root:admins 0750 : les admins peuvent lire pour restaurer, seul root écrit, les autres peuvent meme pas entrer. comme rsync garde les droits, /etc/shadow dans la sauvegarde reste en 640 root:shadow donc un admin le lit pas sans sudo

D2 ce qui écoute
ss -tulpn ne montre que le port 22 en ipv4 et ipv6. il y a d'autres services qui tournent sur la VM (lightdm pour l'interface, NetworkManager, cron, dbus, fail2ban, unattended-upgrades, virtualbox-guest-utils...) mais aucun écoute sur le réseau. installer.sh masque en plus apache2 nginx postgresql mariadb redis smbd nmbd rpcbind avahi cups exim4 postfix xrdp vsftpd snmpd si ils sont installés, c'est des services que kali peut avoir et qu'on veut surtout pas voir démarrer

D3 fichiers SUID
verifier.sh vérifie que chaque SUID vient d'un paquet et qu'il y en a aucun dans /home /srv /tmp /var/tmp. la liste sur la VM :
- passwd chfn chsh gpasswd newgrp : changer son mot de passe ou ses infos, il faut ecrire dans /etc/shadow ou /etc/passwd
- su sudo : changer d'utilisateur, c'est leur role
- mount umount fusermount3 : monter des clés usb ou des systemes fuse en tant qu'utilisateur
- pkexec dbus-daemon-launch-helper : polkit et dbus pour l'interface graphique
- ssh-keysign : authentification par hôte de ssh, on l'utilise pas
- Xorg.wrap chrome-sandbox : interface graphique et bac a sable de chromium
- ntfs-3g mount.cifs mount.nfs : monter des disques windows ou réseau
- pppd : connexions ppp (modem)
- rsh-redone-rsh rsh-redone-rlogin et les kismet_cap_* : outils de kali (vieux rsh et captures wifi/bluetooth)
les derniers servent a rien sur un serveur, on aurait pu les enlever avec apt purge kismet rsh-redone-client ou retirer le bit avec chmod u-s. on les a laissés parce qu'ils viennent tous de paquets kali et que les retirer touche a l'outillage de la VM, mais sur un vrai serveur ce serait la premiere chose a faire (GTFOBins montre bien pourquoi un SUID en trop c'est dangereux)


3. Défense

force brute ssh
quelqu'un essaie des mots de passe sur le port 22. ça marche pas du tout parce que ssh accepte que les clés, et apres 4 échecs en 10 min fail2ban bannit l'IP 15 min. analyse_logs.sh le montre aussi et sort en erreur si une IP dépasse 10 échecs. par contre si l'attaquant change d'IP souvent fail2ban suffit pas

vol de mot de passe
si le mot de passe d'un admin fuite ça suffit pas pour entrer en ssh, il faut la clé privée. le mot de passe sert seulement pour sudo une fois connecté. root est verrouillé donc pas de su root non plus. ce qui est pas couvert : si quelqu'un vole la clé privée d'un admin (sans phrase de passe en plus) il entre directement, il faudrait du 2FA

utilisateur curieux
un commercial qui essaie de lire /srv/projets ou le home d'un collegue se fait refuser (ACL et homes en 700), il a pas ssh non plus, et il peut pas lire les sauvegardes. par contre il peut toujours lire les fichiers du systeme qui sont lisibles par tous, c'est normal sur linux

compte freelance compromis
le compte a pas sudo, pas ssh, ne voit que /srv/projets/externe et il expire tout seul a la fin du semestre. le pire qu'il peut faire c'est abimer externe, et on a les sauvegardes pour revenir en arriere

compte support compromis
il peut lancer analyse_logs.sh en root et rien d'autre. le script appartient a root et vérifie ses arguments donc il peut pas s'en servir pour avoir un shell root. il peut lire les logs ssh par contre

rançongiciel ou suppression par erreur
on a 7 versions datées, donc si des fichiers sont chiffrés ou supprimés on reprend la version d'avant. ce qui est pas couvert : la sauvegarde est sur un 2e disque de la meme machine, si la VM est volée, cassée ou chiffrée en entier on perd tout. en vrai il faudrait une copie sur une autre machine et une autre hors site (3-2-1)

ce qu'on couvre pas en général
l'accès physique a la console de la VM, les failles dans ssh lui meme (d'ou les mises a jour auto), un admin malveillant, et toute la surface que kali ajoute (beaucoup de paquets et de SUID qu'un serveur normal aurait pas)


4. Procédure de restauration

le cas classique : quelqu'un a supprimé ou abimé un fichier dans /srv/projets

1. se connecter en admin : ssh -p 2222 ybouibridene@127.0.0.1
2. voir les versions dispo : ls /sauvegardes (une par exécution, nommées AAAA-MM-JJ_HHMMSS)
3. trouver une version où le fichier est encore bon : ls -l /sauvegardes/2026-11-05_045228/srv/projets/
4. tester avant sans rien écrire :
   sudo rsync -aAX --dry-run -v /sauvegardes/<version>/srv/projets/fichier /srv/projets/
5. restaurer pour de vrai :
   sudo rsync -aAX /sauvegardes/<version>/srv/projets/fichier /srv/projets/
6. vérifier que les droits et les ACL sont revenus : ls -l /srv/projets/fichier et getfacl /srv/projets/fichier

pour un dossier entier c'est pareil avec le dossier, et on peut ajouter --delete si on veut qu'il redevienne exactement comme dans la sauvegarde (attention ça supprime ce qui a été créé depuis). on fait toujours le --dry-run avant

pour /etc c'est la meme chose mais on restaure fichier par fichier, et pour la config ssh on refait un sshd -t avant de redémarrer ssh

on a testé : verifier.sh restaure /etc/hostname et le dossier /srv/projets depuis la plus ancienne version dans un dossier temporaire et compare le contenu, le propriétaire, les droits et les ACL (test_B4_fichier et test_B4_acl, OK au dernier passage)
