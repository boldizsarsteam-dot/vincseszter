#!/usr/bin/env bash

#########################################
#  🌈 INTERAKTÍV, FULL-EXTRA INSTALLER 🌈
#########################################

# ====== Verzió / changelog ======
SCRIPT_VERSION="v1.2.0"
SCRIPT_CHANGELOG=(
  "- Új: 'Csak frissítés (update mód)' menüpont (7)"
  "- Új: Rendszer / környezet infó kiírása induláskor"
  "- Új: Verzió- és changelog kijelzése a fejléc alatt"
  "- Új: Teljes eltávolítás (UNINSTALL mód) menüpont (8)"
)

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
  # 1. param: leírás, további paramok: parancs
  local desc="$1"
  shift
  step "$desc"
  set +e
  "$@" &>/tmp/vincs_install_step.log &
  local pid=$!
  spinner "$pid" "$desc"
  wait "$pid"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo -e "\n${CROSS} ${RED}Hiba a következő lépésnél:${NC} $desc (kód: $rc)"
    echo -e "${WARN} Részletek:"
    sed -e 's/^/  /' /tmp/vincs_install_step.log || true
    exit $rc
  fi
  echo -e "\n${CHECK} $desc kész."
}

msg()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()   { echo -e "${CHECK} $1"; }
err()  { echo -e "${CROSS} $1"; }
warn() { echo -e "${WARN} $1"; }

print_system_info() {
  echo
  echo -e "${CYAN}Rendszer információk:${NC}"

  # OS
  local OS_NAME="Ismeretlen"
  local OS_VER=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VER="$VERSION"
  fi

  # Virtualizáció
  local VIRT="ismeretlen"
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null || echo "ismeretlen")
    [[ -z "$VIRT" ]] && VIRT="nincs / bare metal"
  fi

  # CPU
  local CPU_CORES
  CPU_CORES=$(nproc 2>/dev/null || echo "?")

  # RAM
  local RAM_TOTAL_KB RAM_GB
  RAM_TOTAL_KB=$(grep -i MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
  if [[ -n "$RAM_TOTAL_KB" ]]; then
    RAM_GB=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_KB/1024/1024}")
  else
    RAM_GB="ismeretlen"
  fi

  # Disk (root)
  local ROOT_FREE_HUMAN ROOT_FREE_KB
  ROOT_FREE_HUMAN=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
  ROOT_FREE_KB=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')

  echo "- OS:            $OS_NAME $OS_VER"
  echo "- Virtualizáció: $VIRT"
  echo "- CPU magok:     $CPU_CORES"
  echo "- RAM:           ${RAM_GB} GB"
  echo "- Root szabad:   ${ROOT_FREE_HUMAN}"

  # Figyelmeztetések
  if [[ -n "$RAM_TOTAL_KB" ]] && (( RAM_TOTAL_KB < 1024*1024 )); then
    warn "Kevesebb mint 1 GB RAM – Node-RED / MariaDB szűkösen futhat."
  fi
  if [[ -n "$ROOT_FREE_KB" ]] && (( ROOT_FREE_KB < 5*1024*1024 )); then
    warn "Kevesebb mint 5 GB szabad hely a / kötetre – adatbázis / logok megtelhetnek."
  fi
  echo
}

echo -e "${MAGENTA}"
echo '╔══════════════════════════════════════════════════════════════╗'
echo '║  Node-RED + Apache2 + MariaDB + phpMyAdmin + MQTT + mc + nmon║'
echo '╚══════════════════════════════════════════════════════════════╝'
echo -e "${NC}"

echo -e "${CYAN}Verzió:${NC} ${YELLOW}${SCRIPT_VERSION}${NC}"
echo -e "${CYAN}Changelog:${NC}"
for line in "${SCRIPT_CHANGELOG[@]}"; do
  echo "  ${line}"
done

# --- Root ellenőrzés ---
if [[ $EUID -ne 0 ]]; then
  err "Ezt a scriptet rootként kell futtatni!"
  echo "Használd így: sudo bash install.sh"
  exit 1
fi

# --- Logolás fájlba ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGFILE="/var/log/vincseszter-install-$TIMESTAMP.log"
mkdir -p /var/log
touch "$LOGFILE" 2>/dev/null || LOGFILE="/tmp/vincseszter-install-$TIMESTAMP.log"
exec > >(tee -a "$LOGFILE") 2>&1

msg "Logolás ide: $LOGFILE"

# --- IP cím detektálása ---
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP_ADDR" ] && IP_ADDR="szerver-ip"

# --- Rendszer infó kiírása ---
print_system_info

#########################################
#  MENÜ – MIT CSINÁLJON A SCRIPT?
#########################################

INSTALL_NODE_RED=0
INSTALL_LAMP=0          # Apache2 + MariaDB + PHP + phpMyAdmin
INSTALL_MQTT=0          # Mosquitto
INSTALL_MC=0
INSTALL_NMON=0
DO_HARDEN=0             # Security hardening (MariaDB+MQTT)
UPDATE_ONLY=0           # Csak frissítés mód
UNINSTALL_MODE=0        # Teljes eltávolítás mód

echo -e "${CYAN}Mit szeretnél csinálni?${NC}"
echo -e "  ${YELLOW}0${NC} - MINDENT telepít (hardening nélkül)"
echo -e "  ${YELLOW}1${NC} - Node-RED (ha van node + npm)"
echo -e "  ${YELLOW}2${NC} - Apache2 + MariaDB + PHP + phpMyAdmin"
echo -e "  ${YELLOW}3${NC} - MQTT szerver (Mosquitto)"
echo -e "  ${YELLOW}4${NC} - mc (Midnight Commander)"
echo -e "  ${YELLOW}5${NC} - nmon (rendszer monitor)"
echo -e "  ${YELLOW}6${NC} - Security hardening (MariaDB jelszó + MQTT auth)"
echo -e "  ${YELLOW}7${NC} - Csak frissítés (update mód, NINCS új telepítés)"
echo -e "  ${YELLOW}8${NC} - Teljes eltávolítás (UNINSTALL mód – mindent leszed)"
echo
echo -e "${CYAN}Többet is megadhatsz szóközzel elválasztva, pl.:${NC}  ${YELLOW}1 3 4${NC}"
echo -e "${CYAN}Mindent telepíteni:${NC} ${YELLOW}0${NC}, hardeninghez add hozzá a 6-ost is (pl. 0 6)"
echo -e "${CYAN}Csak frissítéshez:${NC} ${YELLOW}7${NC}"
echo -e "${CYAN}Teljes törléshez:${NC} ${YELLOW}8${NC}"
echo

# /dev/tty-ról olvasunk, hogy curl | bash esetén is működjön
read -rp "Választás (pl. 0 vagy 1 2 5): " CHOICES </dev/tty || CHOICES=""

if echo "$CHOICES" | grep -qw "0"; then
  INSTALL_NODE_RED=1
  INSTALL_LAMP=1
  INSTALL_MQTT=1
  INSTALL_MC=1
  INSTALL_NMON=1
fi

for c in $CHOICES; do
  case "$c" in
    1) INSTALL_NODE_RED=1 ;;
    2) INSTALL_LAMP=1 ;;
    3) INSTALL_MQTT=1 ;;
    4) INSTALL_MC=1 ;;
    5) INSTALL_NMON=1 ;;
    6) DO_HARDEN=1 ;;
    7) UPDATE_ONLY=1 ;;
    8) UNINSTALL_MODE=1 ;;
    0) ;; # már kezeltük
    *) warn "Ismeretlen opció: $c (kihagyva)" ;;
  esac
done

# Ha uninstall mód be van kapcsolva, az felülír mindent
if [[ $UNINSTALL_MODE -eq 1 ]]; then
  if [[ $UPDATE_ONLY -eq 1 ]] || [[ $INSTALL_NODE_RED -eq 1 || $INSTALL_LAMP -eq 1 || $INSTALL_MQTT -eq 1 || $INSTALL_MC -eq 1 || $INSTALL_NMON -eq 1 || $DO_HARDEN -eq 1 ]]; then
    warn "A 8-as (UNINSTALL mód) más opciókkal együtt lett megadva – a többi opciót figyelmen kívül hagyom, csak törölni fogok."
  fi
  INSTALL_NODE_RED=0
  INSTALL_LAMP=0
  INSTALL_MQTT=0
  INSTALL_MC=0
  INSTALL_NMON=0
  DO_HARDEN=0
  UPDATE_ONLY=0
fi

# Ha csak update módot választott, de mellette mást is, akkor az update módot ignoráljuk
if [[ $UPDATE_ONLY -eq 1 ]] && \
   [[ $INSTALL_NODE_RED -eq 1 || $INSTALL_LAMP -eq 1 || $INSTALL_MQTT -eq 1 || $INSTALL_MC -eq 1 || $INSTALL_NMON -eq 1 || $DO_HARDEN -eq 1 ]]; then
  warn "A 7-es (csak frissítés) telepítési opciókkal együtt lett megadva, az update módot figyelmen kívül hagyom."
  UPDATE_ONLY=0
fi

# Ha semmit nem választott, és update/uninstall mód sincs
if [[ $INSTALL_NODE_RED -eq 0 && $INSTALL_LAMP -eq 0 && $INSTALL_MQTT -eq 0 && $INSTALL_MC -eq 0 && $INSTALL_NMON -eq 0 && $DO_HARDEN -eq 0 && $UPDATE_ONLY -eq 0 && $UNINSTALL_MODE -eq 0 ]]; then
  err "Nem választottál semmit, kilépek."
  exit 0
fi

#########################################
#  KÜLÖN: CSAK FRISSÍTÉS (UPDATE MÓD)
#########################################
if [[ $UPDATE_ONLY -eq 1 ]]; then
  echo
  msg "Csak frissítés (update mód) kiválasztva – nem telepítek új komponenseket."

  TOTAL_STEPS=3
  CURRENT_STEP=0

  run_with_spinner "Rendszer frissítése (apt-get update && upgrade)" \
    bash -c 'apt-get update -y && apt-get upgrade -y'

  step "Node-RED frissítése (ha telepítve npm-ből)"
  if command -v npm >/dev/null 2>&1 && npm list -g node-red >/dev/null 2>&1; then
    set +e
    npm update -g node-red &>/tmp/vincs_install_step.log
    RC=$?
    set -e
    if [[ $RC -eq 0 ]]; then
      ok "Node-RED npm update sikeres."
    else
      warn "Node-RED npm update NEM sikerült, nézd meg a logot: $LOGFILE"
    fi
  else
    warn "Node-RED nincs npm-ből telepítve, ezt a lépést kihagyom."
  fi

  step "Szolgáltatások újraindítása (Apache2, MariaDB, Mosquitto, Node-RED ha van)"
  systemctl restart apache2 2>/dev/null || true
  systemctl restart mariadb 2>/dev/null || true
  systemctl restart mosquitto 2>/dev/null || true
  systemctl restart node-red 2>/dev/null || true
  ok "Szolgáltatások újraindítva (ha telepítve voltak)."

  echo
  echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║          ✅ UPDATE MÓD FUTTATVA ✅            ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
  echo
  echo "Log fájl: $LOGFILE"
  echo
  exit 0
fi

#########################################
#  KÜLÖN: TELJES ELTÁVOLÍTÁS (UNINSTALL MÓD)
#########################################
if [[ $UNINSTALL_MODE -eq 1 ]]; then
  echo
  msg "TELJES ELTÁVOLÍTÁS (UNINSTALL mód) kiválasztva – mindent törlök, amit ez a script felrakott."

  TOTAL_STEPS=4
  CURRENT_STEP=0

  step "Szolgáltatások leállítása (apache2, mariadb, mosquitto, node-red)"
  systemctl stop apache2 2>/dev/null || true
  systemctl stop mariadb 2>/dev/null || true
  systemctl stop mosquitto 2>/dev/null || true
  systemctl stop node-red 2>/dev/null || true
  ok "Szolgáltatások leállítva (amelyek léteztek)."

  step "MariaDB user törlése (user@localhost)"
  set +e
  mysql -u root <<EOF
DROP USER IF EXISTS 'user'@'localhost';
FLUSH PRIVILEGES;
EOF
  set -e
  ok "MariaDB user (user@localhost) törölve (ha létezett)."

  step "Node-RED eltávolítása npm-ből"
  set +e
  npm uninstall -g node-red &>/dev/null || true
  set -e
  ok "Node-RED npm csomag eltávolítva (ha telepítve volt)."

  step "phpMyAdmin és Mosquitto extra configok törlése"
  rm -rf /usr/share/phpmyadmin
  rm -f /etc/apache2/conf-available/phpmyadmin.conf
  rm -f /etc/apache2/conf-enabled/phpmyadmin.conf
  rm -f /etc/mosquitto/conf.d/local.conf
  ok "phpMyAdmin könyvtár és extra Mosquitto config törölve (ha léteztek)."

  step "Csomagok purge-ölése + autoremove"
  apt-get purge -y apache2 apache2-bin apache2-data apache2-utils \
    mariadb-server mariadb-client \
    mosquitto mosquitto-clients \
    mc nmon \
    php libapache2-mod-php php-mysql php-mbstring php-zip php-gd php-json php-curl || true
  apt-get autoremove -y || true
  apt-get autoclean -y || true
  ok "Apache2, MariaDB, Mosquitto, mc, nmon, PHP csomagok törölve (ha voltak)."

  echo
  echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║        ✅ TELJES ELTÁVOLÍTÁS KÉSZ ✅          ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
  echo
  echo "Log fájl: $LOGFILE"
  echo
  echo -e "${YELLOW}Most újra futtathatod a telepítést, mintha szűz gép lenne (Node.js/npm kivételével).${NC}"
  echo
  exit 0
fi

#########################################
#  Lépések számolása (telepítés mód)
#########################################
TOTAL_STEPS=3  # update+upgrade, alap csomagok, vincs-install helper

[[ $INSTALL_NODE_RED -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # Node-RED + service opció
[[ $INSTALL_LAMP -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 4))  # LAMP + phpMyAdmin + dashboard + HTTP selftest
[[ $INSTALL_MQTT -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # MQTT + selftest
[[ $INSTALL_MC -eq 1       ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ $INSTALL_NMON -eq 1     ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[[ $DO_HARDEN   -eq 1      ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # MariaDB + MQTT hardening

#########################################
#  1️⃣ Rendszer frissítés + alap csomagok
#########################################

run_with_spinner "Rendszer frissítése (apt-get update && upgrade)" \
  bash -c 'apt-get update -y && apt-get upgrade -y'

run_with_spinner "Alap eszközök telepítése (curl, wget, unzip, ca-certificates)" \
  apt-get install -y curl wget unzip ca-certificates gnupg lsb-release

# vincs-install helper script
step "vincs-install helper parancs létrehozása (/usr/local/bin/vincs-install)"
ALIASESCRIPT="/usr/local/bin/vincs-install"
cat >"$ALIASESCRIPT" <<'ALIAS'
#!/usr/bin/env bash
curl -sL https://raw.githubusercontent.com/boldizsarsteam-dot/vincseszter/main/install.sh | sudo bash
ALIAS
chmod +x "$ALIASESCRIPT"
ok "Helper parancs telepítve: 'vincs-install' (használat: sudo vincs-install)"

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
    warn "Node.js NINCS telepítve."
  fi

  if command -v npm >/dev/null 2>&1; then
    ok "npm megtalálva: $(npm -v)"
    HAS_NPM=1
  else
    warn "npm NINCS telepítve."
  fi

  if [[ $HAS_NODE -eq 1 && $HAS_NPM -eq 1 ]]; then
    run_with_spinner "Node-RED telepítése npm-mel (globálisan)" \
      npm install -g --unsafe-perm node-red

    # systemd service létrehozása
    SERVICE="/etc/systemd/system/node-red.service"
    if [[ ! -f "$SERVICE" ]]; then
      step "Node-RED systemd service létrehozása"
      cat >"$SERVICE" <<'UNIT'
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
      ok "node-red.service létrehozva."
    else
      warn "node-red.service már létezik, nem módosítom."
    fi

    # kérdés autoindításról
    echo
    read -rp "Induljon a Node-RED automatikusan bootkor? (y/n): " NR_AUTO </dev/tty || NR_AUTO="n"
    if [[ "$NR_AUTO" =~ ^[Yy]$ ]]; then
      run_with_spinner "Node-RED service engedélyezése és indítása" \
        systemctl enable --now node-red
    else
      msg "Node-RED service létrejött, de nincs engedélyezve (indítás: systemctl start node-red)."
    fi
  else
    warn "Node-RED telepítése kihagyva, mert nincs teljes Node.js + npm."
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
  ok "phpMyAdmin beállítva (http://$IP_ADDR/phpmyadmin)."

  # HTML dashboard Apache root alatt
  step "Vincseszter dashboard HTML oldal létrehozása (/var/www/html/index.html)"
  cat >/var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="hu">
<head>
  <meta charset="UTF-8">
  <title>Vincseszter Server Dashboard</title>
  <style>
    body { font-family: Arial, sans-serif; background:#0f172a; color:#e5e7eb; margin:0; padding:20px; }
    h1 { text-align:center; color:#38bdf8; }
    .ip { text-align:center; margin-bottom:20px; }
    .grid { display:flex; flex-wrap:wrap; gap:16px; justify-content:center; }
    .card { background:#1f2937; border-radius:12px; padding:16px 20px; min-width:260px; box-shadow:0 4px 12px rgba(0,0,0,0.4); }
    .card h2 { margin-top:0; color:#a5b4fc; }
    a { color:#38bdf8; text-decoration:none; }
    a:hover { text-decoration:underline; }
    .tag { display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; background:#111827; margin-top:4px; }
    .warn { color:#f97316; font-size:13px; margin-top:4px; }
    .footer { text-align:center; margin-top:30px; font-size:12px; color:#9ca3af; }
    code { background:#111827; padding:2px 4px; border-radius:4px; }
  </style>
</head>
<body>
  <h1>Vincseszter Server Dashboard</h1>
  <div class="ip">
    <p><strong>Szerver IP:</strong> $IP_ADDR</p>
  </div>
  <div class="grid">
    <div class="card">
      <h2>Node-RED</h2>
      <p>Flow alapú IoT / automatizálási szerver.</p>
      <p><a href="http://$IP_ADDR:1880" target="_blank">→ Megnyitás</a></p>
      <div class="tag">node-red</div>
      <p class="warn">Indítás: <code>node-red</code> vagy <code>systemctl start node-red</code></p>
    </div>
    <div class="card">
      <h2>phpMyAdmin</h2>
      <p>Webes felület a MariaDB adatbázis kezelésére.</p>
      <p><a href="http://$IP_ADDR/phpmyadmin" target="_blank">→ Megnyitás</a></p>
      <div class="tag">LAMP</div>
      <p class="warn">Teszt user: <code>user / user123</code> – élesben NE hagyd így!</p>
    </div>
    <div class="card">
      <h2>MQTT broker</h2>
      <p>Mosquitto MQTT szerver IoT eszközökhöz.</p>
      <p>Host: <code>$IP_ADDR</code>, Port: <code>1883</code></p>
      <div class="tag">MQTT</div>
      <p class="warn">Fejlesztéshez anonymous ON – élesben állíts be felhasználót.</p>
    </div>
    <div class="card">
      <h2>mc &amp; nmon</h2>
      <p><code>mc</code> – Midnight Commander fájlkezelő.</p>
      <p><code>nmon</code> – rendszer monitor.</p>
      <div class="tag">CLI tools</div>
      <p class="warn">Indítás: <code>mc</code> vagy <code>nmon</code> a terminálból.</p>
    </div>
  </div>
  <div class="footer">
    <p>Install script verzió: ${SCRIPT_VERSION}</p>
    <p>Log fájl: $LOGFILE</p>
  </div>
</body>
</html>
EOF
  ok "Dashboard oldal elkészült: http://$IP_ADDR/"

  # Apache HTTP self-test
  step "Apache HTTP self-test (curl http://127.0.0.1)"
  if command -v curl >/dev/null 2>&1 && curl -Isf "http://127.0.0.1" >/dev/null 2>&1; then
    ok "Apache HTTP self-test OK (200)."
  else
    warn "Apache HTTP self-test NEM sikerült."
  fi
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

  # MQTT self-test
  step "MQTT self-test (publish/subscribe loopback)"
  if command -v mosquitto_pub >/dev/null 2>&1 && command -v mosquitto_sub >/dev/null 2>&1; then
    mosquitto_sub -h localhost -t 'vincseszter/test' -C 1 -W 3 >/tmp/mqtt_test.out 2>/dev/null &
    SUB_PID=$!
    sleep 0.5
    mosquitto_pub -h localhost -t 'vincseszter/test' -m 'ok' >/dev/null 2>&1 || true
    wait "$SUB_PID" || true
    if grep -q 'ok' /tmp/mqtt_test.out 2>/dev/null; then
      ok "MQTT self-test OK (üzenet visszaérkezett)."
    else
      warn "MQTT self-test NEM sikerült."
    fi
  else
    warn "mosquitto_pub / mosquitto_sub nem érhető el, self-test kihagyva."
  fi
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
#  7️⃣ Security hardening (opcionális)
#########################################
if [[ $DO_HARDEN -eq 1 ]]; then
  echo -e "${BLUE}--- Security hardening ---${NC}"

  # MariaDB jelszócsere 'user' felhasználónak
  if [[ $INSTALL_LAMP -eq 1 ]]; then
    msg "MariaDB 'user' jelszó csere (Enter -> kihagyás)."
    read -s -rp "Új jelszó a 'user' számára: " NEW_DB_PW </dev/tty || NEW_DB_PW=""
    echo
    if [[ -n "$NEW_DB_PW" ]]; then
      read -s -rp "Jelszó mégegyszer: " NEW_DB_PW2 </dev/tty || NEW_DB_PW2=""
      echo
      if [[ "$NEW_DB_PW" != "$NEW_DB_PW2" ]]; then
        warn "Nem egyezik, MariaDB jelszócsere kihagyva."
      else
        step "MariaDB 'user' jelszó frissítése"
        ESCAPED_PW=$(printf "%s" "$NEW_DB_PW" | sed "s/'/''/g")
        mysql -u root -e "ALTER USER 'user'@'localhost' IDENTIFIED BY '$ESCAPED_PW'; FLUSH PRIVILEGES;"
        ok "MariaDB 'user' jelszó frissítve."
      fi
    else
      warn "Nem adtál meg új jelszót, MariaDB hardening kihagyva."
    fi
  else
    warn "LAMP nincs telepítve, MariaDB hardening kihagyva."
  fi

  # MQTT hardening
  if [[ $INSTALL_MQTT -eq 1 ]]; then
    msg "MQTT hardening (anonymous OFF, password auth)."
    read -rp "MQTT felhasználónév (Enter -> kihagyás): " MQTT_USER </dev/tty || MQTT_USER=""
    if [[ -n "$MQTT_USER" ]]; then
      read -s -rp "MQTT jelszó: " MQTT_PW </dev/tty || MQTT_PW=""
      echo
      read -s -rp "MQTT jelszó mégegyszer: " MQTT_PW2 </dev/tty || MQTT_PW2=""
      echo
      if [[ "$MQTT_PW" != "$MQTT_PW2" ]]; then
        warn "Nem egyezik, MQTT hardening kihagyva."
      else
        if command -v mosquitto_passwd >/dev/null 2>&1; then
          step "Mosquitto password auth beállítása"
          mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PW"
          cat >/etc/mosquitto/conf.d/local.conf <<EOF
listener 1883
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF
          systemctl restart mosquitto
          ok "MQTT hardening kész (anonymous OFF, user: $MQTT_USER)."
        else
          warn "mosquitto_passwd nem érhető el, MQTT hardening kihagyva."
        fi
      fi
    else
      warn "Nem adtál meg MQTT usert, MQTT hardening kihagyva."
    fi
  else
    warn "MQTT nincs telepítve, MQTT hardening kihagyva."
  fi
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
    warn "ss parancs nem elérhető, nem tudom ellenőrizni a(z) $name portját."
  fi
}

echo
echo -e "${CYAN}Health check:${NC}"
if [[ $INSTALL_LAMP -eq 1 ]]; then
  check_port 80 "Apache2 (HTTP)"
endif
::contentReference[oaicite:0]{index=0}
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
  echo -e "| Node-RED       | http://$IP_ADDR:1880       |"
fi
if [[ $INSTALL_LAMP -eq 1 ]]; then
  echo -e "| Dashboard      | http://$IP_ADDR/           |"
  echo -e "| phpMyAdmin     | http://$IP_ADDR/phpmyadmin |"
fi
if [[ $INSTALL_MQTT -eq 1 ]]; then
  echo -e "| MQTT broker    | $IP_ADDR:1883              |"
fi
if [[ $INSTALL_MC -eq 1 ]]; then
  echo -e "| mc             | parancs: mc                |"
fi
if [[ $INSTALL_NMON -eq 1 ]]; then
  echo -e "| nmon           | parancs: nmon              |"
fi

echo -e "${BLUE}+----------------+-----------------------------+${NC}"

#########################################
#  Összefoglaló + pro tipp
#########################################
echo
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               ✅ TELEPÍTÉS KÉSZ ✅             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo
echo "Log fájl: $LOGFILE"
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
  "Tipp: Node-RED-et érdemes systemd service-ként futtatni, hogy bootkor induljon."
  "Tipp: MQTT-hez használj user/jelszó auth-ot és TLS-t éles rendszeren."
  "Tipp: mc-ben F10 a kilépés, F5 másol, F6 mozgat."
  "Tipp: Vincseszter dashboard: http://$IP_ADDR/"
  "Tipp: Csak frissítéshez elég a 7-es opciót választani a menüben."
  "Tipp: Teljes törléshez a 8-as menüpontot válaszd."
)

RANDOM_TIP=${TIPS[$RANDOM % ${#TIPS[@]}]}
echo -e "${YELLOW}$RANDOM_TIP${NC}"
echo

