#!/usr/bin/env bash

#############################
#  SZÍNES TELEPÍTŐ SCRIPT   #
#############################

# ====== Színek ======
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

msg()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

set -e

echo -e "${BLUE}"
echo '╔══════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin telepítő  ║'
echo '╚══════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  err "Ezt a scriptet rootként kell futtatni. Használd így:  sudo bash install.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

#############################
#  RENDSZER FRISSÍTÉS       #
#############################
msg "Rendszer frissítése (apt-get update && apt-get upgrade)..."
apt-get update -y
apt-get upgrade -y
ok "Rendszer sikeresen frissítve."

#############################
#  ALAP CSOMAGOK            #
#############################
msg "Alap eszközök telepítése (curl, wget, unzip, ca-certificates)..."
apt-get install -y curl wget unzip ca-certificates gnupg lsb-release
ok "Alap eszközök telepítve."

#############################
#  NODE.JS + NODE-RED       #
#############################
msg "Node.js és npm telepítése a disztribúció csomagjából..."
apt-get install -y nodejs npm
ok "Node.js és npm telepítve."

msg "Node-RED telepítése npm-mel (globálisan)..."
npm install -g --unsafe-perm node-red
ok "Node-RED telepítve."

warn "Node-RED NEM indul el automatikusan, és nem futtatunk semmilyen interaktív varázslót."

# Opcionális systemd service létrehozása, de NEM engedélyezzük
SERVICE_PATH="/etc/systemd/system/node-red.service"
if [[ ! -f "$SERVICE_PATH" ]]; then
  msg "systemd szolgáltatás fájl létrehozása Node-RED-hez (de nem engedélyezzük)..."
  cat >"$SERVICE_PATH" <<'UNIT'
[Unit]
Description=Node-RED
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/env node-red
Restart=on-failure
Environment="NODE_OPTIONS=--max_old_space_size=256"

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  ok "node-red.service létrehozva (de NINCS engedélyezve)."
else
  warn "node-red.service már létezik, nem módosítom."
fi

#############################
#  APACHE2 + MARIADB + PHP  #
#############################
msg "Apache2, MariaDB és PHP telepítése..."
apt-get install -y apache2 mariadb-server \
  php libapache2-mod-php php-mysql php-mbstring php-zip php-gd php-json php-curl
ok "Apache2, MariaDB és PHP telepítve."

msg "Apache2 és MariaDB szolgáltatások engedélyezése és indítása..."
systemctl enable apache2
systemctl enable mariadb
systemctl start apache2
systemctl start mariadb
ok "Apache2 és MariaDB fut."

#############################
#  MARIADB USER             #
#############################
msg "MariaDB felhasználó létrehozása (user / user123)..."
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
ok "MariaDB user létrehozva (user / user123)."

#############################
#  PHPMYADMIN TELEPÍTÉS     #
#############################
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

#############################
#  APACHE KONFIG            #
#############################
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

#############################
#  PHPMYADMIN CONFIG        #
#############################
msg "phpMyAdmin config.inc.php létrehozása..."
cat >/usr/share/phpmyadmin/config.inc.php <<'PHPCONF'
<?php
$cfg['blowfish_secret'] = 'ValamiNagyonHosszúEsVéletlenszerűJelsorozat1234567890XYZ';
$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
PHPCONF

#############################
#  APACHE RELOAD            #
#############################
msg "Apache2 újratöltése..."
systemctl reload apache2
ok "Apache2 újratöltve."

#############################
#  ÖSSZEFOGLALÓ             #
#############################
echo
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           TELEPÍTÉS KÉSZ!           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo
echo -e "${MAGENTA} Node-RED:${NC}    http://<szerver-ip>:1880"
echo -e "  Indítás kézzel: ${YELLOW}node-red${NC}  (pl. screen-ből vagy tmux-ból)"
echo -e "  VAGY szolgáltatásként: ${YELLOW}systemctl start node-red${NC}"
echo -e "  Automatikus induláshoz: ${YELLOW}systemctl enable node-red${NC}"
echo
echo -e "${MAGENTA} phpMyAdmin:${NC} http://<szerver-ip>/phpmyadmin"
echo -e "  MariaDB belépés:"
echo -e "    Felhasználó: ${YELLOW}user${NC}"
echo -e "    Jelszó:      ${YELLOW}user123${NC}"
echo
echo -e "${RED}FONTOS:${NC} éles rendszeren AZONNAL változtasd meg a user123 jelszót!"
echo
