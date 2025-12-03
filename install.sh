#!/usr/bin/env bash

#########################################
#  🌈 FULL COLOR NODE-RED INSTALLER 🌈  #
#########################################

# ====== Színek és ikonok ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"

set -e

echo -e "${MAGENTA}"
echo '╔════════════════════════════════════════════════════════════════╗'
echo '║     🚀  Node-RED + Apache2 + MariaDB + phpMyAdmin Installer    ║'
echo '╚════════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${CROSS} ${RED}Ezt a scriptet rootként kell futtatni!${NC}"
  echo "Használd így: sudo bash install.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

#########################################
#  1️⃣ Rendszer frissítés
#########################################
echo -e "${CYAN}[*] Rendszer frissítése...${NC}"
apt-get update -y && apt-get upgrade -y
echo -e "${CHECK} Rendszer frissítve!"

#########################################
#  2️⃣ Alap eszközök
#########################################
echo -e "${CYAN}[*] Alap eszközök telepítése...${NC}"
apt-get install -y curl wget gnupg lsb-release ca-certificates unzip
echo -e "${CHECK} Alap eszközök telepítve!"

#########################################
#  3️⃣ Node.js 20.x + Node-RED (NPM-ből)
#########################################
echo -e "${CYAN}[*] Node.js 20.x hivatalos NodeSource telepítése...${NC}"

# régi node eltávolítása, ha hibás
apt-get purge -y nodejs npm || true
rm -rf /etc/apt/sources.list.d/nodesource.list* || true

# NodeSource repo
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

# telepítés
apt-get install -y nodejs
echo -e "${CHECK} Node.js $(node -v) és npm $(npm -v) telepítve!"

echo -e "${CYAN}[*] Node-RED telepítése npm segítségével...${NC}"
npm install -g --unsafe-perm node-red
echo -e "${CHECK} Node-RED telepítve globálisan!"

#########################################
#  4️⃣ Apache2 + MariaDB + PHP
#########################################
echo -e "${CYAN}[*] Apache2, MariaDB és PHP telepítése...${NC}"
apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
  php-mbstring php-zip php-gd php-json php-curl
systemctl enable apache2 mariadb
systemctl start apache2 mariadb
echo -e "${CHECK} Apache2 és MariaDB fut."

#########################################
#  5️⃣ MariaDB user létrehozása
#########################################
echo -e "${CYAN}[*] MariaDB user létrehozása (user / user123)...${NC}"
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
echo -e "${CHECK} MariaDB felhasználó kész."

#########################################
#  6️⃣ phpMyAdmin telepítés
#########################################
echo -e "${CYAN}[*] phpMyAdmin letöltése és beállítása...${NC}"
cd /tmp
wget -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
unzip -q phpmyadmin.zip && rm phpmyadmin.zip
rm -rf /usr/share/phpmyadmin
mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin
mkdir -p /usr/share/phpmyadmin/tmp
chown -R www-data:www-data /usr/share/phpmyadmin
chmod 777 /usr/share/phpmyadmin/tmp

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

cat >/usr/share/phpmyadmin/config.inc.php <<'PHPCONF'
<?php
$cfg['blowfish_secret'] = 'RandomStrongSecretKeyForPhpMyAdmin123456789!';
$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['AllowNoPassword'] = false;
PHPCONF

systemctl reload apache2
echo -e "${CHECK} phpMyAdmin elérhető: http://<ip>/phpmyadmin"

#########################################
#  7️⃣ Összefoglaló
#########################################
echo
echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               ✅  TELEPÍTÉS KÉSZ! ✅                 ║${NC}"
echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Node-RED:${NC}    http://<szerver-ip>:1880"
echo -e "${YELLOW}Indítás kézzel:${NC}  node-red"
echo -e "${YELLOW}Szolgáltatásként:${NC} systemctl enable --now node-red"
echo
echo -e "${GREEN}phpMyAdmin:${NC} http://<szerver-ip>/phpmyadmin"
echo -e "${YELLOW}Bejelentkezés:${NC} user / user123"
echo
echo -e "${RED}⚠ FONTOS:${NC} Éles rendszeren AZONNAL változtasd meg a jelszót!"
echo
