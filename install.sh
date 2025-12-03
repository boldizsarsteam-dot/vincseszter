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

# Globális lépésszámláló
TOTAL_STEPS=0
CURRENT_STEP=0

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo -e "${BLUE}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} $1"
}

spinner() {
  local pid=$1
  local text="$2"
  local spin='-\|/'
  local i=0
  echo -ne " ${text} "
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) %4 ))
    printf "\b${spin:$i:1}"
    sleep 0.1
  done
  echo -ne "\b"
}

run_with_spinner() {
  # 1. param: leírás, továbbiak: parancs
  local desc="$1"
  shift
  step "$desc"
  set +e
  "$@" &>/tmp/install_tmp.log &
  local pid=$!
  spinner "$pid" "$desc"
  wait "$pid"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo -e "\n${CROSS} ${RED}Hiba a következő lépésnél:${NC} $desc (kód: $rc)"
    echo -e "${WARN} Részletek:"
    sed -e 's/^/  /' /tmp/install_tmp.log || true
    exit $rc
  fi
  echo -e "\n${CHECK} $desc kész."
}

msg()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${CHECK} $1"; }
err()  { echo -e "${CROSS} $1"; }

echo -e "${MAGENTA}"
echo '╔══════════════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin + MQTT + mc + nmon║'
echo '╚══════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  err "Ezt a scriptet rootként kell futtatni!"
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

# /dev/tty-ról olvasunk, hogy curl | bash esetén is működjön
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
  err "Nem választottál semmit, kilépek."
  exit 0
fi

#########################################
#  Lépések számolása
#########################################
# 1: rendszer frissítés, 2: alap csomagok
TOTAL_STEPS=2
[[ $INSTALL_NODE_RED -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ $INSTALL_LAMP -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # LAMP + phpMyAdmin
[[ $INSTALL_MQTT -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ $INSTALL_MC -eq 1       ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ $INSTALL_NMON -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

#########################################
#  1️⃣ Rendszer frissítés + alap csomagok
#########################################

run_with_spinner "Rendszer frissítése (apt-get update && upgrade)" \
  bash -c 'apt-get update -y && apt-get upgrade -y'

run_with_spinner "Alap eszközök telepítése (curl, wget, unzip, ca-certificates)" \
  apt-get install -y curl wget unzip ca-certificates gnupg lsb-release

#########################################
#  2️⃣ Node-RED (ha kérted)
#########################################
if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo -e "${BLUE}--- Node-RED telepítés ---${NC}"
  msg "Node.js / npm ellenőrzése..."

  HAS_NODE=0
  HAS_NPM=0

  if command -v node >/dev/null 2>&1; then
    ok "Node.js megtalálva: $(node -v)"
    HAS_NODE=1
  else
    echo -e "${WARN} Node.js NINCS telepítve."
  fi

  if command -v npm >/dev/null 2>&1; then
    ok "npm megtalálva: $(npm -v)"
    HAS_NPM=1
  else
    echo -e "${WARN} npm NINCS telepítve."
  fi

  if [[ $HAS_NODE -eq 1 && $HAS_NPM -eq 1 ]]; then
    run_with_spinner "Node-RED telepítése npm-mel (globálisan)" \
      npm install -g --unsafe-perm node-red
  else
    echo -e "${WARN} Node-RED telepítése kihagyva, mert nincs teljes Node.js + npm."
  fi
fi

#########################################
#  3️⃣ Apache2 + MariaDB + PHP + phpMyAdmin
#########################################
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "${BLUE}--- Apache2 + MariaDB + PHP + phpMyAdmin telepítés ---${NC}"

  run_with_spinner "Apache2, MariaDB és PHP telepítése" \
    apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql \
      php-mbstring php-zip php-gd php-json php-curl

  systemctl enable apache2 mariadb
  systemctl start apache2 mariadb
  ok "Apache2 és MariaDB telepítve és fut."

  step "MariaDB felhasználó létrehozása (user / user123)"
  mysql -u root <<EOF
CREATE USER IF NOT EXISTS 'user'@'localhost' IDENTIFIED BY 'user123';
GRANT ALL PRIVILEGES ON *.* TO 'user'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
  ok "MariaDB user létrehozva (user / user123)."

  step "phpMyAdmin letöltése és telepítése"
  cd /tmp
  wget -q -O phpmyadmin.zip https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
  unzip -q phpmyadmin.zip
  rm phpmyadmin.zip

  rm -rf /usr/share/phpmyadmin
  mv phpMyAdmin-*-all-languages /usr/share/phpmyadmin

  mkdir -p /usr/share/phpmyadmin/tmp
  chown -R www-data:www-data /usr/share/phpmyadmin
  chmod 777 /usr/share/phpmyadmin/tmp
  ok "phpMyAdmin könyvtárak beállítva."

  step "Apache2 konfiguráció létrehozása phpMyAdminhoz"
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

  step "phpMyAdmin config.inc.php létrehozása"
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
  ok "phpMyAdmin beállítva (http://<szerver-ip>/phpmyadmin)."
fi

#########################################
#  4️⃣ MQTT (Mosquitto)
#########################################
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${BLUE}--- MQTT (Mosquitto) telepítés ---${NC}"
  run_with_spinner "Mosquitto MQTT szerver telepítése" \
    apt-get install -y mosquitto mosquitto-clients

  mkdir -p /etc/mosquitto/conf.d
  cat >/etc/mosquitto/conf.d/local.conf <<'MQTTCONF'
listener 1883
allow_anonymous true
MQTTCONF

  systemctl enable mosquitto
  systemctl restart mosquitto
  ok "Mosquitto MQTT fut a 1883 porton (anonymous enabled)."
fi

#########################################
#  5️⃣ mc (Midnight Commander)
#########################################
if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "${BLUE}--- mc telepítés ---${NC}"
  run_with_spinner "mc telepítése" \
    apt-get install -y mc
  ok "mc telepítve. Indítás: mc"
fi

#########################################
#  6️⃣ nmon
#########################################
if [[ $INSTALL_NMON -eq 1 ]]; then
  echo -e "${BLUE}--- nmon telepítés ---${NC}"
  run_with_spinner "nmon telepítése" \
    apt-get install -y nmon
  ok "nmon telepítve. Indítás: nmon"
fi

#########################################
#  Health check – port ellenőrzés
#########################################
check_port() {
  local port=$1
  local name=$2
  if command -v ss >/dev/null 2>&1; then
    if ss -tln 2>/dev/null | grep -q ":$port "; then
      echo -e "${CHECK} $name fut a ${YELLOW}$port${NC} porton."
    else
      echo -e "${CROSS} $name NEM fut a ${YELLOW}$port${NC} porton."
    fi
  else
    echo -e "${WARN} ss parancs nem elérhető, nem tudom ellenőrizni a(z) $name portját."
  fi
}

echo
echo -e "${CYAN}Health check:${NC}"
if [[ $INSTALL_LAMP -eq 1 ]]; then
  check_port 80 "Apache2 (HTTP)"
fi
if [[ $INSTALL_MQTT -eq 1 ]]; then
  check_port 1883 "MQTT (Mosquitto)"
fi

#########################################
#  Summary table
#########################################
echo
echo -e "${BLUE}+----------------+-----------------------------+${NC}"
echo -e "${BLUE}| Szolgáltatás   | Elérés / Megjegyzés        |${NC}"
echo -e "${BLUE}+----------------+-----------------------------+${NC}"

if [[ $INSTALL_NODE_RED -eq 1 ]]; then
  echo -e "| Node-RED       | http://<ip>:1880           |"
fi
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "| phpMyAdmin     | http://<ip>/phpmyadmin     |"
fi
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "| MQTT broker    | <ip>:1883 (anonymous ON)   |"
fi
if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "| mc             | parancs: mc                |"
fi
if [[ $INSTALL_NMON -eq 1 ]]; then
  echo -e "| nmon           | parancs: nmon              |"
fi

echo -e "${BLUE}+----------------+-----------------------------+${NC}"

#########################################
#  7️⃣ Összefoglaló + pro tipp
#########################################
echo
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               ✅ TELEPÍTÉS KÉSZ ✅             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo

if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "${RED}⚠ FONTOS:${NC} éles rendszeren VÁLTOZTASD MEG a MariaDB jelszót (user123)!"
fi

if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "${RED}⚠ MQTT:${NC} éles rendszeren NE hagyd anonymous módban a Mosquittót!"
fi

echo

TIPS=(
  "Tipp: csinálj alias-t: alias vincs='curl -sL https://raw.githubusercontent.com/boldizsarsteam-dot/vincseszter/main/install.sh | sudo bash'"
  "Tipp: Node-RED-et érdemes systemd service-ként beállítani, hogy bootkor induljon."
  "Tipp: MQTT-hez használj felhasználó/jelszó alapú auth-ot éles rendszeren."
  "Tipp: mc-ben F10 a kilépés, F5 másol, F6 mozgat."
)

RANDOM_TIP=${TIPS[$RANDOM % ${#TIPS[@]}]}
echo -e "${YELLOW}$RANDOM_TIP${NC}"
echo
