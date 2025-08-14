#!/bin/bash

clear
echo "=== Suppression complète d'un client ==="

# Demande du nom du client
read -p "Entrez le nom du client à supprimer : " CLIENT
if [[ -z "$CLIENT" ]]; then
    echo "[ERREUR] Le nom du client est obligatoire."
    exit 1
fi

# Vérification anti-suppression root
if [[ "$CLIENT" == "root" ]]; then
    echo "[ERREUR] Impossible de supprimer l'utilisateur root."
    exit 1
fi

# Protection du domaine principal
if [[ "$CLIENT" == "linuxserver" ]]; then
    echo "[ERREUR] Impossible de supprimer le domaine principal linuxserver.lan."
    exit 1
fi

# Vérification existence utilisateur
if ! id "$CLIENT" &>/dev/null; then
    echo "[ERREUR] L'utilisateur '$CLIENT' n'existe pas."
    exit 1
fi

DOMAIN="$CLIENT.linuxserver.lan"

DOCUMENT_ROOT="/var/www/$CLIENT"
VHOST_CONF="/etc/httpd/conf.d/$CLIENT.conf"
CERT_FILE="/etc/pki/tls/certs/$DOMAIN.crt"
KEY_FILE="/etc/pki/tls/private/$DOMAIN.key"
ZONE_FILE="/var/named/linuxserver.lan.zone"

DB_NAME="$CLIENT"
DB_USER="$CLIENT"

# Confirmation
echo
read -p "Confirmez-vous la suppression TOTALE de $CLIENT et de toutes ses données ? (O/N) : " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Oo]$ ]]; then
    echo "[ANNULATION] Aucune suppression effectuée."
    exit 0
fi

echo
echo "[INFO] Début de la suppression pour : $CLIENT"
echo "------------------------------------------"

# 1. Suppression Apache
if [ -f "$VHOST_CONF" ]; then
    sudo rm -f "$VHOST_CONF"
    echo "[✓] Fichier de configuration Apache supprimé"
fi
if [ -d "$DOCUMENT_ROOT" ]; then
    sudo rm -rf "$DOCUMENT_ROOT"
    echo "[✓] Dossier web supprimé"
fi
sudo rm -f "$CERT_FILE" "$KEY_FILE" && echo "[✓] Certificats SSL supprimés"

# 1bis. Création d'un VirtualHost de blocage
BLOCK_VHOST="/etc/httpd/conf.d/${CLIENT}_blocked.conf"
sudo bash -c "cat > $BLOCK_VHOST <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect 403 /
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    SSLEngine on
    SSLCertificateFile /etc/ssl/linuxserver.lan/linuxserver.lan.crt
    SSLCertificateKeyFile /etc/ssl/linuxserver.lan/linuxserver.lan.key
    Redirect 403 /
</VirtualHost>
EOF"
echo "[✓] VirtualHost de blocage créé pour $DOMAIN"

# 2. Suppression DNS
if [ -f "$ZONE_FILE" ] && grep -q "^$CLIENT\s" "$ZONE_FILE"; then
    sudo sed -i "/^$CLIENT\s/d" "$ZONE_FILE"
    echo "[✓] Entrée DNS supprimée"
    NEW_SERIAL=$(date +%Y%m%d)$(printf "%02d" 01)
    sudo sed -i -E "s/([0-9]{10}) ; Serial/${NEW_SERIAL} ; Serial/" "$ZONE_FILE"
    sudo systemctl restart named
fi

# 3. Suppression Base de données + utilisateur MariaDB
if [ -f /root/.mariadb_root_pass ]; then
    MYSQL_ROOT_PWD=$(cat /root/.mariadb_root_pass)
    sudo mysql -u root -p"$MYSQL_ROOT_PWD" <<EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
DROP USER IF EXISTS '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF
    echo "[✓] Base de données et utilisateur MariaDB supprimés"
else
    echo "[!] Impossible de trouver le mot de passe root MariaDB (/root/.mariadb_root_pass)"
fi

# 4. Suppression utilisateur FTP / Samba / Linux + /home
sudo smbpasswd -x "$CLIENT" 2>/dev/null
sudo pkill -u "$CLIENT" 2>/dev/null
sudo userdel -r "$CLIENT" 2>/dev/null
sudo rm -rf "/home/$CLIENT" 2>/dev/null
echo "[✓] Utilisateur et /home supprimés"

# 5. Suppression quota
sudo setquota -u "$CLIENT" 0 0 0 0 /var/www 2>/dev/null
sudo setquota -u "$CLIENT" 0 0 0 0 /srv/nfs/share 2>/dev/null
echo "[✓] Quotas réinitialisés"

# 6. Nettoyage du partage Samba
SAMBA_CONF="/etc/samba/smb.conf"
if grep -q "^\[$CLIENT\]$" "$SAMBA_CONF"; then
    sudo sed -i "/^\[$CLIENT\]/,/^$/d" "$SAMBA_CONF"
    echo "[✓] Partage Samba supprimé"
    sudo systemctl restart smb
fi

# 7. Redémarrage des services principaux
sudo systemctl restart httpd
sudo systemctl restart named
sudo systemctl restart vsftpd

echo "------------------------------------------"
echo "[FIN] Suppression terminée pour $CLIENT"
