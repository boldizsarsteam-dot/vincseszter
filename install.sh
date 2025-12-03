#!/usr/bin/env bash

#########################################
#  🌈 INTERAKTÍV, SZÍNES INSTALLER 🌈   #
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
echo '╔══════════════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin + MQTT + mc + nmon║'
echo '╚══════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${CROSS} Ezt a scriptet rootként kell futtatni!"
  echo "Használd így: sudo bash install.sh"
  exit 1
fi

#########################################
#  MENÜ – MIT TELEPÍTSEN A SCRIPT?
#########################################

INSTALL_NODE_RED=0
INSTALL_LAMP=0          # Apache2 + MariaDB + PHP + phpMyAdmin
INSTALL_MQTT=0          # Mosquitto
INSTALL_MC=0
INSTALL_NMON=0

echo -e "${CYAN}Mit szeretnél telepíteni?${NC}"
echo -e "  ${YELLOW}0${NC} - MINDENT telepít"
echo -e "  ${YELLOW}1${NC} - Node-RED (ha van node + npm)"
echo -e "  ${YELLOW}2${NC} - Apache2 + MariaDB + PHP + phpMyAdmin"
echo -e "  ${YELLOW}3${NC} - MQTT szerver (Mosquitto)"
echo -e "  ${YELLOW}4${NC} - mc (Midnight Commander)"
echo -e "  ${YELLOW}5${NC} - nmon (rendszer monitor)"
echo
echo -e "${CYAN}Többet is megadhatsz szóközzel elválasztva, pl.:${NC}  ${YELLOW}1 3 4${NC}"
echo -e "${CYAN}Mindent telepíteni:${NC} ${YELLOW}0${NC}"
echo

# FONTOS: /dev/tty-ról olvasunk, hogy működjön curl | bash esetén is
read -rp "Választás (pl. 0 vagy 1 2 5): " CHOICES </dev/tty || CHOICES=""

if echo "$CHOICES" | grep -qw "0"; then
  INSTALL_NODE_RED=1
  INSTALL_LAMP=1
  INSTALL_MQTT=1
  INSTALL_MC=1
  INSTALL_NMON=1
else
  for c in $CHOICES; do
    case "$c" in
      1) INSTALL_NODE_RED=1 ;;
      2) INSTALL_LAMP=1 ;;
      3) INSTALL_MQTT=1 ;;
      4) INSTALL_MC=1 ;;
      5) INSTALL_NMON=1 ;;
      *) echo -e "${WARN} Ismeretlen opció: ${YELLOW}$c${NC} (kihagyva)";;
    esac
  done
fi

if [[ $INSTALL_NODE_RED -eq 0 && $INSTALL_LAMP -eq 0 && $INSTALL_MQTT -eq 0 && $INSTALL_MC -eq 0 && $INSTALL_NMON -eq 0 ]]; then
  echo -e "${CROSS} Nem választottál semmit, kilépek."
  exit 0
fi

#########################################
#  1️⃣ Rendszer frissítés + alap csomagok
#########################################
echo -e "${CYAN}[*] Rendszer frissítése (apt-get update && upgrade)...${NC}"
apt-get update -y
apt-get upgrade -y
echo -e "${CHECK} Rendszer frissítve."

echo -e "${CYAN}[*] Alap eszközök telepítése (curl, wget, unzip, ca-certificates)...${NC}"
apt-get install -y curl wget unzip ca-certificates gnupg lsb-release
echo -e "${CHECK} Alap csomagok telepítve."

#########################################
#  2️⃣ Node-RED (ha kérted)
#########################################
if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo -e "${BLUE}--- Node-RED telepítés ---${NC}"
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
  fi
fi

#########################################
#  3️⃣ Apache2 + MariaDB + PHP + phpMyAdmin
#########################################
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "${BLUE}--- Apache2 + MariaDB + PHP + phpMyAdmin telepítés ---${NC}"

  echo -e "${CYAN}[*] Apache2, MariaDB és PHP telepítése...${NC}"
  apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
    php-mbstring php-zip php-gd php-json php-curl
  systemctl enable apache2 mariadb
  systemctl start apache2 mariadb
  echo -e "${CHECK} Apache2 és MariaDB telepítve és fut."

  echo -e "${CYAN}[*] MariaDB felhasználó létrehozása (user / user123)...${NC}"
  mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
  echo -e "${CHECK} MariaDB user létrehozva (user / user123)."

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
fi

#########################################
#  4️⃣ MQTT (Mosquitto)
#########################################
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${BLUE}--- MQTT (Mosquitto) telepítés ---${NC}"
  echo -e "${CYAN}[*] Mosquitto MQTT szerver telepítése...${NC}"
  apt-get install -y mosquitto mosquitto-clients

  mkdir -p /etc/mosquitto/conf.d
  cat >/etc/mosquitto/conf.d/local.conf <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

  systemctl enable mosquitto
  systemctl restart mosquitto
  echo -e "${CHECK} Mosquitto MQTT fut a ${YELLOW}1883${NC} porton (anonymous enabled)."
fi

#########################################
#  5️⃣ mc (Midnight Commander)
#########################################
if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "${BLUE}--- mc telepítés ---${NC}"
  apt-get install -y mc
  echo -e "${CHECK} mc telepítve. Indítás: ${YELLOW}mc${NC}"
fi

#########################################
#  6️⃣ nmon
#########################################
if [[ $INSTALL_NMON -eq 1 ]]; then
  echo -e "${BLUE}--- nmon telepítés ---${NC}"
  apt-get install -y nmon
  echo -e "${CHECK} nmon telepítve. Indítás: ${YELLOW}nmon${NC}"
fi

#########################################
#  7️⃣ Összefoglaló
#########################################
echo
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               ✅ TELEPÍTÉS KÉSZ ✅             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo

if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo -e "${GREEN}Node-RED (ha sikerült a telepítés):${NC}  http://<szerver-ip>:1880"
  echo -e "${YELLOW}Indítás:${NC}  node-red"
  echo
fi

if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "${GREEN}phpMyAdmin:${NC}  http://<szerver-ip>/phpmyadmin"
  echo -e "  MariaDB user: ${YELLOW}user${NC}"
  echo -e "  Jelszó:       ${YELLOW}user123${NC}"
  echo
fi

if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${GREEN}MQTT (Mosquitto):${NC}  host: <szerver-ip>  port: ${YELLOW}1883${NC}"
  echo -e "  (fejlesztéshez anonymous engedélyezve)"
  echo
fi

if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "${GREEN}mc:${NC}   parancs: ${YELLOW}mc${NC}"
fi

if [[ $INSTALL_NMON -eq 1 ]]; then
  echo -e "${GREEN}nmon:${NC} parancs: ${YELLOW}nmon${NC}"
fi

if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo
  echo -e "${RED}⚠ FONTOS:${NC} éles rendszeren VÁLTOZTASD MEG a MariaDB jelszót!"
fi

if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${RED}⚠ MQTT:${NC} éles rendszeren NE hagyd anonymous módban a Mosquittót!"
fi

echo
