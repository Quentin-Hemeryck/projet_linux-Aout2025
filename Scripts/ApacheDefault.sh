#!/bin/bash

# Création du dossier racine

cat > /etc/httpd/conf.d/00-default.conf <<EOF
 
<VirtualHost *:80>
    ServerName linuxserver.lan
    DocumentRoot /var/www/linuxserver.lan
    Redirect permanent / https://linuxserver.lan/
</VirtualHost>

<VirtualHost *:443>
    ServerName linuxserver.lan
    DocumentRoot /var/www/linuxserver.lan

    SSLEngine on
    SSLCertificateFile /etc/ssl/linuxserver.lan/linuxserver.lan.crt
    SSLCertificateKeyFile /etc/ssl/linuxserver.lan/linuxserver.lan.key

    <Directory /var/www/linuxserver.lan>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

sudo systemctl restart httpd
