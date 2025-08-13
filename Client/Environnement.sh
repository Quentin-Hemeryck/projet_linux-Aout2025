#!/bin/bash

# Variables
CLIENT=$1
DOMAIN=$2
FTP_PASSWORD=$3
DB_PASS=$4

DOCUMENT_ROOT="/var/www/$CLIENT"
FTP_USER=$CLIENT
DB_NAME="$CLIENT"
DB_USER="$CLIENT"

SOFT_LIMIT=${SOFT_LIMIT:-102400}  # 100 Mo
HARD_LIMIT=${HARD_LIMIT:-153600}  # 150 Mo

# Vérifier mot de passe root MariaDB
if [ ! -f /root/.mariadb_root_pass ]; then
    echo "[ERREUR] Mot de passe root MariaDB introuvable (/root/.mariadb_root_pass)"
    exit 1
fi
MYSQL_ROOT_PWD=$(cat /root/.mariadb_root_pass)

# Créer utilisateur Linux
sudo useradd -m -s /bin/bash $CLIENT

# Dossier web
sudo mkdir -p $DOCUMENT_ROOT
sudo chown -R $CLIENT:$CLIENT $DOCUMENT_ROOT
sudo chmod -R 755 $DOCUMENT_ROOT

# Config FTP
echo "$FTP_USER:$FTP_PASSWORD" | sudo chpasswd
grep -q "^$FTP_USER$" /etc/vsftpd/user_list || echo "$FTP_USER" | sudo tee -a /etc/vsftpd/user_list > /dev/null
sudo usermod -d $DOCUMENT_ROOT $FTP_USER
sudo chown $FTP_USER:$FTP_USER $DOCUMENT_ROOT

# Base MariaDB + utilisateur
sudo mysql -u root -p"$MYSQL_ROOT_PWD" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

# Infos
echo "Utilisateur $CLIENT créé avec succès."
echo "Domaine web : $DOMAIN"
echo "Utilisateur FTP : $FTP_USER"
echo "Base de données : $DB_NAME"
echo "Utilisateur DB : $DB_USER"

# Quotas
sudo setquota -u "$CLIENT" $SOFT_LIMIT $HARD_LIMIT 0 0 /var/www
sudo setquota -u "$CLIENT" $SOFT_LIMIT $HARD_LIMIT 0 0 /srv/nfs/share
