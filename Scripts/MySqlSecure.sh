#!/bin/bash

# Choix mdp root MariaDB
read -s -p "Entrez le mot de passe root que vous désirez : " MARIADB_ROOT_PASSWORD
echo
read -s -p "Confirmez le mot de passe root : " MARIADB_ROOT_PASSWORD_CONFIRM
echo

if [ "$MARIADB_ROOT_PASSWORD" != "$MARIADB_ROOT_PASSWORD_CONFIRM" ]; then
    echo "Les mots de passe ne correspondent pas. Abandon."
    exit 1
fi

# Sauvegarde du mot de passe root pour les scripts
echo "$MARIADB_ROOT_PASSWORD" | sudo tee /root/.mariadb_root_pass > /dev/null
sudo chmod 600 /root/.mariadb_root_pass

echo "[*] Configuration sécurisée de MariaDB..."

# Forcer l'utilisation de mysql_native_password pour root
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MARIADB_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Sécurisation classique
if command -v mysql_secure_installation &> /dev/null; then
    sudo mysql_secure_installation <<EOF
$MARIADB_ROOT_PASSWORD
n
n
Y
Y
Y
Y
EOF
else
    sudo mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';"
    sudo mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');"
    sudo mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;"
    sudo mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    sudo mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
fi

echo "[+] mysql_secure_installation terminé avec succès."
