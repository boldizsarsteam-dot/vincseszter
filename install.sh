#!/usr/bin/env bash
set -e

echo "== Node-RED + Apache2 + MariaDB + phpMyAdmin telepítő =="

if [[ $EUID -ne 0 ]]; then
  echo "Ezt a scriptet rootként kell futtatni. Használd így: sudo bash install.sh"
  exit 1
fi

echo "-> Csomaglista frissítése..."
apt update
apt upgrade -y

echo "-> Alap eszközök telepítése (curl, wget, unzip)..."
apt install -y curl wget unzip

echo "-> Node-RED és Node.js telepítése (Node-RED hivatalos installer)..."
bash <(curl -sL https://github.com/node-red/linux-installers/releases/latest/download/update-nodejs-and-nodered-deb)

echo "-> Node-RED szolgáltatás engedélyezése és indítása..."
systemctl enable nodered.service
systemctl start nodered.service

echo "-> Apache2, MariaDB, PHP telepítése..."
apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql

echo "-> Apache2 és MariaDB engedélyezése és indítása..."
systemctl enable apache2
systemctl enable mariadb
systemctl start apache2
systemctl start mariadb

echo "-> MariaDB felhasználó létrehozása (user / user123)..."
mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "-> phpMyAdmin letöltése és telepítése..."
cd /tmp
wget -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
unzip -q phpmyadmin.zip
rm phpmyadmin.zip

echo "-> Régi /usr/share/phpmyadmin törlése (ha volt)..."
rm -rf /usr/share/phpmyadmin

echo "-> phpMyAdmin áthelyezése a végleges helyére..."
mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin

echo "-> phpMyAdmin tmp mappa, jogosultságok beállítása..."
mkdir -p /usr/share/phpmyadmin/tmp
chown -R www-data:www-data /usr/share/phpmyadmin
chmod 777 /usr/share/phpmyadmin/tmp

echo "-> Apache2 konfiguráció létrehozása phpMyAdminhoz..."
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

echo "-> Minimális phpMyAdmin config.inc.php létrehozása..."
cat >/usr/share/phpmyadmin/config.inc.php <<'PHPCONF'
<?php
/* MINIMÁLIS phpMyAdmin konfiguráció */
$cfg['blowfish_secret'] = 'ValamiNagyonHosszúEsVéletlenszerűJelsorozat1234567890'; /* LEGALÁBB 32 KARAKTER! */

$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = false;
PHPCONF

echo "-> Apache újratöltése..."
systemctl reload apache2

echo
echo "==============================="
echo "TELEPÍTÉS KÉSZ!"
echo
echo "Node-RED:"
echo "  URL:  http://<szerver-ip>:1880"
echo
echo "phpMyAdmin:"
echo "  URL:  http://<szerver-ip>/phpmyadmin"
echo "  Bejelentkezésre használd a MariaDB felhasználót:"
echo "    Felhasználó: user"
echo "    Jelszó:      user123"
echo
echo "FONTOS: éles rendszeren AZONNAL változtasd meg a user123 jelszót!"
echo "==============================="
