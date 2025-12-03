#!/usr/bin/env bash

#########################################
#  🌈 SIMPLE & COLORFUL INSTALLER 🌈    #
#########################################

# ====== Színek ======
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
export DEBIAN_FRONTEND=noninteractive

echo -e "${MAGENTA}"
echo '╔════════════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin + MQTT + mc + nmon  ║'
echo '╚════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${CROSS} Ezt a scriptet rootként kell futtatni!"
  echo "Használd így: sudo bash install.sh"
  exit 1
fi

#########################################
#  1️⃣ Rendszer frissítés
#########################################
echo -e "${CYAN}[*] Rendszer frissítése (apt-get update && upgrade)...${NC}"
apt-get update -y
apt-get upgrade -y
echo -e "${CHECK} Rendszer frissítve."

#########################################
#  2️⃣ Alap csomagok
#########################################
echo -e "${CYAN}[*] Alap eszközök telepítése (curl, wget, unzip, ca-certificates)...${NC}"
apt-get install -y curl wget unzip ca-certificates gnupg lsb-release
echo -e "${CHECK} Alap csomagok telepítve."

#########################################
#  3️⃣ Node.js / npm ellenőrzés + Node-RED
#########################################
echo -e "${CYAN}[*] Node.js / npm ellenőrzése...${NC}"

HAS_NODE=0
HAS_NPM=0

if command -v node >/dev/null 2>&1; then
  echo -e "${CHECK} Node.js megtalálva: ${YELLOW}$(node -v)${NC}"
  HAS_NODE=1
else
  echo -e "${WARN} Node.js NINCS telepítve."
fi

if command -v npm >/dev/null 2>&1; then
  echo -e "${CHECK} npm megtalálva: ${YELLOW}$(npm -v)${NC}"
  HAS_NPM=1
else
  echo -e "${WARN} npm NINCS telepítve."
fi

if [[ $HAS_NODE -eq 1 && $HAS_NPM -eq 1 ]]; then
  echo -e "${CYAN}[*] Node-RED telepítése npm-mel (globálisan)...${NC}"
  set +e
  npm install -g --unsafe-perm node-red
  NODERED_RC=$?
  set -e
  if [[ $NODERED_RC -eq 0 ]]; then
    echo -e "${CHECK} Node-RED sikeresen telepítve (npm -g node-red)."
  else
    echo -e "${WARN} Node-RED telepítése NEM sikerült. Később kézzel futtasd:"
    echo -e "     ${YELLOW}npm install -g --unsafe-perm node-red${NC}"
  fi
else
  echo -e "${WARN} Node-RED telepítése kihagyva, mert nincs teljes Node.js + npm."
  echo -e "     Telepíts Node.js-t külön, majd futtasd:"
  echo -e "     ${YELLOW}npm install -g --unsafe-perm node-red${NC}"
fi

#########################################
#  4️⃣ Apache2 + MariaDB + PHP
#########################################
echo -e "${CYAN}[*] Apache2, MariaDB és PHP telepítése...${NC}"
apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
  php-mbstring php-zip php-gd php-json php-curl
systemctl enable apache2 mariadb
systemctl start apache2 mariadb
echo -e "${CHECK} Apache2 és MariaDB telepítve és fut."

#########################################
#  5️⃣ MariaDB user létrehozása
#########################################
echo -e "${CYAN}[*] MariaDB felhasználó létrehozása (user / user123)...${NC}"
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
echo -e "${CHECK} MariaDB user létrehozva (user / user123)."

#########################################
#  6️⃣ phpMyAdmin telepítés
#########################################
echo -e "${CYAN}[*] phpMyAdmin letöltése és telepítése...${NC}"
cd /tmp
wget -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
unzip -q phpmyadmin.zip
rm phpmyadmin.zip

echo -e "${CYAN}[*] Régi /usr/share/phpmyadmin törlése (ha volt)...${NC}"
rm -rf /usr/share/phpmyadmin

mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin

mkdir -p /usr/share/phpmyadmin/tmp
chown -R www-data:www-data /usr/share/phpmyadmin
chmod 777 /usr/share/phpmyadmin/tmp
echo -e "${CHECK} phpMyAdmin könyvtárak beállítva."

echo -e "${CYAN}[*] Apache2 konfiguráció létrehozása phpMyAdminhoz...${NC}"
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

echo -e "${CYAN}[*] phpMyAdmin config.inc.php létrehozása...${NC}"
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
echo -e "${CHECK} phpMyAdmin beállítva (http://<szerver-ip>/phpmyadmin)."

#########################################
#  7️⃣ MQTT szerver (Mosquitto)
#########################################
echo -e "${CYAN}[*] Mosquitto MQTT szerver telepítése...${NC}"
apt-get install -y mosquitto mosquitto-clients

# egyszerű fejlesztői config: 1883 port, anonymous ON (LAN tesztre oké)
mkdir -p /etc/mosquitto/conf.d
cat >/etc/mosquitto/conf.d/local.conf <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

systemctl enable mosquitto
systemctl restart mosquitto
echo -e "${CHECK} Mosquitto MQTT fut a ${YELLOW}1883${NC} porton (anonymous enabled)."

#########################################
#  8️⃣ mc és nmon telepítése
#########################################
echo -e "${CYAN}[*] mc (Midnight Commander) és nmon telepítése...${NC}"
apt-get install -y mc nmon
echo -e "${CHECK} mc és nmon telepítve."
echo -e "    mc indítása: ${YELLOW}mc${NC}"
echo -e "  nmon indítása: ${YELLOW}nmon${NC}"

#########################################
#  9️⃣ Összefoglaló
#########################################
echo
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               ✅ TELEPÍTÉS KÉSZ ✅             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo
echo -e "${GREEN}Node-RED (ha sikerült a telepítés):${NC}  http://<szerver-ip>:1880"
echo -e "${YELLOW}Indítás:${NC}  node-red"
echo
echo -e "${GREEN}phpMyAdmin:${NC}  http://<szerver-ip>/phpmyadmin"
echo -e "  MariaDB user: ${YELLOW}user${NC}"
echo -e "  Jelszó:       ${YELLOW}user123${NC}"
echo
echo -e "${GREEN}MQTT (Mosquitto):${NC}  host: <szerver-ip>  port: ${YELLOW}1883${NC}"
echo -e "  (fejlesztéshez anonymous engedélyezve)"
echo
echo -e "${GREEN}mc:${NC}   parancs: ${YELLOW}mc${NC}"
echo -e "${GREEN}nmon:${NC} parancs: ${YELLOW}nmon${NC}"
echo
echo -e "${RED}⚠ FONTOS:${NC} éles rendszeren VÁLTOZTASD MEG a MariaDB jelszót,"
echo -e "          és az MQTT-n ÉRDEMES kikapcsolni az anonymous-t!"
echo
