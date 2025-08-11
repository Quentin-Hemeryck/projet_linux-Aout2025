#!/bin/bash

# Script de suppression complète d'un client
# Ce script supprime toutes les configurations créées par SetupClient.sh

# Vérifier si le script est exécuté en tant que root/sudo
if [[ $EUID -ne 0 ]]; then
   echo "Ce script doit être exécuté en tant que root (sudo)."
   exit 1
fi

# Demande interactive du nom du client
read -p "Entrez le nom du client à supprimer (ex: client1) : " CLIENT

# Vérifie que ce n'est pas vide
if [[ -z "$CLIENT" ]]; then
  echo "Erreur : le nom du client est obligatoire."
  exit 1
fi

# Confirmation de suppression
echo "ATTENTION : Cette action va supprimer DÉFINITIVEMENT toutes les configurations pour le client '$CLIENT':"
echo "  - Utilisateur système"
echo "  - Répertoire web et tous ses fichiers"
echo "  - Configuration Apache (VirtualHost)"
echo "  - Partage Samba"
echo "  - Accès FTP"
echo "  - Base de données MySQL/MariaDB"
echo "  - Entrée DNS"
echo "  - Certificats SSL"
echo "  - Quotas utilisateur"
echo ""
read -p "Êtes-vous sûr de vouloir continuer ? (oui/non) : " CONFIRM

if [[ "$CONFIRM" != "oui" ]]; then
    echo "Suppression annulée."
    exit 0
fi

# Variables
DOMAIN="$CLIENT.linuxserver.lan"
DOCUMENT_ROOT="/var/www/$CLIENT"
VHOST_CONF="/etc/httpd/conf.d/$CLIENT.conf"
CERT_FILE="/etc/pki/tls/certs/$DOMAIN.crt"
KEY_FILE="/etc/pki/tls/private/$DOMAIN.key"
SAMBA_CONF="/etc/samba/smb.conf"
ZONE_FILE="/var/named/linuxserver.lan.zone"
FTP_USER_LIST="/etc/vsftpd/user_list"

echo "Début de la suppression du client '$CLIENT'..."

# 1. Supprimer la configuration Apache
echo "[1/8] Suppression de la configuration Apache..."
if [[ -f "$VHOST_CONF" ]]; then
    rm -f "$VHOST_CONF"
    echo "   Configuration Apache supprimée : $VHOST_CONF"
else
    echo "   - Configuration Apache non trouvée : $VHOST_CONF"
fi

# 2. Supprimer les certificats SSL
echo "[2/8] Suppression des certificats SSL..."
if [[ -f "$CERT_FILE" ]]; then
    rm -f "$CERT_FILE"
    echo "   Certificat SSL supprimé : $CERT_FILE"
else
    echo "   - Certificat SSL non trouvé : $CERT_FILE"
fi

if [[ -f "$KEY_FILE" ]]; then
    rm -f "$KEY_FILE"
    echo "    Clé SSL supprimée : $KEY_FILE"
else
    echo "   - Clé SSL non trouvée : $KEY_FILE"
fi

# 3. Supprimer le partage Samba
echo "[3/8] Suppression du partage Samba..."
if grep -q "^\[$CLIENT\]$" "$SAMBA_CONF"; then
    # Supprimer la section Samba complète (du nom de section jusqu'à la ligne vide ou fin de fichier)
    sed -i "/^\[$CLIENT\]$/,/^$/d" "$SAMBA_CONF"
    echo "    Partage Samba supprimé de $SAMBA_CONF"
    # Redémarrer Samba
    systemctl restart smb
    echo "    Service Samba redémarré"
else
    echo "   - Partage Samba non trouvé dans $SAMBA_CONF"
fi

# 4. Supprimer l'utilisateur Samba
echo "[4/8] Suppression de l'utilisateur Samba..."
if smbpasswd -x "$CLIENT" 2>/dev/null; then
    echo "    Utilisateur Samba '$CLIENT' supprimé"
else
    echo "   - Utilisateur Samba '$CLIENT' non trouvé ou déjà supprimé"
fi

# 5. Supprimer l'accès FTP
echo "[5/8] Suppression de l'accès FTP..."
if [[ -f "$FTP_USER_LIST" ]] && grep -q "^$CLIENT$" "$FTP_USER_LIST"; then
    sed -i "/^$CLIENT$/d" "$FTP_USER_LIST"
    echo "    Utilisateur FTP supprimé de $FTP_USER_LIST"
    # Redémarrer vsftpd
    systemctl restart vsftpd
    echo "    Service FTP redémarré"
else
    echo "   - Utilisateur FTP non trouvé dans $FTP_USER_LIST"
fi

# 6. Supprimer la base de données MySQL/MariaDB
echo "[6/8] Suppression de la base de données MySQL/MariaDB..."
if mysql -u root -e "DROP DATABASE IF EXISTS \`$CLIENT\`; DROP USER IF EXISTS '$CLIENT'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null; then
    echo "    Base de données '$CLIENT' et utilisateur MySQL supprimés"
else
    echo "   - Erreur lors de la suppression de la base de données (vérifiez les droits MySQL)"
fi

# 7. Supprimer l'entrée DNS
echo "[7/8] Suppression de l'entrée DNS..."
if [[ -f "$ZONE_FILE" ]] && grep -q "^$CLIENT\s" "$ZONE_FILE"; then
    sed -i "/^$CLIENT\s/d" "$ZONE_FILE"
    echo "    Entrée DNS supprimée de $ZONE_FILE"
    
    # Incrémenter le numéro de série DNS
    NEW_SERIAL=$(date +%Y%m%d)$(printf "%02d" $((RANDOM % 99 + 1)))
    sed -i -E "s/([0-9]{10}) ; Serial/${NEW_SERIAL} ; Serial/" "$ZONE_FILE"
    echo "    Numéro de série DNS mis à jour : $NEW_SERIAL"
    
    # Redémarrer BIND
    systemctl restart named
    echo "    Service DNS redémarré"
else
    echo "   - Entrée DNS non trouvée dans $ZONE_FILE"
fi

# 8. Supprimer les quotas utilisateur
echo "[8/9] Suppression des quotas utilisateur..."
if id "$CLIENT" &>/dev/null; then
    sudo setquota -u "$CLIENT" 0 0 0 0 /var/www 2>/dev/null
    sudo setquota -u "$CLIENT" 0 0 0 0 /srv/nfs/share 2>/dev/null
    echo "    Quotas supprimés pour '$CLIENT'"
else
    echo "   - Utilisateur '$CLIENT' non trouvé pour suppression des quotas"
fi

# 9. Supprimer le répertoire web et l'utilisateur système
echo "[9/9] Suppression du répertoire web et de l'utilisateur système..."
if [[ -d "$DOCUMENT_ROOT" ]]; then
    rm -rf "$DOCUMENT_ROOT"
    echo "    Répertoire web supprimé : $DOCUMENT_ROOT"
else
    echo "   - Répertoire web non trouvé : $DOCUMENT_ROOT"
fi

if id "$CLIENT" &>/dev/null; then
    # Récupérer le répertoire home avant suppression (méthode plus fiable)
    HOME_DIR=$(getent passwd "$CLIENT" | cut -d: -f6)
    
    echo "    Répertoire home détecté : $HOME_DIR"
    
    # Arrêter tous les processus de l'utilisateur
    echo "    Arrêt des processus de l'utilisateur '$CLIENT'..."
    pkill -u "$CLIENT" 2>/dev/null
    sleep 2
    pkill -9 -u "$CLIENT" 2>/dev/null
    
    # Supprimer l'utilisateur avec son répertoire home
    echo "    Tentative de suppression avec userdel -r..."
    if userdel -r "$CLIENT" 2>&1; then
        echo "    ✓ Utilisateur système '$CLIENT' supprimé avec userdel -r"
    else
        echo "    ⚠ Problème avec userdel -r, détails de l'erreur affichés ci-dessus"
        echo "    Tentative de suppression manuelle..."
        
        # Forcer la suppression de l'utilisateur sans le répertoire home
        if userdel "$CLIENT" 2>/dev/null; then
            echo "    ✓ Utilisateur système '$CLIENT' supprimé (sans répertoire home)"
        else
            echo "    ⚠ Impossible de supprimer l'utilisateur système"
        fi
    fi
    
    # Vérifier et forcer la suppression du répertoire home s'il existe encore
    if [[ -n "$HOME_DIR" ]] && [[ -d "$HOME_DIR" ]] && [[ "$HOME_DIR" != "/" ]] && [[ "$HOME_DIR" != "/home" ]] && [[ "$HOME_DIR" =~ ^/home/ ]]; then
        echo "    Suppression forcée du répertoire home : $HOME_DIR"
        
        # Vérifier les processus utilisant ce répertoire
        if lsof "$HOME_DIR" 2>/dev/null | grep -q "$HOME_DIR"; then
            echo "    ⚠ Processus actifs détectés dans $HOME_DIR, arrêt forcé..."
            lsof "$HOME_DIR" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null
            sleep 1
        fi
        
        # Changer les permissions pour forcer la suppression
        chmod -R 755 "$HOME_DIR" 2>/dev/null
        chattr -R -i "$HOME_DIR" 2>/dev/null  # Supprimer les attributs immutables si présents
        
        # Tentative de suppression
        if rm -rf "$HOME_DIR" 2>/dev/null; then
            echo "    ✓ Répertoire home supprimé : $HOME_DIR"
        else
            echo "    ⚠ ATTENTION: Répertoire home persistant : $HOME_DIR"
            echo "    Raisons possibles : fichiers verrouillés, attributs spéciaux, ou permissions"
            echo "    Commandes manuelles à essayer :"
            echo "      sudo lsof '$HOME_DIR' 2>/dev/null"
            echo "      sudo chattr -R -i '$HOME_DIR' 2>/dev/null"
            echo "      sudo rm -rf '$HOME_DIR'"
        fi
    else
        echo "    - Répertoire home non trouvé, invalide ou déjà supprimé"
    fi
else
    echo "   - Utilisateur système '$CLIENT' non trouvé"
    
    # Vérifier s'il existe un répertoire home orphelin
    ORPHAN_HOME_DIR="/home/$CLIENT"
    if [[ -d "$ORPHAN_HOME_DIR" ]]; then
        echo "    ⚠ Répertoire home orphelin détecté : $ORPHAN_HOME_DIR"
        echo "    Suppression du répertoire home orphelin..."
        
        # Vérifier les processus utilisant ce répertoire
        if lsof "$ORPHAN_HOME_DIR" 2>/dev/null | grep -q "$ORPHAN_HOME_DIR"; then
            echo "    ⚠ Processus actifs détectés dans $ORPHAN_HOME_DIR, arrêt forcé..."
            lsof "$ORPHAN_HOME_DIR" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null
            sleep 1
        fi
        
        # Changer les permissions pour forcer la suppression
        chmod -R 755 "$ORPHAN_HOME_DIR" 2>/dev/null
        chattr -R -i "$ORPHAN_HOME_DIR" 2>/dev/null  # Supprimer les attributs immutables si présents
        
        # Tentative de suppression
        if rm -rf "$ORPHAN_HOME_DIR" 2>/dev/null; then
            echo "    ✓ Répertoire home orphelin supprimé : $ORPHAN_HOME_DIR"
        else
            echo "    ⚠ ATTENTION: Répertoire home orphelin persistant : $ORPHAN_HOME_DIR"
            echo "    Commandes manuelles à essayer :"
            echo "      sudo lsof '$ORPHAN_HOME_DIR' 2>/dev/null"
            echo "      sudo chattr -R -i '$ORPHAN_HOME_DIR' 2>/dev/null"
            echo "      sudo rm -rf '$ORPHAN_HOME_DIR'"
        fi
    else
        echo "    - Aucun répertoire home orphelin trouvé"
    fi
fi

# Redémarrer Apache pour prendre en compte les changements
echo "Redémarrage d'Apache..."
systemctl restart httpd
echo "    Service Apache redémarré"

echo ""
echo "Suppression du client '$CLIENT' terminée avec succès !"
echo "   Domaine supprimé : $DOMAIN"
echo "   Tous les services ont été redémarrés."
echo ""
echo "Note : Vérifiez manuellement les logs si nécessaire :"
echo "   - Apache : /var/log/httpd/"
echo "   - MySQL : /var/log/mysqld.log ou /var/log/mariadb/mariadb.log"
echo "   - DNS : /var/log/messages"