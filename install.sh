#!/usr/bin/env bash

# ====== Színek ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

msg() { echo -e "${CYAN}[*]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERR]${NC} $1"; }

set -e

echo -e "${BLUE}== Node-RED + Apache2 + MariaDB + phpMyAdmin telepítő ==${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  err "Ezt a scriptet rootként kell futtatni. Használd így:  sudo bash install.sh"
  exit 1
fi

# --- Rendszer frissítés ---
msg "Rendszer frissítése (apt-get update && apt-get upgrade)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
ok "Rendszer sikeresen frissítve."

# --- Alap eszközök ---
msg "Alap eszközök telepítése (curl, wget, unzip)..."
apt-get install -y curl wget unzip
ok "Alap eszközök telepítve."

# --- Node-RED telepítés (automatikusan, kérdések nélkül) ---
msg "Node-RED és Node.js telepítése (automatikus, non-interactive)..."
curl -sL https://github.com/node-red/linux-installers/releases/latest/download/update-nodejs-and-nodered-deb \
  -o /tmp/nodered-install.sh
export DEBIAN_FRONTEND=noninteractive
yes | bash /tmp/nodered-install.sh --confirm-root --confirm-install --skip-pi --nocolors || true
ok "Node-RED telepítve és beállítva (non-interactive)."

# --- Apache2, MariaDB, PHP ---
msg "Apache2, MariaDB és PHP telepítése..."
apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql
ok "Apache2, MariaDB, PHP telepítve."

msg "Apache2 és MariaDB szolgáltatások engedélyezése és indítása..."
systemctl enable apache2
systemctl enable mariadb
systemctl start apache2
systemctl start mariadb
ok "Apache2 és MariaDB fut."

# --- MariaDB user létrehozása ---
msg "MariaDB felhasználó létrehozása (user / user123)..."
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
ok "MariaDB user létrehozva (user / user123)."

# --- phpMyAdmin letöltése és telepítése ---
msg "phpMyAdmin letöltése..."
cd /tmp
wget -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
unzip -q phpmyadmin.zip
rm phpmyadmin.zip

msg "Régi /usr/share/phpmyadmin törlése (ha létezett)..."
rm -rf /usr/share/phpmyadmin

msg "phpMyAdmin áthelyezése végleges helyére..."
mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin

msg "phpMyAdmin tmp könyvtár és jogosultságok beállítása..."
mkdir -p /usr/share/phpmyadmin/tmp
chown -R www-data:www-data /usr/share/phpmyadmin
chmod 777 /usr/share/phpmyadmin/tmp
ok "phpMyAdmin könyvtárak beállítva."

# --- Apache konfig phpMyAdminhoz ---
msg "Apache2 konfiguráció létrehozása phpMyAdminhoz..."
cat >/etc/apache2/conf-available/phpmyadmin.conf <<'APACHECONF'
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
APACHECONF

a2enconf phpmyadmin

# --- phpMyAdmin alap config ---
msg "phpMyAdmin config.inc.php létrehozása..."
cat >/usr/share/phpmyadmin/config.inc.php <<'PHPCONF'
<?php
$cfg['blowfish_secret'] = 'ValamiNagyonHosszúEsVéletlenszerűJelsorozat1234567890';
$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
PHPCONF

# --- Apache újratöltése ---
msg "Apache2 újratöltése..."
systemctl reload apache2
ok "Apache2 újratöltve."

echo
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN} TELEPÍTÉS KÉSZ!${NC}"
echo -e "${YELLOW} Node-RED:    ${NC}http://<szerver-ip>:1880"
echo -e "${YELLOW} phpMyAdmin:  ${NC}http://<szerver-ip>/phpmyadmin"
echo
echo -e "${CYAN} MariaDB belépés phpMyAdminban:${NC}"
echo -e "   Felhasználó: ${YELLOW}user${NC}"
echo -e "   Jelszó:      ${YELLOW}user123${NC}"
echo
echo -e "${RED}FONTOS:${NC} éles rendszeren AZONNAL változtasd meg a user123 jelszót!"
echo -e "${GREEN}==============================${NC}"
echo
