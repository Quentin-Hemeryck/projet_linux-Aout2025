#!/bin/bash

# Variables
DOMAIN="linuxserver.lan"
DOC_ROOT="/var/www/$DOMAIN"
SSL_DIR="/etc/ssl/$DOMAIN"
CONF_FILE="/etc/httpd/conf.d/$DOMAIN.conf"

# Préparation
echo "[INFO] Création du dossier de certificat : $SSL_DIR"
mkdir -p "$SSL_DIR"

echo "[INFO] Génération du certificat auto-signé pour $DOMAIN"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/$DOMAIN.key" \
  -out "$SSL_DIR/$DOMAIN.crt" \
  -subj "/C=BE/ST=Hainaut/L=Mons/O=LinuxServerCorp/OU=Web/CN=$DOMAIN"

# Création de la page d'accueil
mkdir -p "$DOC_ROOT"
cat <<'EOF' > "$DOC_ROOT/index.html"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>linuxserver.lan</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #000000;
            color: #ffffff;
            line-height: 1.6;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 60px 40px;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        header {
            text-align: center;
            margin-bottom: 60px;
        }
        h1 {
            font-size: 3rem;
            font-weight: 300;
            margin-bottom: 15px;
            color: #ffffff;
            letter-spacing: -0.02em;
        }
        .subtitle {
            color: #9ca3af;
            font-size: 1.1rem;
            font-weight: 400;
        }
        .services {
            display: grid;
            gap: 20px;
            margin-bottom: 60px;
        }
        .service {
            display: flex;
            align-items: center;
            padding: 25px;
            background: #1a1a1a;
            border: 1px solid #333333;
            border-radius: 8px;
            text-decoration: none;
            color: inherit;
            transition: all 0.3s ease;
        }
        .service:hover {
            border-color: #4f46e5;
            background: #252525;
            transform: translateY(-2px);
        }
        .service-icon {
            width: 60px;
            height: 60px;
            background: #4f46e5;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 25px;
            font-size: 24px;
            color: white;
        }
        .service-content h3 {
            font-size: 1.3rem;
            font-weight: 500;
            margin-bottom: 8px;
            color: #ffffff;
        }
        .service-content p {
            color: #9ca3af;
            font-size: 1rem;
            font-weight: 400;
        }
        .footer {
            text-align: center;
            color: #6b7280;
            font-size: 0.9rem;
            border-top: 1px solid #333333;
            padding-top: 30px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>linuxserver.lan</h1>
            <p class="subtitle">Services disponibles</p>
        </header>

        <main class="services">
            <a href="http://linuxserver.lan/phpMyAdmin" target="_blank" class="service">
                <div class="service-icon">🗄️</div>
                <div class="service-content">
                    <h3>phpMyAdmin</h3>
                    <p>Administration de la base de données MySQL</p>
                </div>
            </a>

            <a href="http://linuxserver.lan:19999" target="_blank" class="service">
                <div class="service-icon">📊</div>
                <div class="service-content">
                    <h3>Monitoring</h3>
                    <p>Surveillance des ressources système en temps réel</p>
                </div>
            </a>
        </main>

        <footer class="footer">
            <p>© 2025 linuxserver.lan - Système interne v1.0</p>
        </footer>
    </div>
</body>
</html>
EOF

# Création du fichier de configuration Apache
echo "[INFO] Création du fichier de configuration Apache"
cat <<EOF > "$CONF_FILE"
<VirtualHost *:80>
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $DOC_ROOT

    SSLEngine on
    SSLCertificateFile $SSL_DIR/$DOMAIN.crt
    SSLCertificateKeyFile $SSL_DIR/$DOMAIN.key

    <Directory $DOC_ROOT>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Activation des modules nécessaires
echo "[INFO] Activation du module SSL (si nécessaire)"
dnf install -y mod_ssl

# Redémarrage du service Apache
echo "[INFO] Redémarrage d'Apache"
systemctl restart httpd

echo "[INFO] Configuration HTTPS terminée pour $DOMAIN" 