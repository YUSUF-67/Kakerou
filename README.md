Kakerou projet XTI302-CYB durcir un serveur linux et le prouver  

on a pris le contexte A donc l'agence web Pixelia avec les groupes dev design commercial et freelance. les freelance expirent le 31/01/2027 et ils ont pas sudo  
on est trois dessus Yusuf (ybouibridene) Maxime (mchang) et Charles (ccrosnier)  

pour la VM on utilise une Kali dans VirtualBox et pas une Debian 13, c'est basé sur debian mais avec les depots kali donc ya deux trois trucs qui changent (pas de /var/log/auth.log les logs ssh sont dans journald, un groupe kali-trusted qui donne sudo sans mot de passe, pas de depot debian-security pour les mises a jour auto)  
le reseau est en NAT avec une redirection 127.0.0.1:2222 vers le port 22 de la VM. il faut aussi un second disque de 2 Go pour les sauvegardes, il apparait en /dev/sdb. on garde un snapshot vierge-propre pris juste avant installer.sh pour pouvoir tout refaire  

avant d'installer chaque admin doit avoir mis sa clé publique dans config/cles/<login>.pub, jamais la clé privée et aucun mot de passe dans le depot. installer.sh refuse de toucher a ssh si aucun admin a de clé sinon on se retrouve bloqué dehors  

pour installer on copie le depot dans la VM puis  
    sudo ./installer.sh  
il demande le mot de passe de chaque admin qui en a pas encore (c'est celui de sudo apres) ensuite il retire sudo aux autres comptes et verrouille root. on peut le relancer sans probleme il recree pas ce qui existe deja et il reformate jamais le disque de sauvegarde si il est deja formaté  

pour verifier  
    sudo verifier.sh  
ca affiche un [OK] ou [KO] par test avec le numero de l'exigence et le total a la fin, code de sortie 0 si tout est bon et 1 sinon. il modifie rien sur le systeme a part des fichiers de test qu'il supprime. pour ajouter un test il suffit d'ecrire une fonction test_<exigence>_quelquechose elle est lancée toute seule  

apres l'install on se connecte avec  
    ssh -p 2222 <login>@127.0.0.1  
seulement par clé, root est refusé et seuls les membres du groupe acces_ssh passent  

ce que fait chaque fichier  
comptes.csv c'est la liste des comptes au format imposé login;nom;groupe_principal;groupes_secondaires  
creer_comptes.sh crée les groupes les comptes les dossiers de /srv avec les ACL (y compris par defaut pour les fichiers créés plus tard) et installe les clés  
installer.sh reconstruit toute la config sur la VM vierge  
verifier.sh teste toutes les exigences  
analyse_logs.sh fait le rapport des connexions ssh, échecs par IP comptes visés et connexions réussies. support peut le lancer en root et rien d'autre  
    sudo analyse_logs.sh  
    sudo analyse_logs.sh -s 5  
le seuil par defaut est 10 et le code de sortie est different de 0 si une IP le depasse  
sauvegarde.sh sauvegarde /srv et /etc sur /sauvegardes avec rsync, une version datée a chaque fois, les fichiers inchangés sont des liens durs vers la version d'avant donc pas recopiés, les ACL sont gardées et on garde les 7 dernieres versions  
config/ contient sshd, sudoers, fail2ban, nftables, journald, apt, les units systemd de la sauvegarde et les clés publiques  

quelques valeurs qu'on a choisies  
ssh MaxAuthTries 3 et ChannelTimeout session=10m, fail2ban bannit apres 4 echecs en 10 min pendant 15 min (court expres pour la demo). pour se debannir  
    sudo fail2ban-client set sshd unbanip <ip>  
le pare-feu est en drop par defaut sauf lo, les connexions deja établies et le port 22, sans flush ruleset pour pas effacer les bans de fail2ban  
la sauvegarde tourne chaque nuit a 2h avec un timer systemd et Persistent=true donc si la VM etait eteinte elle se lance au demarrage, les logs sont dans journalctl -u sauvegarde. /sauvegardes est en root:admins 0750  

pour restaurer un fichier on regarde les versions dans /sauvegardes, on prend celle d'avant le probleme et on recopie avec rsync -aAX pour garder les droits et les ACL, par exemple  
    sudo rsync -aAX /sauvegardes/<version>/srv/projets/fichier /srv/projets/fichier  

qui a fait quoi  
Yusuf partie 1 comptes ACL sudo ssh (C1 a C4 S1 a S5) et la base de installer.sh et verifier.sh  
Maxime partie 2 fail2ban pare-feu journal persistant analyse_logs.sh et mises a jour auto (J1 a J4 D1)  
Charles partie 3 sauvegarde planification droits sur les sauvegardes services réseau et permissions (B1 a B4 D2 D3)  
