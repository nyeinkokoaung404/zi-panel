#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION
# Author: 4 0 4 \ 2.0 [🇲🇲]
# Features: Complete Enterprise Management System with Bandwidth Control, Billing, Multi-Server, API, etc.
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION ${Z}\n$LINE"

# ===== Root check & apt guards =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R} script root accept (sudo -i)${Z}"; exit 1
fi
export DEBIAN_FRONTEND=noninteractive

wait_for_apt() {
  echo -e "${Y}⏳ wait apt 3 min ${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else return 0; fi
  done
  echo -e "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}

apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Enhanced Packages =====
say "${Y}📦 Enhanced Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-pip python3-venv iproute2 conntrack ca-certificates sqlite3 gzip >/dev/null || \
{
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask python3-pip iproute2 conntrack ca-certificates sqlite3 gzip >/dev/null
}

# Additional Python packages
pip3 install requests python-dateutil python-telegram-bot >/dev/null 2>&1 || true
apt_guard_end

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
systemctl stop zivpn-cleanup.timer 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
DB="/etc/zivpn/zivpn.db"
ENVF="/etc/zivpn/web.env"
BACKUP_DIR="/etc/zivpn/backups"
CLEANUP_PY="/etc/zivpn/cleanup.py"
WEB_PY="/etc/zivpn/web.py"
API_PY="/etc/zivpn/api.py"
BOT_PY="/etc/zivpn/bot.py"
mkdir -p /etc/zivpn "$BACKUP_DIR"

# ===== Download ZIVPN binary (Keep original logic) =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Enhanced Database Setup (Keep original schema for data integrity) =====
say "${Y}🗃️ Enhanced Database ဖန်တီးနေပါတယ်...${Z}"
sqlite3 "$DB" <<'EOF'
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expires DATE,
    port INTEGER,
    status TEXT DEFAULT 'active',
    bandwidth_limit INTEGER DEFAULT 0,
    bandwidth_used INTEGER DEFAULT 0,
    speed_limit_up INTEGER DEFAULT 0,
    speed_limit_down INTEGER DEFAULT 0,
    concurrent_conn INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS billing (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    plan_type TEXT DEFAULT 'monthly',
    amount REAL DEFAULT 0,
    currency TEXT DEFAULT 'MMK',
    payment_method TEXT,
    payment_status TEXT DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS bandwidth_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    bytes_used INTEGER DEFAULT 0,
    log_date DATE DEFAULT CURRENT_DATE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS server_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    total_bandwidth INTEGER DEFAULT 0,
    server_load REAL DEFAULT 0,
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_user TEXT NOT NULL,
    action TEXT NOT NULL,
    target_user TEXT,
    details TEXT,
    ip_address TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT DEFAULT 'info',
    read_status INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF

# ===== Base config (Keep original logic) =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs (Keep original logic) =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KHAINGUDP/OU=Net/CN=khaingudp" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Setup (Keep original logic for ENV) =====
say "${Y}🔒 Web Admin Login UI ${Z}"
read -r -p "Web Admin Username (Enter=admin): " WEB_USER
WEB_USER="${WEB_USER:-admin}"
read -r -s -p "Web Admin Password: " WEB_PASS; echo

# Generate strong secret
if command -v openssl >/dev/null 2>&1; then
  WEB_SECRET="$(openssl rand -hex 32)"
else
  WEB_SECRET="$(python3 - <<'PY'
import secrets;print(secrets.token_hex(32))
PY
)"
fi

{
  echo "WEB_ADMIN_USER=${WEB_USER}"
  echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
  echo "WEB_SECRET=${WEB_SECRET}"
  echo "DATABASE_PATH=${DB}"
} > "$ENVF"
chmod 600 "$ENVF"

# ===== Ask initial VPN passwords (Keep original logic) =====
say "${G}🔏 VPN Password List (eg: channel404,alice,pass1)${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then
  PW_LIST='["zi"]'
else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# Get Server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "${SERVER_IP:-}" ]; then
  SERVER_IP=$(curl -s icanhazip.com || echo "127.0.0.1")
fi

# ===== Update config.json (Keep original logic) =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" --arg ip "$SERVER_IP" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn") |
    .server = $ip
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== Enhanced Web Panel (Updated) =====
say "${Y}🖥️ Enhanced Web Panel ထည့်သွင်းနေပါတယ်...${Z}"
cat >"$WEB_PY" <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics

USERS_FILE = "/etc/zivpn/users.json" # Legacy, using DB now
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120 # Conntrack Timeout for "Online" status
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Language Map (Burmese/English) ---
LANG_MAP = {
    'en': {
        'title': 'Channel 404 ZIVPN Enterprise', 'subtitle': 'Enterprise Management System',
        'login_title': 'ZIVPN Panel Login', 'login_err': 'Invalid Credentials',
        'user': 'User', 'password': 'Password', 'expires': 'Expires', 'port': 'Port',
        'bandwidth': 'Bandwidth', 'speed': 'Speed', 'status': 'Status', 'actions': 'Actions',
        'total_users': 'Total Users', 'active_users': 'Active Users',
        'bw_used': 'Bandwidth Used', 'server_load': 'Server Load',
        'user_mgmt': 'User Management', 'add_user': 'Add New User',
        'bulk_ops': 'Bulk Operations', 'reports': 'Reports',
        'user_name_req': 'User and Password are required', 'expires_err': 'Invalid Expires format',
        'port_err': 'Port range 6000-19999', 'user_saved': 'User saved successfully',
        'confirm_delete': 'Do you want to delete {}?', 'online': 'ONLINE',
        'offline': 'OFFLINE', 'expired': 'EXPIRED', 'suspended': 'SUSPENDED',
        'unknown': 'UNKNOWN', 'speed_limit_mb': 'Speed Limit (MB/s)',
        'bw_limit_gb': 'Bandwidth Limit (GB)', 'max_conn': 'Max Connections',
        'plan_type': 'Plan Type', 'select_action': 'Select Action',
        'extend_7': 'Extend Expiry (+7 days)', 'suspend_users': 'Suspend Users',
        'activate_users': 'Activate Users', 'delete_users': 'Delete Users',
        'users_comma': 'Usernames comma separated (user1,user2)',
        'execute': 'Execute', 'export': 'Export Users CSV', 'import': 'Import Users',
        'search': 'Search users...', 'save_user': 'Save User', 'usage': 'Usage',
        'speed_limit': 'Speed Limit', 'delete_btn': 'Delete', 'edit_btn': 'Edit',
        'login_btn': 'Login', 'logout_btn': 'Logout', 'contact_btn': 'Contact',
        'from_date': 'From Date', 'to_date': 'To Date', 'report_type': 'Report Type',
        'generate_report': 'Generate Report', 'speed_limit_short': 'Speed (MB/s)',
        'bw_limit_short': 'BW (GB)', 'max_conn_short': 'Conn',
    },
    'my': {
        'title': 'Channel 404 ZIVPN Enterprise', 'subtitle': 'အဆင့်မြင့် စီမံခန့်ခွဲမှုစနစ်',
        'login_title': 'ZIVPN ထိန်းချုပ်ခန်း ဝင်ရန်', 'login_err': 'မှန်ကန်မှုမရှိပါ',
        'user': 'အသုံးပြုသူ', 'password': 'စကားဝှက်', 'expires': 'သက်တမ်းကုန်ဆုံးရက်', 'port': 'ပို့တ်',
        'bandwidth': 'ဒေတာပမာဏ', 'speed': 'အမြန်နှုန်း', 'status': 'အခြေအနေ', 'actions': 'လုပ်ဆောင်ချက်များ',
        'total_users': 'စုစုပေါင်းအသုံးပြုသူ', 'active_users': 'အသုံးပြုနေသူ',
        'bw_used': 'သုံးပြီးဒေတာ', 'server_load': 'ဆာဗာလုပ်ဆောင်မှု',
        'user_mgmt': 'အသုံးပြုသူ စီမံခန့်ခွဲမှု', 'add_user': 'အသုံးပြုသူ အသစ်ထည့်ပါ',
        'bulk_ops': 'အများအပြား လုပ်ဆောင်မှု', 'reports': 'အစီရင်ခံစာများ',
        'user_name_req': 'အသုံးပြုသူအမည်နှင့် စကားဝှက် လိုအပ်သည်', 'expires_err': 'သက်တမ်းကုန်ဆုံးရက် ပုံစံမမှန်ပါ',
        'port_err': 'ပို့တ် အကွာအဝေး 6000-19999', 'user_saved': 'အသုံးပြုသူအား အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ',
        'confirm_delete': '{} ကို ဖျက်ရန် သေချာပါသလား?', 'online': 'ချိတ်ဆက်ထားသည်',
        'offline': 'အဆက်ပြတ်နေသည်', 'expired': 'သက်တမ်းကုန်ဆုံး', 'suspended': 'ပိတ်ထားသည်',
        'unknown': 'မသိ', 'speed_limit_mb': 'အမြန်နှုန်း ကန့်သတ်ချက် (MB/s)',
        'bw_limit_gb': 'ဒေတာပမာဏ ကန့်သတ်ချက် (GB)', 'max_conn': 'အများဆုံး ချိတ်ဆက်မှု',
        'plan_type': 'စီမံကိန်းအမျိုးအစား', 'select_action': 'လုပ်ဆောင်ချက် ရွေးပါ',
        'extend_7': 'သက်တမ်းတိုးရန် (+၇ ရက်)', 'suspend_users': 'အသုံးပြုသူများ ပိတ်ရန်',
        'activate_users': 'အသုံးပြုသူများ ဖွင့်ရန်', 'delete_users': 'အသုံးပြုသူများ ဖျက်ရန်',
        'users_comma': 'အသုံးပြုသူအမည်များ ကော်မာဖြင့် ခွဲပါ (user1,user2)',
        'execute': 'လုပ်ဆောင်ပါ', 'export': 'အသုံးပြုသူများ CSV ထုတ်ရန်', 'import': 'အသုံးပြုသူများ တင်သွင်းရန်',
        'search': 'အသုံးပြုသူ ရှာဖွေပါ...', 'save_user': 'အသုံးပြုသူ သိမ်းဆည်းရန်', 'usage': 'အသုံးပြုမှု',
        'speed_limit': 'အမြန်နှုန်း ကန့်သတ်ချက်', 'delete_btn': 'ဖျက်မည်', 'edit_btn': 'ပြင်မည်',
        'login_btn': 'ဝင်မည်', 'logout_btn': 'ထွက်မည်', 'contact_btn': 'ဆက်သွယ်ရန်',
        'from_date': 'စတင်ရက်', 'to_date': 'နောက်ဆုံးရက်', 'report_type': 'အစီရင်ခံစာအမျိုးအစား',
        'generate_report': 'အစီရင်ခံစာ ထုတ်ပါ', 'speed_limit_short': 'အမြန်နှုန်း (MB/s)',
        'bw_limit_short': 'ဒေတာပမာဏ (GB)', 'max_conn_short': 'ချိတ်ဆက်မှု',
    }
}
DEFAULT_LANG = 'my'
# --- End Language Map ---

HTML = """<!doctype html>
<html lang="{{ lang }}" data-theme="{{ theme }}">
<head>
<meta charset="utf-8">
<title>{{ T.title }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root {
  --ok: #27ae60; --bad: #c0392b; --unk: #f39c12; --expired: #8e44ad; --info: #3498db; --success: #1abc9c;
  --delete-btn: #e74c3c; --primary-btn: #3498db; --logout-btn: #e67e22; --telegram-btn: #0088cc;
  --user-icon: #f1c40f; --pass-icon: #e74c3c; --expires-icon: #9b59b6; --port-icon: #3498db;
}
/* Default: Dark Theme */
[data-theme="dark"] {
  --bg: #121212; --fg: #f0f0f0; --card: #1e1e1e; --bd: #333; --header-bg: #1e1e1e;
  --input-text: #fff; --shadow: 0 4px 15px rgba(0,0,0,0.7); --table-header: #222;
  --table-hover: #2d2d2d;
}
/* Light Theme */
[data-theme="light"] {
  --bg: #f4f4f9; --fg: #1e1e1e; --card: #ffffff; --bd: #ddd; --header-bg: #e0e0e0;
  --input-text: #1e1e1e; --shadow: 0 4px 15px rgba(0,0,0,0.1); --table-header: #f0f0f0;
  --table-hover: #e9e9e9;
}

html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px;transition:background 0.3s, color 0.3s;}
.container{max-width:1400px;margin:auto;padding:10px}

@keyframes colorful-shift {
  0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius, 8px);box-shadow:var(--shadow);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--bd)}

.btn{padding:10px 18px;border-radius:var(--radius, 8px);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.3);display:flex;align-items:center;gap:8px;}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:#2980b9}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:#95a5a6;color:var(--fg);}.btn.secondary:hover{background:#7f8c8d}
.btn.toggle-theme{background:var(--bd);color:var(--fg);}.btn.toggle-theme:hover{background:#555}

.label-c1{color:var(--ok)}.label-c2{color:var(--unk)}.label-c3{color:var(--bad)}.label-c4{color:var(--expired)}.label-c5{color:var(--logout-btn)}.label-c6{color:var(--success)}

form.box{margin:25px 0;padding:25px;border-radius:var(--radius, 8px);background:var(--card);box-shadow:var(--shadow);}
h3{color:var(--fg);margin-top:0;}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius, 8px);box-sizing:border-box;background:var(--bg);color:var(--input-text);transition:border-color 0.3s;}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:none;color:var(--fg);cursor:pointer;border-radius:var(--radius, 8px) var(--radius, 8px) 0 0;transition:all 0.3s ease;}
.tab-btn.active{background:var(--primary-btn);color:white;}
.tab-content{display:none;min-height:300px;padding:15px 0;}
.tab-content.active{display:block;}

.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius, 8px);text-align:center;box-shadow:var(--shadow);border-left:5px solid var(--primary-btn);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;}
.stat-label{font-size:.9em;color:var(--bd);}

table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius, 8px);box-shadow:var(--shadow);overflow:hidden;}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);}
th:last-child,td:last-child{border-right:none;}
th{background:var(--table-header);font-weight:700;color:var(--fg);text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover{background:var(--table-hover)}

.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;text-shadow:1px 1px 2px rgba(0,0,0,0.2);box-shadow:0 1px 3px rgba(0,0,0,0.2);}
.status-ok{color:white;background:var(--ok)} /* ONLINE */
.status-bad{color:white;background:var(--bad)} /* OFFLINE / SUSPENDED */
.status-unk{color:white;background:var(--unk)} /* UNKNOWN */
.status-expired{color:white;background:var(--expired)} /* EXPIRED */
.pill-yellow{background:var(--unk)}.pill-red{background:var(--bad)}.pill-green{background:var(--ok)}
.pill-lightgreen{background:var(--success)}.pill-pink{background:var(--expired)}.pill-orange{background:var(--logout-btn)}

.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:1;background:rgba(142, 68, 173, 0.1);color:inherit} /* Light purple tint for expired */
tr.expired .muted{color:var(--bd);}
.center{display:flex;align-items:center;justify-content:center}
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;background:var(--card);box-shadow:var(--shadow);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;text-shadow:0 1px 3px rgba(0,0,0,0.3);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius, 8px);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius, 8px);background:var(--delete-btn);color:white;font-weight:700;}

.bulk-actions{margin:15px 0;display:flex;gap:10px;flex-wrap:wrap;}
.bulk-actions select,.bulk-actions input{padding:8px;border-radius:var(--radius, 8px);background:var(--bg);color:var(--fg);border:1px solid var(--bd);}

@media (max-width: 768px) {
  body{padding:10px}.container{padding:0}
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .row>div,.stats-grid{grid-template-columns:1fr;}
  .btn{width:100%;margin-bottom:5px;justify-content:center}
  table,thead,tbody,th,td,tr{display:block;}
  thead tr{position:absolute;top:-9999px;left:-9999px;}
  tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius, 8px);overflow:hidden;background:var(--card);}
  td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
  td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
  td:nth-of-type(1):before{content:"{{ T.user }}";}.mobile-header:nth-of-type(1):before{content:"{{ T.user }}";}
  td:nth-of-type(2):before{content:"{{ T.password }}";}.mobile-header:nth-of-type(2):before{content:"{{ T.password }}";}
  td:nth-of-type(3):before{content:"{{ T.expires }}";}.mobile-header:nth-of-type(3):before{content:"{{ T.expires }}";}
  td:nth-of-type(4):before{content:"{{ T.port }}";}.mobile-header:nth-of-type(4):before{content:"{{ T.port }}";}
  td:nth-of-type(5):before{content:"{{ T.bandwidth }}";}.mobile-header:nth-of-type(5):before{content:"{{ T.bandwidth }}";}
  td:nth-of-type(6):before{content:"{{ T.speed }}";}.mobile-header:nth-of-type(6):before{content:"{{ T.speed }}";}
  td:nth-of-type(7):before{content:"{{ T.status }}";}.mobile-header:nth-of-type(7):before{content:"{{ T.status }}";}
  td:nth-of-type(8):before{content:"{{ T.actions }}";}.mobile-header:nth-of-type(8):before{content:"{{ T.actions }}";}
  .delform{width:auto;}
}
</style>
</head>
<body>
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="Logo"></div>
    <h3 class="center">{{ T.login_title }}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label class="label-c1"><i class="fas fa-user icon icon-user"></i> {{ T.user }}</label>
      <input name="u" autofocus required>
      <label class="label-c2" style="margin-top:15px"><i class="fas fa-lock icon icon-pass"></i> {{ T.password }}</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i> {{ T.login_btn }}
      </button>
    </form>
    <div style="display:flex; justify-content:space-between; margin-top:15px;">
        <button class="btn toggle-theme" onclick="toggleTheme()" style="width:48%; box-shadow:none;">
            <i class="fas fa-{{ 'moon' if theme == 'dark' else 'sun' }}"></i> {{ theme.capitalize() }}
        </button>
        <a class="btn toggle-theme" href="/lang/{{ 'en' if lang == 'my' else 'my' }}" style="width:48%; box-shadow:none; justify-content:center;">
            <i class="fas fa-language"></i> {{ 'မြန်မာ' if lang == 'en' else 'English' }}
        </a>
    </div>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]" class="logo">
    <div>
      <h1><span class="colorful-title">{{ T.title }}</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ {{ T.subtitle }} ⊱✫⊰</span></div>
    </div>
  </div>
  <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;justify-content:flex-end;">
    <button class="btn toggle-theme" onclick="toggleTheme()" style="width:auto; box-shadow:none;">
        <i class="fas fa-{{ 'moon' if theme == 'dark' else 'sun' }}"></i> {{ theme.capitalize() }}
    </button>
    <a class="btn toggle-theme" href="/lang/{{ 'en' if lang == 'my' else 'my' }}" style="width:auto; box-shadow:none; justify-content:center;">
        <i class="fas fa-language"></i> {{ 'မြန်မာ' if lang == 'en' else 'English' }}
    </a>
    <a class="btn contact" href="https://t.me/nkka404" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i> {{ T.contact_btn }}
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i> {{ T.logout_btn }}
    </a>
  </div>
</header>

<!-- Stats Dashboard -->
<div class="stats-grid">
  <div class="stat-card" style="border-left-color:var(--info);">
    <i class="fas fa-users" style="font-size:2em;color:var(--info);"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">{{ T.total_users }}</div>
  </div>
  <div class="stat-card" style="border-left-color:var(--ok);">
    <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">{{ T.active_users }}</div>
  </div>
  <div class="stat-card" style="border-left-color:var(--delete-btn);">
    <i class="fas fa-database" style="font-size:2em;color:var(--delete-btn);"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{ T.bw_used }}</div>
  </div>
  <div class="stat-card" style="border-left-color:var(--unk);">
    <i class="fas fa-server" style="font-size:2em;color:var(--unk);"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{ T.server_load }}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab(event, 'users')">{{ T.user_mgmt }}</button>
    <button class="tab-btn" onclick="openTab(event, 'adduser')">{{ T.add_user }}</button>
    <button class="tab-btn" onclick="openTab(event, 'bulk')">{{ T.bulk_ops }}</button>
    <button class="tab-btn" onclick="openTab(event, 'reports')">{{ T.reports }}</button>
  </div>

  <!-- Add User Tab -->
  <div id="adduser" class="tab-content">
    <form method="post" action="/add" class="box">
      <h3 class="label-c6"><i class="fas fa-users-cog"></i> {{ T.add_user }}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label class="label-c1"><i class="fas fa-user icon icon-user"></i> {{ T.user }}</label><input name="user" placeholder="{{ T.user }}" required></div>
        <div><label class="label-c2"><i class="fas fa-lock icon icon-pass"></i> {{ T.password }}</label><input name="password" placeholder="{{ T.password }}" required></div>
        <div><label class="label-c3"><i class="fas fa-clock icon icon-expires"></i> {{ T.expires }}</label><input name="expires" placeholder="2026-01-01 or 30" value="30"></div>
        <div><label class="label-c4"><i class="fas fa-server icon icon-port"></i> {{ T.port }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label class="label-c5"><i class="fas fa-tachometer-alt"></i> {{ T.speed_limit_mb }}</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label class="label-c6"><i class="fas fa-database"></i> {{ T.bw_limit_gb }}</label><input name="bandwidth_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label class="label-c1"><i class="fas fa-plug"></i> {{ T.max_conn }}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label class="label-c2"><i class="fas fa-money-bill"></i> {{ T.plan_type }}</label>
          <select name="plan_type">
            <option value="free">Free</option>
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly" selected>Monthly</option>
            <option value="yearly">Yearly</option>
          </select>
        </div>
      </div>
      <button class="btn save" type="submit" style="margin-top:20px">
        <i class="fas fa-save"></i> {{ T.save_user }}
      </button>
    </form>
  </div>

  <!-- Bulk Operations Tab -->
  <div id="bulk" class="tab-content">
    <div class="box">
      <h3 class="label-c5"><i class="fas fa-cogs"></i> {{ T.bulk_ops }}</h3>
      <div class="bulk-actions">
        <select id="bulkAction">
          <option value="">{{ T.select_action }}</option>
          <option value="extend">{{ T.extend_7 }}</option>
          <option value="suspend">{{ T.suspend_users }}</option>
          <option value="activate"> {{ T.activate_users }}</option>
          <option value="delete">{{ T.delete_users }}</option>
        </select>
        <input type="text" id="bulkUsers" placeholder="{{ T.users_comma }}">
        <button class="btn secondary" onclick="executeBulkAction()">
          <i class="fas fa-play"></i> {{ T.execute }}
        </button>
      </div>
      <div style="margin-top:15px">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> {{ T.export }}
        </button>
        <!-- Import functionality would need a file upload handler -->
        <!-- <button class="btn secondary" onclick="importUsers()"> -->
        <!-- <i class="fas fa-upload"></i> {{ T.import }} -->
        <!-- </button> -->
      </div>
    </div>
  </div>

  <!-- Users Management Tab -->
  <div id="users" class="tab-content active">
    <div class="box">
      <h3 class="label-c1"><i class="fas fa-users"></i> {{ T.user_mgmt }}</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="{{ T.search }}" style="flex:1;">
        <button class="btn secondary" onclick="filterUsers()">
          <i class="fas fa-search"></i> {{ T.search }}
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th class="mobile-header"><i class="fas fa-user"></i> {{ T.user }}</th>
          <th class="mobile-header"><i class="fas fa-lock"></i> {{ T.password }}</th>
          <th class="mobile-header"><i class="fas fa-clock"></i> {{ T.expires }}</th>
          <th class="mobile-header"><i class="fas fa-server"></i> {{ T.port }}</th>
          <th class="mobile-header"><i class="fas fa-database"></i> {{ T.usage }}</th>
          <th class="mobile-header"><i class="fas fa-tachometer-alt"></i> {{ T.speed_limit }}</th>
          <th class="mobile-header"><i class="fas fa-chart-line"></i> {{ T.status }}</th>
          <th class="mobile-header"><i class="fas fa-cog"></i> {{ T.actions }}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.is_expired %}expired{% endif %}">
        <td style="color:var(--ok);"><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
        <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
        <td>
          {% if u.status == "Online" %}<span class="pill status-ok">{{ T.online }}</span>
          {% elif u.status == "Offline" %}<span class="pill status-bad">{{ T.offline }}</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">{{ T.expired }}</span>
          {% elif u.status == "suspended" %}<span class="pill status-bad">{{ T.suspended }}</span>
          {% else %}<span class="pill status-unk">{{ T.unknown }}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{ T.confirm_delete|format(u.user) }}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="{{ T.delete_btn }}" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn secondary" title="{{ T.edit_btn }}" style="padding:6px 12px;" onclick="editUser('{{u.user}}', '{{u.password}}', '{{ T.password }}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == "suspended" %}
          <form class="delform" method="post" action="/activate">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" title="{{ T.activate_users }}" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="{{ T.suspend_users }}" style="padding:6px 12px;">
              <i class="fas fa-pause"></i>
            </button>
          </form>
          {% endif %}
        </td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
  </div>

  <!-- Reports Tab -->
  <div id="reports" class="tab-content">
    <div class="box">
      <h3 class="label-c6"><i class="fas fa-chart-bar"></i> {{ T.reports }}</h3>
      <div class="row">
        <div><label>{{ T.from_date }}</label><input type="date" id="fromDate"></div>
        <div><label>{{ T.to_date }}</label><input type="date" id="toDate"></div>
        <div><label>{{ T.report_type }}</label>
          <select id="reportType">
            <option value="bandwidth">{{ T.bandwidth }} {{ T.usage }}</option>
            <option value="users">{{ T.user }} {{ T.status }}</option>
            <option value="revenue">Revenue</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">
            <i class="fas fa-chart-bar"></i> {{ T.generate_report }}
        </button></div>
      </div>
    </div>
    <div id="reportResults"></div>
  </div>
</div>

{% endif %}
</div>

<script>
// UI/UX Functions
document.addEventListener('DOMContentLoaded', () => {
    // Set initial theme/lang from cookies
    const theme = getCookie('theme') || 'dark';
    document.documentElement.setAttribute('data-theme', theme);

    // Initial tab load (for back button navigation)
    const urlParams = new URLSearchParams(window.location.search);
    const initialTab = urlParams.get('tab') || 'users';
    const initialTabBtn = document.querySelector(`.tab-btn[onclick*="${initialTab}"]`);
    if (initialTabBtn) {
        openTab(initialTabBtn, initialTab);
    } else {
        openTab(document.querySelector('.tab-btn'), 'users');
    }
});

function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
}

function setCookie(name, value, days) {
    let expires = "";
    if (days) {
        const date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + (value || "")  + expires + "; path=/";
}

function toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', newTheme);
    setCookie('theme', newTheme, 365);
    // Update button icon/text
    const btn = document.querySelector('.btn.toggle-theme i');
    if(btn) {
        btn.classList.remove(`fa-${currentTheme === 'dark' ? 'moon' : 'sun'}`);
        btn.classList.add(`fa-${newTheme === 'dark' ? 'moon' : 'sun'}`);
    }
}

function openTab(event, tabName) {
  // Handle case where event is the button element itself
  let targetBtn = event.currentTarget || event;
  
  document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  
  document.getElementById(tabName).classList.add('active');
  targetBtn.classList.add('active');
  
  // Optional: Update URL for persistence, without reloading
  history.replaceState(null, '', `?tab=${tabName}`);
}

function executeBulkAction() {
  const action = document.getElementById('bulkAction').value;
  const users = document.getElementById('bulkUsers').value;
  if (!action || !users) { alert('{{ T.select_action }}'); return; }
  
  fetch('/api/bulk', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u.length > 0)})
  }).then(r => r.json()).then(data => {
    alert(data.message); location.reload();
  }).catch(e => alert("Error: " + e));
}

function exportUsers() {
  window.open('/api/export/users', '_blank');
}

function filterUsers() {
  const search = document.getElementById('searchUser').value.toLowerCase();
  document.querySelectorAll('tbody tr').forEach(row => {
    const user = row.cells[0].textContent.toLowerCase();
    row.style.display = user.includes(search) ? '' : 'none';
  });
}

function editUser(username, currentPassword, passwordLabel) {
  const newPass = prompt(`Enter new ${passwordLabel} for ${username}`, currentPassword);
  if (newPass && newPass.trim() !== currentPassword) {
    fetch('/api/user/update', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({user: username, password: newPass.trim()})
    }).then(r => r.json()).then(data => {
      alert(data.message); location.reload();
    }).catch(e => alert("Error: " + e));
  }
}

function generateReport() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const type = document.getElementById('reportType').value;
  
  fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
    .then(r => r.json()).then(data => {
      document.getElementById('reportResults').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
    });
}
</script>
</body></html>"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

# --- Helpers ---
def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def read_json(path, default):
    try:
        with open(path,"r") as f: return json.load(f)
    except Exception:
        return default

def write_json_atomic(path, data):
    d=json.dumps(data, ensure_ascii=False, indent=2)
    dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
    try:
        with os.fdopen(fd,"w") as f: f.write(d)
        os.replace(tmp,path)
    finally:
        try: os.remove(tmp)
        except: pass

def get_T(lang_code):
    return type('T', (), LANG_MAP.get(lang_code, LANG_MAP[DEFAULT_LANG]))

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, bandwidth_used, speed_limit_up as speed_limit,
               concurrent_conn
        FROM users
        ORDER BY username ASC
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        # Check if user exists to decide on INSERT or UPDATE
        existing_user = db.execute('SELECT id FROM users WHERE username = ?', (user_data['user'],)).fetchone()
        
        if existing_user:
             db.execute('''
                UPDATE users SET 
                    password = ?, expires = ?, port = ?, bandwidth_limit = ?, 
                    speed_limit_up = ?, concurrent_conn = ?, updated_at = CURRENT_TIMESTAMP
                WHERE username = ?
            ''', (
                user_data['password'], user_data.get('expires'), 
                user_data.get('port'), user_data.get('bandwidth_limit', 0), 
                user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1), 
                user_data['user']
            ))
        else:
            db.execute('''
                INSERT INTO users (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                user_data['user'], user_data['password'], user_data.get('expires'),
                user_data.get('port'), 'active', user_data.get('bandwidth_limit', 0),
                user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
            ))
        
        # Add/Update billing record
        if user_data.get('plan_type'):
            expires = user_data.get('expires') or (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
            db.execute('''
                INSERT OR REPLACE INTO billing (username, plan_type, expires_at)
                VALUES (?, ?, ?)
            ''', (user_data['user'], user_data['plan_type'], expires))
            
        db.commit()
            
    finally:
        db.close()

def delete_user(username):
    db = get_db()
    try:
        db.execute('DELETE FROM users WHERE username = ?', (username,))
        db.execute('DELETE FROM billing WHERE username = ?', (username,))
        db.commit()
    finally:
        db.close()

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status = "active"').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        # Simple server load simulation based on active users (more realistic metrics would require system commands)
        server_load = min(100.0, (total_users * 0.5) + (active_users * 1.5))
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': f"{server_load:.1f}"
        }
    finally:
        db.close()

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

# Use conntrack to check for active connections on a specific port within the last 120 seconds
def has_recent_udp_activity(port):
    if not port: return False
    try:
        # Check conntrack for state=ESTABLISHED/UNREPLIED and relevant expiry time (e.g. within 120s)
        # We rely on the ZIVPN client keeping the connection alive or the conntrack entry remaining.
        out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                            shell=True, capture_output=True, text=True).stdout
        
        # Simple check: if we see any entry for the port, consider it active.
        return bool(out.strip())
        
    except Exception:
        return False

def sync_config_passwords(mode="mirror"):
    users=load_users()
    # Only include active users' passwords in the config
    users_pw=sorted({str(u["password"]) for u in users if u.get("password") and u.get("status", "active") == "active"})
    
    cfg=read_json(CONFIG_FILE,{})
    if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
    cfg["auth"]["mode"]="passwords"
    cfg["auth"]["config"]=users_pw
    cfg["listen"]=cfg.get("listen") or ":5667"
    cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
    cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
    cfg["obfs"]=cfg.get("obfs") or "zivpn"
    
    write_json_atomic(CONFIG_FILE,cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True, check=False)

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

# --- Routes ---
@app.before_request
def set_language_and_theme():
    # Set Language
    lang_code = request.cookies.get('lang', DEFAULT_LANG)
    if lang_code not in LANG_MAP:
        lang_code = DEFAULT_LANG
    session['lang'] = lang_code
    
    # Set Theme (only relevant if not logged in, otherwise handled in build_view)
    theme = request.cookies.get('theme', 'dark')
    session['theme'] = theme

@app.route("/lang/<lang_code>", methods=["GET"])
def set_lang(lang_code):
    resp = make_response(redirect(request.referrer or url_for('index')))
    if lang_code in LANG_MAP:
        resp.set_cookie('lang', lang_code, max_age=365 * 24 * 60 * 60)
    return resp

def build_view(msg="", err=""):
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    theme = request.cookies.get('theme', 'dark')
    
    if not require_login():
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T, lang=lang, theme=theme)
    
    users=load_users()
    listen_port=get_listen_port_from_config()
    stats = get_server_stats()
    
    view=[]
    today_date=datetime.date.today()
    
    for u in users:
        expires_str=u.get("expires","")
        is_expired=False
        
        if expires_str:
            try:
                expires_dt=datetime.datetime.strptime(expires_str, "%Y-%m-%d").date()
                if expires_dt < today_date:
                    is_expired=True
            except ValueError:
                # Invalid date format, treat as not expired for now
                pass
        
        # 1. Check DB status (suspended takes precedence)
        db_status = u.get('status', 'active')
        if db_status == 'suspended':
            status = 'suspended'
        elif is_expired:
            # 2. Check if expired (Expired takes precedence over Online/Offline)
            status = 'Expired'
        else:
            # 3. Check live activity
            port=str(u.get("port",""))
            check_port=port if port else listen_port
            if has_recent_udp_activity(check_port):
                status = "Online"
            else:
                status = "Offline"
                
        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":expires_str,
            "port":u.get("port",""),
            "status":status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": f"{u.get('bandwidth_used', 0) / 1024 / 1024 / 1024:.2f}",
            "speed_limit": u.get('speed_limit', 0),
            "is_expired": is_expired
        }))
    
    today=today_date.strftime("%Y-%m-%d")
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL, T=T, lang=lang, theme=theme,
                                 users=view, msg=msg, err=err, today=today, stats=stats)

@app.route("/login", methods=["GET","POST"])
def login():
    if not login_enabled(): return redirect(url_for('index'))
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    theme = request.cookies.get('theme', 'dark')
    
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('index'))
        else:
            session["auth"]=False
            session["login_err"]=T.login_err
            return redirect(url_for('login'))
            
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T, lang=lang, theme=theme)

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
    if not require_login(): return redirect(url_for('login'))
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    
    user = (request.form.get("user") or "").strip()
    password = (request.form.get("password") or "").strip()
    expires = (request.form.get("expires") or "").strip()
    port_in = (request.form.get("port") or "").strip()
    
    user_data = {
        'user': user,
        'password': password,
        'bandwidth_limit': int(request.form.get("bandwidth_limit") or 0),
        'speed_limit': int(request.form.get("speed_limit") or 0),
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1),
        'plan_type': (request.form.get("plan_type") or "").strip()
    }
    
    if not user or not password:
        return build_view(err=T.user_name_req)
    
    expires_date = None
    if expires:
        if expires.isdigit():
            expires_date = (datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")
        else:
            try:
                expires_date = datetime.strptime(expires,"%Y-%m-%d").strftime("%Y-%m-%d")
            except ValueError:
                return build_view(err=T.expires_err)
    user_data['expires'] = expires_date
    
    port_out = None
    if port_in:
        try:
            port_num = int(port_in)
            if not (6000 <= port_num <= 19999):
                return build_view(err=T.port_err)
            port_out = str(port_num)
        except ValueError:
             return build_view(err=T.port_err)
    
    if not port_out:
        # Auto assign port
        used_ports = {str(u.get('port', '')) for u in load_users() if u.get('port')}
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                port_out = str(p)
                break
    user_data['port'] = port_out
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=T.user_saved)

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=f"{T.user} လိုအပ်သည်")
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=f"{T.delete_btn}: {user}")

@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        db.commit()
        db.close()
        sync_config_passwords()
    return redirect(url_for('index'))

@app.route("/activate", methods=["POST"])
def activate_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "active", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        db.commit()
        db.close()
        sync_config_passwords()
    return redirect(url_for('index'))

# API Routes (Bulk, Export, Report, Update)
@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    
    data = request.get_json() or {}
    action = data.get('action')
    users = [u.strip() for u in data.get('users', []) if u.strip()]
    
    db = get_db()
    try:
        if action == 'extend':
            for user in users:
                db.execute('UPDATE users SET expires = date(expires, "+7 days"), updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        elif action == 'suspend':
            for user in users:
                db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        elif action == 'activate':
            for user in users:
                db.execute('UPDATE users SET status = "active", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        elif action == 'delete':
            for user in users:
                delete_user(user) # Use the helper for full cleanup
        else:
            return jsonify({"ok": False, "message": "Invalid action"}), 400
            
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": f"{T.execute} {action} completed for {len(users)} users"})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Status\n"
    for u in users:
        # Convert bandwidth used from bytes to GB for export
        bw_used_gb = f"{u.get('bandwidth_used', 0) / 1024 / 1024 / 1024:.2f}"
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{bw_used_gb},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{u.get('status','')}\n"
    
    response = make_response(csv_data)
    response.headers["Content-Disposition"] = "attachment; filename=users_export.csv"
    response.headers["Content-type"] = "text/csv"
    return response

@app.route("/api/reports")
def generate_reports():
    if not require_login(): return jsonify({"error": "Unauthorized"}), 401
    
    report_type = request.args.get('type', 'bandwidth')
    from_date = request.args.get('from') or '2000-01-01'
    to_date = request.args.get('to') or '2030-12-31'
    
    db = get_db()
    data = []
    try:
        if report_type == 'bandwidth':
            # Bandwidth usage grouped by user
            data = db.execute('''
                SELECT username, SUM(bytes_used) as total_bytes_used
                FROM bandwidth_logs
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
                ORDER BY total_bytes_used DESC
            ''', (from_date, to_date)).fetchall()
        elif report_type == 'users':
            # New users and status changes
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date
                UNION ALL
                SELECT strftime('%Y-%m-%d', updated_at) as date, status as status_change, COUNT(*) as count
                FROM users
                WHERE updated_at BETWEEN ? AND ? AND status IN ('active', 'suspended')
                GROUP BY date, status_change
                ORDER BY date DESC
            ''', (from_date, to_date, from_date, to_date)).fetchall()
        elif report_type == 'revenue':
             # Simple revenue report based on billing
             data = db.execute('''
                SELECT plan_type, COUNT(*) as subscriptions, SUM(amount) as total_revenue, currency
                FROM billing
                WHERE created_at BETWEEN ? AND ? AND payment_status = 'paid'
                GROUP BY plan_type, currency
            ''', (from_date, to_date)).fetchall()
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()
        
    return jsonify([dict(d) for d in data])

@app.route("/api/user/update", methods=["POST"])
def update_user():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    lang = session.get('lang', DEFAULT_LANG)
    T = get_T(lang)
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    
    if user and password:
        db = get_db()
        db.execute('UPDATE users SET password = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?', (password, user))
        db.commit()
        db.close()
        sync_config_passwords()
        return jsonify({"ok": True, "message": "User updated"})
    
    return jsonify({"ok": False, "err": "Invalid data"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (Minimal Changes) =====
say "${Y}🔌 API Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >"$API_PY" <<'PY'
from flask import Flask, jsonify, request
import sqlite3, datetime
from datetime import timedelta

app = Flask(__name__)
DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/api/v1/stats', methods=['GET'])
def get_stats():
    db = get_db()
    stats = db.execute('''
        SELECT 
            COUNT(*) as total_users,
            SUM(CASE WHEN status = "active" THEN 1 ELSE 0 END) as active_users,
            SUM(bandwidth_used) as total_bandwidth
        FROM users
    ''').fetchone()
    db.close()
    return jsonify(dict(stats))

@app.route('/api/v1/users', methods=['GET'])
def get_users():
    db = get_db()
    users = db.execute('SELECT username, status, expires, bandwidth_used FROM users').fetchall()
    db.close()
    return jsonify([dict(u) for u in users])

@app.route('/api/v1/user/<username>', methods=['GET'])
def get_user(username):
    db = get_db()
    user = db.execute('SELECT * FROM users WHERE username = ?', (username,)).fetchone()
    db.close()
    if user:
        return jsonify(dict(user))
    return jsonify({"error": "User not found"}), 404

@app.route('/api/v1/bandwidth/<username>', methods=['POST'])
def update_bandwidth(username):
    # This API should be protected/authenticated in a real-world scenario
    data = request.get_json()
    bytes_used = data.get('bytes_used', 0)
    
    if not isinstance(bytes_used, int) or bytes_used < 0:
        return jsonify({"error": "Invalid bytes_used value"}), 400
        
    db = get_db()
    try:
        # 1. Update total bandwidth used on the user record
        db.execute('''
            UPDATE users 
            SET bandwidth_used = bandwidth_used + ?, updated_at = CURRENT_TIMESTAMP 
            WHERE username = ?
        ''', (bytes_used, username))
        
        # 2. Log bandwidth usage (for reporting)
        db.execute('''
            INSERT INTO bandwidth_logs (username, bytes_used) 
            VALUES (?, ?)
        ''', (username, bytes_used))
        
        # 3. Check for bandwidth limit and auto-suspend if exceeded
        user_check = db.execute('SELECT bandwidth_limit, bandwidth_used FROM users WHERE username = ?', (username,)).fetchone()
        if user_check and user_check['bandwidth_limit'] > 0 and user_check['bandwidth_used'] >= user_check['bandwidth_limit']:
            db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (username,))
            
        db.commit()
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()
        
    return jsonify({"message": "Bandwidth updated"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Telegram Bot (Myanmar Language) =====
say "${Y}🤖 Telegram Bot Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >"$BOT_PY" <<'PY'
import telegram
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import sqlite3, logging, os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATABASE_PATH = "/etc/zivpn/zivpn.db"
# NOTE: Set your actual bot token in the web.env or replace this placeholder
BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '8079105459:AAFNww6keJvnGJi4DpAHZGESBcL9ytFxqA4') 

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def start(update, context):
    update.message.reply_text(
        '🤖 ZIVPN Bot မှ ကြိုဆိုပါတယ်!\n\n'
        'အသုံးပြုနိုင်သော Command များ:\n'
        '/stats - ဆာဗာ စာရင်းအင်းများ\n'
        '/users - အသုံးပြုသူစာရင်း (အများဆုံး ၂၀)\n'
        '/myinfo <အသုံးပြုသူအမည်> - သုံးစွဲသူအချက်အလက်\n'
        '/help - အကူအညီ'
    )

def get_stats(update, context):
    db = get_db()
    stats = db.execute('''
        SELECT 
            COUNT(*) as total_users,
            SUM(CASE WHEN status = "active" THEN 1 ELSE 0 END) as active_users,
            SUM(bandwidth_used) as total_bandwidth
        FROM users
    ''').fetchone()
    db.close()
    
    total_bw_gb = stats['total_bandwidth'] / 1024 / 1024 / 1024 if stats['total_bandwidth'] else 0
    
    message = (
        f"📊 ဆာဗာ စာရင်းအင်းများ:\n"
        f"• စုစုပေါင်းအသုံးပြုသူ: {stats['total_users']}\n"
        f"• အသုံးပြုနေသူ: {stats['active_users']}\n"
        f"• သုံးပြီးဒေတာ: {total_bw_gb:.2f} GB"
    )
    update.message.reply_text(message)

def get_users(update, context):
    db = get_db()
    users = db.execute('SELECT username, status, expires FROM users LIMIT 20').fetchall()
    db.close()
    
    if not users:
        update.message.reply_text("အသုံးပြုသူ မတွေ့ပါ။")
        return
    
    message = "👥 အသုံးပြုသူ စာရင်း (ထိပ်ဆုံး ၂၀):\n"
    for user in users:
        message += f"• {user['username']} - အခြေအနေ: {user['status']} - သက်တမ်းကုန်ဆုံး: {user['expires'] or 'မရှိ'}\n"
    
    update.message.reply_text(message)

def get_user_info(update, context):
    if not context.args:
        update.message.reply_text("အသုံးပြုပုံ: /myinfo <အသုံးပြုသူအမည်>")
        return
    
    username = context.args[0]
    db = get_db()
    user = db.execute('''
        SELECT username, status, expires, bandwidth_used, bandwidth_limit, 
               speed_limit_up, concurrent_conn
        FROM users WHERE username = ?
    ''', (username,)).fetchone()
    db.close()
    
    if not user:
        update.message.reply_text(f"အသုံးပြုသူ '{username}' ကို မတွေ့ပါ။")
        return
    
    bw_used_gb = user['bandwidth_used'] / 1024 / 1024 / 1024 if user['bandwidth_used'] else 0
    
    message = (
        f"👤 အသုံးပြုသူ: {user['username']}\n"
        f"📊 အခြေအနေ: {user['status']}\n"
        f"⏰ သက်တမ်းကုန်ဆုံး: {user['expires'] or 'မရှိ'}\n"
        f"📦 ဒေတာပမာဏ: {bw_used_gb:.2f} GB / {user['bandwidth_limit']} GB\n"
        f"⚡ အမြန်နှုန်း ကန့်သတ်ချက်: {user['speed_limit_up']} MB/s\n"
        f"🔗 အများဆုံး ချိတ်ဆက်မှု: {user['concurrent_conn']}"
    )
    update.message.reply_text(message)

def main():
    if BOT_TOKEN == '8079105459:AAFNww6keJvnGJi4DpAHZGESBcL9ytFxqA4':
        logger.warning("TELEGRAM_BOT_TOKEN is using a placeholder. Please set it up in /etc/zivpn/web.env and restart zivpn-bot.service.")
    
    try:
        updater = Updater(BOT_TOKEN, use_context=True)
        dp = updater.dispatcher
        
        dp.add_handler(CommandHandler("start", start))
        dp.add_handler(CommandHandler("stats", get_stats))
        dp.add_handler(CommandHandler("users", get_users))
        dp.add_handler(CommandHandler("myinfo", get_user_info))
        
        logger.info("Starting Telegram Bot polling...")
        updater.start_polling()
        updater.idle()
    except telegram.error.InvalidToken:
        logger.error("Invalid Telegram Bot Token. Bot service failed to start.")
    except Exception as e:
        logger.error(f"Telegram Bot error: {e}")

if __name__ == '__main__':
    main()
PY

# ===== Backup & Cleanup Script (New/Updated) =====
say "${Y}💾 Backup & Cleanup System ထည့်သွင်းနေပါတယ်...${Z}"
cat >"$CLEANUP_PY" <<'PY'
import sqlite3, shutil, datetime, os, gzip, logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BACKUP_DIR = "/etc/zivpn/backups"
DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def backup_database():
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"zivpn_backup_{timestamp}.db.gz")
    
    try:
        # Backup database
        with open(DATABASE_PATH, 'rb') as f_in:
            with gzip.open(backup_file, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)
        logger.info(f"Backup created: {backup_file}")
    except Exception as e:
        logger.error(f"Error during backup: {e}")
        return

    # Cleanup old backups (keep last 7 days)
    now = datetime.datetime.now()
    for file in os.listdir(BACKUP_DIR):
        file_path = os.path.join(BACKUP_DIR, file)
        if os.path.isfile(file_path) and file.endswith(".db.gz"):
            try:
                # Extract date from filename: zivpn_backup_YYYYMMDD_HHMMSS.db.gz
                date_part = file.split('_')[2]
                file_dt = datetime.datetime.strptime(date_part, "%Y%m%d")
                if (now - file_dt).days > 7:
                    os.remove(file_path)
                    logger.info(f"Cleaned up old backup: {file}")
            except Exception as e:
                 logger.warning(f"Could not process/delete file {file}: {e}")

def auto_suspend_expired_users():
    """Checks for users whose expiration date has passed and sets their status to 'suspended'."""
    db = get_db()
    today = datetime.date.today().strftime("%Y-%m-%d")
    
    try:
        # Select users whose 'expires' date is today or earlier AND status is not already 'suspended'
        expired_users = db.execute('''
            SELECT username FROM users
            WHERE expires IS NOT NULL AND expires <= ? AND status != 'suspended'
        ''', (today,)).fetchall()
        
        if expired_users:
            usernames = [u['username'] for u in expired_users]
            # Update their status to 'suspended'
            db.execute(f'''
                UPDATE users SET status = 'suspended', updated_at = CURRENT_TIMESTAMP
                WHERE username IN ({','.join(['?'] * len(usernames))})
            ''', usernames)
            db.commit()
            logger.info(f"Auto-suspended {len(usernames)} expired users: {', '.join(usernames)}")
        else:
            logger.info("No users require auto-suspension.")
            
    except Exception as e:
        logger.error(f"Error during auto-suspension: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == '__main__':
    logger.info("Starting ZIVPN cleanup and backup job...")
    backup_database()
    auto_suspend_expired_users()
    logger.info("ZIVPN cleanup and backup job finished.")
PY

# ===== systemd Services (Updated for Cleanup Timer) =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service (Keep original)
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Web Panel Service (Keep original)
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# API Service (Keep original)
cat >/etc/systemd/system/zivpn-api.service <<'EOF'
[Unit]
Description=ZIVPN API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/api.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Telegram Bot Service (New)
cat >/etc/systemd/system/zivpn-bot.service <<'EOF'
[Unit]
Description=ZIVPN Telegram Bot
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Backup/Cleanup Service (Updated)
cat >/etc/systemd/system/zivpn-cleanup.service <<'EOF'
[Unit]
Description=ZIVPN Daily Cleanup (Backup & Auto-Suspend)
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/cleanup.py

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-cleanup.timer <<'EOF'
[Unit]
Description=Daily ZIVPN Cleanup/Backup Timer
Requires=zivpn-cleanup.service

[Timer]
# Run every day at 03:00 AM
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ===== Networking Setup (Keep original logic) =====
echo -e "${Y}🌐 Network Configuration ပြုလုပ်နေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# DNAT Rules
iptables -t nat -F
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# UFW Rules
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true # For per-user ports
ufw allow 8080/tcp >/dev/null 2>&1 || true # Web Panel
ufw allow 8081/tcp >/dev/null 2>&1 || true # API
ufw --force enable >/dev/null 2>&1 || true

# ===== Final Setup =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-bot.service
systemctl enable --now zivpn-cleanup.timer

# Initial cleanup and backup run
python3 "$CLEANUP_PY"

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "${C}🤖 Telegram Bot:${Z} ${Y}zivpn-bot.service (check token in ${ENVF})${Z}"
echo -e "\n${M}📋 Services:${Z}"
echo -e "  ${Y}systemctl status zivpn${Z}          - VPN Server"
echo -e "  ${Y}systemctl status zivpn-web${Z}      - Web Panel"
echo -e "  ${Y}systemctl status zivpn-cleanup${Z} - Daily Cleanup"
echo -e "  ${Y}systemctl list-timers${Z}          - Backup/Cleanup Timers"
echo -e "\n${G}🎯 Enhanced Features Enabled:${Z}"
echo -e "  ✓ Improved UI/UX with Dark/Light Mode"
echo -e "  ✓ English / မြန်မာ Language Support"
echo -e "  ✓ Accurate Online/Offline Status (via conntrack)"
echo -e "  ✓ Auto-Suspend for Expired Users (Daily)"
echo -e "  ✓ Bandwidth Limit Auto-Suspension (via API)"
echo -e "$LINE"
