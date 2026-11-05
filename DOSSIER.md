Dossier projet XTI302-CYB groupe Kakerou  
Yusuf Bouibridene Maxime Chang Charles Crosnier  
contexte A agence web Pixelia, VM Kali dans VirtualBox  


1. Tableau de conformité  

pour chaque exigence ce qu'on a fait, les tests de verifier.sh (toutes les fonctions test_<ID>_...) et la reco ANSSI si on en a trouvé une (guide BP-028 v2 et guide OpenSSH)

```
ID  | ce qu'on a fait                                          | tests             | ANSSI
----+----------------------------------------------------------+-------------------+-----------
C1  | comptes créés depuis comptes.csv, idempotent             | test_C1_* (3)     | R30
    | freelance expire le 31/01/2027                           |                   |
C2  | /srv en 0770 + ACL et ACL par defaut (setfacl --set)     | test_C2_* (6)     | R50
C3  | admins sudo complet, support juste analyse_logs.sh       | test_C3_* (4)     | R39 a R44
    | groupes sudo et kali-trusted vidés                       |                   |
C4  | root verrouillé, homes en 700                            | test_C4_* (2)     | R33
S1  | clé seulement, mot de passe refusé                       | test_S1_* (2)     | OpenSSH
S2  | PermitRootLogin no                                       | test_S2           | OpenSSH
S3  | AllowGroups acces_ssh                                    | test_S3           | OpenSSH
S4  | MaxAuthTries 3, ChannelTimeout 10 min                    | test_S4_* (2)     | R32
S5  | sshd_config.d/10-durcissement.conf + sshd -t            | test_S5           |
J1  | fail2ban sshd, 4 echecs en 10 min = 15 min de ban        | test_J1_* (2)     |
J2  | nftables drop sauf lo, établies, 22 et icmp              | test_J2_* (3)     | R65 ?
J3  | journal persistant                                       | test_J3_* (2)     | R71
J4  | analyse_logs.sh, seuil 10 par defaut (-s)                | test_J4_* (3)     | R71
D1  | unattended-upgrades sur les depots kali                  | test_D1_* (3)     | R61
B1  | rsync --link-dest, versions datées, 7 gardées            | test_B1_* (4)     |
B2  | timer systemd a 2h, logs dans journalctl                 | test_B2_* (2)     |
B3  | /sauvegardes en root:admins 0750                         | test_B3_* (2)     | R50
B4  | restauration testée (partie 4)                           | test_B4_* (2)     |
D2  | que le port 22 en ecoute, services inutiles masqués      | test_D2_* (2)     | R62
D3  | plus de o+w hors /tmp, SUID listés plus bas              | test_D3_* (3)     | R54 R56 R57
```

dernier passage depuis le snapshot vierge-propre : 76 / 76. il faut lancer sauvegarde.sh une fois apres installer.sh sinon test_B1_incrementale est KO (il faut 2 versions pour comparer)  
les numeros ANSSI on les a pas tous recoupés, ceux avec un ? sont a vérifier  


2. Choix techniques  

la VM  
on a pris une Kali au lieu d'une Debian 13 on sait que c'est pas exactement le sujet. ça change quelques trucs : les logs ssh sont que dans journald, ya un groupe kali-trusted qui donne sudo sans mot de passe, et pas de depot debian-security  
la VM avait aussi des restes d'un ancien TP (comptes alice bob carole poste, un AllowGroups en trop) qu'on a nettoyé avant le snapshot  

comptes et droits  
setfacl --set et pas -m : ça remplace toute l'ACL, donc relancer donne pareil et une entrée ajoutée a la main saute  
freelance a --x sur /srv/projets pour passer jusqu'a externe sans pouvoir lister projets  
homes en 700 pas 750, sinon un dev lit le home d'un autre dev vu qu'ils ont le meme groupe principal  
les admins sont lus dans comptes.csv, getent group admins les montre pas car c'est leur groupe principal (on s'est fait avoir au premier test)  
mots de passe admin jamais dans le depot, demandés a la console a la premiere install  
si aucun admin a de mot de passe installer.sh verrouille pas root, si aucun admin a de clé il touche pas a ssh. c'est pour pas se retrouver bloqué dehors  
support est en NOPASSWD car il a pas de mot de passe. analyse_logs.sh est en root:root 0755 dans /usr/local/sbin, si support pouvait le modifier il serait root. le script vérifie aussi ses arguments  

ssh  
MaxAuthTries 3 : une bonne clé passe du premier coup, 3 laisse de la marge si le client propose plusieurs clés  
ChannelTimeout 10 min : ClientAlive coupe que les clients morts, pas une session ouverte ou personne tape rien  
le fichier s'appelle 10-... parce que sshd garde la premiere valeur lue  
OpenSSH 10 écrit les clés de sshd -T avec des majuscules, verifier.sh compare donc sans la casse  

fail2ban et pare-feu  
maxretry 4 en 10 min, juste au dessus de MaxAuthTries. bantime 15 min court expres pour la démo. pour débannir : fail2ban-client set sshd unbanip <ip>  
backend systemd car les logs sont dans journald  
pas de flush ruleset dans nftables.conf, on supprime que notre table et celle de fail2ban reste  
icmp accepté pour ping, le reste en drop  

journaux  
journal persistant sinon apres un reboot analyse_logs.sh voit plus rien  
seuil 10 : quelqu'un qui se trompe fait 3 echecs, 10 c'est un script. fail2ban bannit avant mais analyse_logs lit tout le journal, ça montre une attaque qui revient apres le ban  

mises a jour  
Origins-Pattern sur kali-rolling sinon rien ne se met a jour  
OnlyOnACPower false car une VM sur portable est parfois vue sur batterie  
pas de reboot auto pour pas couper la démo  

sauvegarde  
--link-dest : un fichier pas modifié devient un lien dur vers la version d'avant, il prend pas de place et chaque version a l'air complete  
-A -X gardent ACL et attributs, -H les liens durs, --numeric-ids garde les uid  
7 versions = une semaine  
2h du matin car personne travail a cette heure, Persistent=true lance la sauvegarde ratée au démarrage  
disque monté par UUID avec nofail nodev nosuid noexec  
installer.sh formate le disque seulement si il est vide, sinon une relance effacerait les sauvegardes  
sauvegarde.sh s'arrete si /sauvegardes est pas monté sinon il remplit le disque systeme  
root:admins 0750 : les admins lisent pour restaurer, seul root ecrit. /etc/shadow reste en 640 dans la sauvegarde donc un admin le lit pas sans sudo  

D2  
ss -tulpn montre que le port 22. d'autres services tournent (lightdm NetworkManager cron dbus fail2ban...) mais aucun écoute sur le reseau  
installer.sh masque aussi apache2 nginx postgresql mariadb redis samba rpcbind avahi cups exim4 postfix xrdp vsftpd snmpd si ils sont la  

D3 les SUID de la VM  
verifier.sh vérifie qu'ils viennent tous d'un paquet et qu'il y en a pas dans /home /srv /tmp  
passwd chfn chsh gpasswd newgrp : changer son mot de passe ou ses infos  
su sudo : changer d'utilisateur  
mount umount fusermount3 : monter des clés usb ou du fuse  
pkexec dbus-daemon-launch-helper : polkit et dbus pour l'interface  
ssh-keysign : auth par hôte de ssh, pas utilisé  
Xorg.wrap chrome-sandbox : interface graphique et chromium  
ntfs-3g mount.cifs mount.nfs : disques windows ou reseau  
pppd : connexions modem  
rsh-redone-rsh rsh-redone-rlogin kismet_cap_* : outils kali  
ceux de la fin servent a rien sur un serveur. on aurait pu les enlever (apt purge ou chmod u-s), on les a gardé parce que c'est l'outillage de kali. sur un vrai serveur ce serait la premiere chose a faire  


3. Défense  

force brute ssh  
les mots de passe sont refusés de toute façon, et apres 4 echecs fail2ban bannit l'IP 15 min. analyse_logs.sh le voit aussi. si l'attaquant change d'IP souvent fail2ban suffit pas  

vol de mot de passe  
un mot de passe admin volé sert a rien sans la clé privée, il sert que pour sudo. root est verrouillé. par contre si la clé privée est volée l'attaquant entre, il faudrait du 2FA  

utilisateur curieux  
un commercial peut pas lire /srv/projets ni les homes ni les sauvegardes, et il a pas ssh. il lit quand meme les fichiers systeme lisibles par tous, c'est normal  

compte freelance compromis  
pas de sudo pas de ssh, il voit que externe et le compte expire tout seul. au pire il abime externe et on restaure  

compte support compromis  
il lance analyse_logs.sh en root et rien d'autre, le script est a root et vérifie ses arguments donc pas de shell root. il peut lire les logs ssh  

rançongiciel ou suppression  
on revient a une des 7 versions. pas couvert : la sauvegarde est sur la meme machine, si la VM est perdue on perd tout. il faudrait une copie ailleurs (3-2-1)  

pas couvert en général  
l'accès a la console de la VM, une faille dans ssh lui meme (d'ou les maj auto), un admin malveillant, et tout ce que kali ajoute en plus  


4. Procédure de restauration  

exemple : un fichier supprimé dans /srv/projets  

1. se connecter en admin : ssh -p 2222 ybouibridene@127.0.0.1  
2. lister les versions : ls /sauvegardes (format AAAA-MM-JJ_HHMMSS)  
3. trouver une version ou le fichier est encore bon : ls -l /sauvegardes/<version>/srv/projets/  
4. tester sans rien ecrire : sudo rsync -aAX --dry-run -v /sauvegardes/<version>/srv/projets/fichier /srv/projets/  
5. restaurer : sudo rsync -aAX /sauvegardes/<version>/srv/projets/fichier /srv/projets/  
6. vérifier les droits et ACL : ls -l /srv/projets/fichier et getfacl /srv/projets/fichier  

pour un dossier entier pareil, avec --delete si on veut qu'il redevienne exactement comme avant (attention ça efface ce qui a été créé depuis). toujours faire le --dry-run avant  
pour /etc on restaure fichier par fichier, et pour ssh on refait sshd -t avant de redémarrer  

testé : verifier.sh restaure /etc/hostname et /srv/projets depuis la plus vieille version dans un dossier temporaire et compare contenu propriétaire droits et ACL (test_B4_fichier et test_B4_acl OK)  
