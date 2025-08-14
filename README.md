# Projet Linux – Août 2025  

## Présentation  
Ce projet a été réalisé dans le cadre de notre formation en informatique de 2ème année bachelier (**orientation réseaux et télécommunications**).  
L’objectif était de mettre en place une **infrastructure Linux complète** en environnement **Amazon Linux 2023** avec l’installation, la configuration et l’automatisation de différents services via des scripts Bash.  

---

## Fonctionnalités principales  
- Installation et configuration automatisée des services réseau et applicatifs  
- Sécurisation du serveur (**pare-feu, Fail2Ban, SSH, SELinux partiel**)  
- Gestion des utilisateurs avec accès **web, FTP/Samba et base de données**  
- Automatisation via **menus interactifs et scripts modulaires**  
- Surveillance et maintenance (**NetData, ClamAV, sauvegardes, journaux**)  

---

## Structure du dépôt  
- **Scripts/** – Scripts Bash pour l’installation, la configuration et l’automatisation des services  
- **Client/** – Scripts destinés à la configuration et à la gestion des machines clientes  
- **installAll.sh** – Script principal permettant d’installer et configurer tous les services via un menu interactif  

> **Note de sécurité** : Les fichiers sensibles (clés SSH `.pem`, profils VPN `.ovpn`, etc.) ont été retirés du dépôt public et sont stockés de manière sécurisée.  

---

## Services configurés  

### éseau & Infrastructure  
- **DNS (Bind)**  
- **Serveur Web (Apache)**  
- **Base de données (MariaDB)**  
- **FTP (vsftpd)**  
- **Samba (partages réseau)**  
- **NFS (montage distant)**  
- **SSL/TLS pour les domaines**  
- **phpMyAdmin** (gestion des bases via interface web)  

### Sécurité  
- **SSH sécurisé** (désactivation accès root, clés publiques)  
- **Fail2Ban** (protection contre les attaques par force brute)  
- **SELinux** (configuration partielle en mode enforcing)  
- **ClamAV** (antivirus avec scan automatique)  
- **Pare-feu (Firewalld)**  

### Maintenance & Monitoring  
- **NetData** (surveillance en temps réel)  
- **Sauvegardes automatiques**  
- **Gestion et visualisation des journaux système**  

---

## Auteurs

- Quentin Hemeryck  
- Alex Genart

---

## Licence  
Ce projet est distribué à **titre éducatif** et ne doit pas être utilisé en production sans adaptation et sécurisation supplémentaires.  
