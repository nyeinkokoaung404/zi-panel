#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION 2.0
# Author: 4 0 4 \ 2.0 [🇲🇲] - Enhanced by Gemini
# Features: Complete Enterprise Management System with Bandwidth Control, Billing, Multi-Server, API, Auto-Suspend, UI/UX, Dark/Light Mode, Language Support (EN/MY).
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION 2.0 ${Z}\n$LINE"

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
apt-get install -y curl ufw jq python3 python3-flask python3-pip python3-venv iproute2 conntrack ca-certificates sqlite3 >/dev/null || \
{
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask python3-pip iproute2 conntrack ca-certificates sqlite3 >/dev/null
}

# Additional Python packages
pip3 install requests python-dateutil python-telegram-bot >/dev/null 2>&1 || true
apt_guard_end

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
systemctl stop zivpn-bot.service 2>/dev/null || true
systemctl stop zivpn-cleanup.service 2>/dev/null || true # Stop new service if exists

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
DB="/etc/zivpn/zivpn.db"
ENVF="/etc/zivpn/web.env"
BACKUP_DIR="/etc/zivpn/backups"
mkdir -p /etc/zivpn "$BACKUP_DIR"

# ===== Download ZIVPN binary =====
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

# ===== Enhanced Database Setup =====
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

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KHAINGUDP/OU=Net/CN=khaingudp" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin =====
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

# ===== Ask initial VPN passwords =====
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

# ===== Update config.json =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" --arg ip "$SERVER_IP" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn") |
    .server = $ip
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== Enhanced Web Panel (web.py) =====
say "${Y}🖥️ Enhanced Web Panel ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Translations ---
LANGUAGES = {
    'en': {
        'title': 'Channel 404 ZIVPN Enterprise Panel',
        'subtitle': 'Enterprise Management System',
        'login': 'Login',
        'login_err': 'Invalid username or password',
        'logout': 'Logout',
        'contact': 'Contact',
        'total_users': 'Total Users',
        'active_users': 'Active Users',
        'bandwidth_used': 'Bandwidth Used',
        'server_load': 'Server Load',
        'user_management': 'User Management',
        'add_new_user': 'Add New User',
        'bulk_operations': 'Bulk Operations',
        'reports': 'Reports',
        'save_user': 'Save User',
        'user_label': 'User',
        'password_label': 'Password',
        'expires_label': 'Expires',
        'port_label': 'Port',
        'speed_limit_label': 'Speed Limit (MB/s)',
        'bandwidth_limit_label': 'Bandwidth Limit (GB)',
        'max_conn_label': 'Max Connections',
        'plan_type_label': 'Plan Type',
        'unlimited': 'unlimited',
        'search_users': 'Search users...',
        'online': 'ONLINE',
        'offline': 'OFFLINE',
        'expired': 'EXPIRED',
        'suspended': 'SUSPENDED',
        'unknown': 'UNKNOWN',
        'delete_confirm': 'Are you sure you want to delete {}?',
        'user_pass_required': 'User and Password are required',
        'expires_invalid': 'Expires format is invalid',
        'port_range_invalid': 'Port range must be 6000-19999',
        'deleted_msg': 'Deleted: {}',
        'saved_msg': 'User saved successfully',
        'select_action': 'Select Action',
        'extend_expiry': 'Extend Expiry (+7 days)',
        'suspend_users': 'Suspend Users',
        'activate_users': 'Activate Users',
        'delete_users': 'Delete Users',
        'usernames_placeholder': 'Usernames comma separated (user1,user2)',
        'execute': 'Execute',
        'export_csv': 'Export Users CSV',
        'import_users': 'Import Users',
        'from_date': 'From Date',
        'to_date': 'To Date',
        'report_type': 'Report Type',
        'generate_report': 'Generate Report',
        'bandwidth_usage': 'Bandwidth Usage',
        'user_activity': 'User Activity',
        'revenue': 'Revenue',
        'actions': 'Actions',
        'update_user': 'Update User',
        'user_updated': 'User updated',
    },
    'my': {
        'title': 'ချန်နယ် 404 ZIVPN Enterprise Panel',
        'subtitle': 'လုပ်ငန်းသုံး စီမံခန့်ခွဲမှုစနစ်',
        'login': 'ဝင်ရောက်ပါ',
        'login_err': 'အသုံးပြုသူအမည် သို့မဟုတ် လျှို့ဝှက်နံပါတ် မမှန်ပါ',
        'logout': 'ထွက်ရန်',
        'contact': 'ဆက်သွယ်ရန်',
        'total_users': 'အသုံးပြုသူ စုစုပေါင်း',
        'active_users': 'အွန်လိုင်းရှိသူ',
        'bandwidth_used': 'သုံးစွဲပြီး Bandwidth',
        'server_load': 'ဆာဗာ ဝန်ပမာဏ',
        'user_management': 'အသုံးပြုသူ စီမံခန့်ခွဲမှု',
        'add_new_user': 'အသုံးပြုသူ အသစ်ထည့်ပါ',
        'bulk_operations': 'အစုလိုက် လုပ်ဆောင်ချက်များ',
        'reports': 'အစီရင်ခံစာများ',
        'save_user': 'အသုံးပြုသူ သိမ်းဆည်းမည်',
        'user_label': 'အသုံးပြုသူ',
        'password_label': 'လျှို့ဝှက်နံပါတ်',
        'expires_label': 'သက်တမ်းကုန်ဆုံး',
        'port_label': 'Port',
        'speed_limit_label': 'အမြန်နှုန်း ကန့်သတ် (MB/s)',
        'bandwidth_limit_label': 'Bandwidth ကန့်သတ် (GB)',
        'max_conn_label': 'ချိတ်ဆက်မှု အများဆုံး',
        'plan_type_label': 'အစီအစဉ် အမျိုးအစား',
        'unlimited': 'ကန့်သတ်မထားပါ',
        'search_users': 'အသုံးပြုသူ ရှာဖွေပါ...',
        'online': 'အွန်လိုင်း',
        'offline': 'အော့ဖ်လိုင်း',
        'expired': 'သက်တမ်းကုန်',
        'suspended': 'ယာယီရပ်ဆိုင်း',
        'unknown': 'မသိရှိရ',
        'delete_confirm': '{} ကို ဖျက်မလား?',
        'user_pass_required': 'အသုံးပြုသူအမည်နှင့် လျှို့ဝှက်နံပါတ် လိုအပ်သည်',
        'expires_invalid': 'သက်တမ်းကုန်ဆုံးရက် format မမှန်ပါ',
        'port_range_invalid': 'Port အကွာအဝေး 6000-19999 အတွင်း ဖြစ်ရမည်',
        'deleted_msg': 'ဖျက်လိုက်ပါပြီ: {}',
        'saved_msg': 'အသုံးပြုသူကို အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ',
        'select_action': 'လုပ်ဆောင်ချက် ရွေးချယ်ပါ',
        'extend_expiry': 'သက်တမ်းတိုးမည် (+၇ ရက်)',
        'suspend_users': 'ယာယီရပ်ဆိုင်းမည်',
        'activate_users': 'ပြန်လည်စတင်မည်',
        'delete_users': 'အပြီးတိုင်ဖျက်မည်',
        'usernames_placeholder': 'အသုံးပြုသူအမည်များ ကော်မာခြားပြီး ထည့်ပါ (user1,user2)',
        'execute': 'လုပ်ဆောင်မည်',
        'export_csv': 'အသုံးပြုသူစာရင်း CSV ထုတ်ယူမည်',
        'import_users': 'အသုံးပြုသူစာရင်း ထည့်သွင်းမည်',
        'from_date': 'မှစတင်ရက်',
        'to_date': 'အထိရက်',
        'report_type': 'အစီရင်ခံစာ အမျိုးအစား',
        'generate_report': 'အစီရင်ခံစာ ထုတ်ယူမည်',
        'bandwidth_usage': 'Bandwidth သုံးစွဲမှု',
        'user_activity': 'အသုံးပြုသူ လှုပ်ရှားမှု',
        'revenue': 'ဝင်ငွေ',
        'actions': 'လုပ်ဆောင်ချက်များ',
        'update_user': 'အသုံးပြုသူ ပြင်ဆင်ရန်',
        'user_updated': 'အသုံးပြုသူကို ပြင်ဆင်ပြီးပါပြီ',
    }
}

HTML = """<!doctype html>
<html lang="{{ lang }}"><head><meta charset="utf-8">
<title>{{ t.title }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{
  --bg-dark: #121212; --fg-dark: #e0e0e0; --card-dark: #1e1e1e; --bd-dark: #333;
  --header-bg-dark: #1e1e1e; --ok-dark: #2ecc71; --bad-dark: #e74c3c; --unknown-dark: #f39c12;
  --expired-dark: #9b59b6; --info-dark: #3498db; --success-dark: #1abc9c; --delete-btn-dark: #e74c3c;
  --primary-btn-dark: #3498db; --logout-btn-dark: #e67e22; --telegram-btn-dark: #0088cc;
  --input-text-dark: #fff; --shadow-dark: 0 4px 15px rgba(0,0,0,0.7); --radius: 8px;
  --user-icon-dark: #f1c40f; --pass-icon-dark: #e74c3c; --expires-icon-dark: #9b59b6; --port-icon-dark: #3498db;

  --bg-light: #f4f4f4; --fg-light: #333; --card-light: #ffffff; --bd-light: #ccc;
  --header-bg-light: #ffffff; --ok-light: #27ae60; --bad-light: #c0392b; --unknown-light: #d35400;
  --expired-light: #8e44ad; --info-light: #3498db; --success-light: #16a085; --delete-btn-light: #c0392b;
  --primary-btn-light: #3498db; --logout-btn-light: #f39c12; --telegram-btn-light: #0088cc;
  --input-text-light: #333; --shadow-light: 0 2px 10px rgba(0,0,0,0.1);

  /* Default to Dark Mode */
  --bg: var(--bg-dark); --fg: var(--fg-dark); --card: var(--card-dark); --bd: var(--bd-dark);
  --header-bg: var(--header-bg-dark); --ok: var(--ok-dark); --bad: var(--bad-dark); --unknown: var(--unknown-dark);
  --expired: var(--expired-dark); --info: var(--info-dark); --success: var(--success-dark); --delete-btn: var(--delete-btn-dark);
  --primary-btn: var(--primary-btn-dark); --logout-btn: var(--logout-btn-dark); --telegram-btn: var(--telegram-btn-dark);
  --input-text: var(--input-text-dark); --shadow: var(--shadow-dark);
  --user-icon: var(--user-icon-dark); --pass-icon: var(--pass-icon-dark); --expires-icon: var(--expires-icon-dark); --port-icon: var(--port-icon-dark);
}
.light-mode {
  --bg: var(--bg-light); --fg: var(--fg-light); --card: var(--card-light); --bd: var(--bd-light);
  --header-bg: var(--header-bg-light); --ok: var(--ok-light); --bad: var(--bad-light); --unknown: var(--unknown-light);
  --expired: var(--expired-light); --info: var(--info-light); --success: var(--success-light); --delete-btn: var(--delete-btn-light);
  --primary-btn: var(--primary-btn-light); --logout-btn: var(--logout-btn-light); --telegram-btn: var(--telegram-btn-light);
  --input-text: var(--input-text-light); --shadow: var(--shadow-light);
  --user-icon: var(--user-icon-dark); --pass-icon: var(--pass-icon-dark); --expires-icon: var(--expires-icon-dark); --port-icon: var(--port-icon-dark);
}
html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px;transition:background 0.3s, color 0.3s}
.container{max-width:1400px;margin:auto;padding:10px}

@keyframes colorful-shift {
  0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius);box-shadow:var(--shadow);border:1px solid var(--bd);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}
.admin-name{color:var(--user-icon);font-weight:700}

.controls{display:flex;gap:10px;align-items:center}
.theme-toggle{cursor:pointer;font-size:1.5em;padding:5px;border-radius:50%;transition:transform 0.2s}
.theme-toggle:hover{transform:scale(1.1)}
.lang-select{padding:6px 10px;border-radius:var(--radius);border:1px solid var(--bd);background:var(--bg);color:var(--fg);cursor:pointer;}

.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.3);display:inline-flex;align-items:center;gap:8px;}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:var(--info)}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:#95a5a6}.btn.secondary:hover{background:#7f8c8d}

.icon{margin-right:5px;font-size:1em;line-height:1;}
.label-c1{color:var(--ok)}.label-c2{color:var(--unknown)}.label-c3{color:var(--bad)}
.label-c4{color:var(--expired)}.label-c5{color:var(--logout-btn)}.label-c6{color:var(--success)}

form.box{margin:25px 0;padding:25px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);border:1px solid var(--bd);}
h3{color:var(--fg);margin-top:0;border-bottom:2px solid var(--bd);padding-bottom:10px;}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);box-sizing:border-box;background:var(--bg);color:var(--input-text);transition:border-color 0.3s;}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:1px solid var(--bd);color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;border-bottom:none;}
.tab-btn.active{background:var(--primary-btn);color:white;border-color:var(--primary-btn);box-shadow:var(--shadow);}
.tab-content{display:none;background:var(--card);padding:20px;border-radius:0 var(--radius) var(--radius) var(--radius);box-shadow:var(--shadow);border:1px solid var(--bd);margin-top:-1px;}
.tab-content.active{display:block;}

.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);border:1px solid var(--bd);transition:transform 0.3s;}
.stat-card:hover{transform:translateY(-5px);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;color:var(--info);}
.stat-label{font-size:.9em;color:var(--fg);}

table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;border:1px solid var(--bd);}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);transition:background 0.3s;}
th:last-child,td:last-child{border-right:none;}
th{background:#1e1e1e;font-weight:700;color:white;text-transform:uppercase;background:var(--header-bg);}
tr:last-child td{border-bottom:none}
tr:hover{background:#3a3a3a}

.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;text-shadow:1px 1px 2px rgba(0,0,0,0.5);box-shadow:0 2px 4px rgba(0,0,0,0.2);}
.status-ok{color:white;background:var(--ok)}.status-bad{color:white;background:var(--bad)}
.status-unk{color:white;background:var(--unknown)}.status-expired{color:white;background:var(--expired)}
.pill-yellow{background:#f1c40f}.pill-red{background:#e74c3c}.pill-green{background:#2ecc71}
.pill-lightgreen{background:#1abc9c}.pill-pink{background:#f78da7}.pill-orange{background:#e67e22}

.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:var(--expired);color:white}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;background:var(--card);box-shadow:var(--shadow);border:1px solid var(--bd);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;text-shadow:0 1px 3px rgba(0,0,0,0.5);color:var(--primary-btn)}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}

.bulk-actions{margin:15px 0;display:flex;gap:10px;flex-wrap:wrap;}
.bulk-actions select,.bulk-actions input{padding:10px;border-radius:var(--radius);background:var(--bg);color:var(--input-text);border:1px solid var(--bd);}

@media (max-width: 768px) {
  body{padding:10px}.container{padding:0}
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .controls{justify-content:space-between;width:100%;}
  .row>div,.stats-grid{grid-template-columns:1fr;}
  .btn{width:100%;margin-bottom:5px;justify-content:center}
  table,thead,tbody,th,td,tr{display:block;}
  thead tr{position:absolute;top:-9999px;left:-9999px;}
  tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
  td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;white-space:normal !important;}
  td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
  td:nth-of-type(1):before{content:"{{ t.user_label }}";}td:nth-of-type(2):before{content:"{{ t.password_label }}";}
  td:nth-of-type(3):before{content:"{{ t.expires_label }}";}td:nth-of-type(4):before{content:"{{ t.port_label }}";}
  td:nth-of-type(5):before{content:"{{ t.bandwidth_limit_label }}";}td:nth-of-type(6):before{content:"{{ t.speed_limit_label }}";}
  td:nth-of-type(7):before{content:"{{ t.active_users }}";}td:nth-of-type(8):before{content:"{{ t.actions }}";}
  .delform{display:block;width:100%;margin-bottom:5px;}tr.expired td{background:var(--expired);}
}
</style>
</head>
<body class="{{ 'light-mode' if session.get('theme') == 'light' else 'dark-mode' }}">
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="4 0 4 \ 2.0"></div>
    <h3 class="center">ZIVPN Panel {{ t.login }}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label class="label-c1"><i class="fas fa-user icon"></i>{{ t.user_label }}</label>
      <input name="u" autofocus required>
      <label class="label-c2" style="margin-top:15px"><i class="fas fa-lock icon"></i>{{ t.password_label }}</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i>{{ t.login }}
      </button>
    </form>
    <div class="controls" style="margin-top:20px;justify-content:flex-start;">
      <span class="theme-toggle" onclick="toggleTheme()">
        <i id="theme-icon" class="fas fa-moon"></i>
      </span>
      <select class="lang-select" onchange="changeLang(this.value)">
        <option value="en" {% if lang == 'en' %}selected{% endif %}>English</option>
        <option value="my" {% if lang == 'my' %}selected{% endif %}>မြန်မာ</option>
      </select>
    </div>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]" class="logo">
    <div>
      <h1><span class="colorful-title">Channel 404 ZIVPN Enterprise</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ {{ t.subtitle }} ⊱✫⊰</span></div>
    </div>
  </div>
  <div class="controls">
    <span class="theme-toggle" onclick="toggleTheme()">
      <i id="theme-icon" class="fas {% if session.get('theme') == 'light' %}fa-sun{% else %}fa-moon{% endif %}"></i>
    </span>
    <select class="lang-select" onchange="changeLang(this.value)">
      <option value="en" {% if lang == 'en' %}selected{% endif %}>English</option>
      <option value="my" {% if lang == 'my' %}selected{% endif %}>မြန်မာ</option>
    </select>
    <a class="btn contact" href="https://t.me/nkka404" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>{{ t.contact }}
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>{{ t.logout }}
    </a>
  </div>
</header>

<!-- Stats Dashboard -->
<div class="stats-grid">
  <div class="stat-card">
    <i class="fas fa-users" style="font-size:2em;color:var(--info);"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">{{ t.total_users }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">{{ t.active_users }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:var(--delete-btn);"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{ t.bandwidth_used }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:var(--unknown);"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{ t.server_load }}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab(event, 'users')">{{ t.user_management }}</button>
    <button class="tab-btn" onclick="openTab(event, 'adduser')">{{ t.add_new_user }}</button>
    <button class="tab-btn" onclick="openTab(event, 'bulk')">{{ t.bulk_operations }}</button>
    <button class="tab-btn" onclick="openTab(event, 'reports')">{{ t.reports }}</button>
  </div>

  <!-- Add User Tab -->
  <div id="adduser" class="tab-content">
    <form method="post" action="/add" class="box" style="box-shadow:none;border:none;padding:0;margin:0;">
      <h3 class="label-c6"><i class="fas fa-users-cog"></i> {{ t.add_new_user }}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label class="label-c1"><i class="fas fa-user icon"></i> {{ t.user_label }}</label><input name="user" placeholder="{{ t.user_label }}" required></div>
        <div><label class="label-c2"><i class="fas fa-lock icon"></i> {{ t.password_label }}</label><input name="password" placeholder="{{ t.password_label }}" required></div>
        <div><label class="label-c3"><i class="fas fa-clock icon"></i> {{ t.expires_label }}</label><input name="expires" placeholder="2026-01-01 or 30"></div>
        <div><label class="label-c4"><i class="fas fa-server icon"></i> {{ t.port_label }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label class="label-c5"><i class="fas fa-tachometer-alt"></i> {{ t.speed_limit_label }}</label><input name="speed_limit" placeholder="0 = {{ t.unlimited }}" type="number"></div>
        <div><label class="label-c6"><i class="fas fa-database"></i> {{ t.bandwidth_limit_label }}</label><input name="bandwidth_limit" placeholder="0 = {{ t.unlimited }}" type="number"></div>
        <div><label class="label-c1"><i class="fas fa-plug"></i> {{ t.max_conn_label }}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label class="label-c2"><i class="fas fa-money-bill"></i> {{ t.plan_type_label }}</label>
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
        <i class="fas fa-save"></i> {{ t.save_user }}
      </button>
    </form>
  </div>

  <!-- Bulk Operations Tab -->
  <div id="bulk" class="tab-content">
    <div class="box" style="box-shadow:none;border:none;padding:0;margin:0;">
      <h3 class="label-c5"><i class="fas fa-cogs"></i> {{ t.bulk_operations }}</h3>
      <div class="bulk-actions">
        <select id="bulkAction">
          <option value="">{{ t.select_action }}</option>
          <option value="extend">{{ t.extend_expiry }}</option>
          <option value="suspend">{{ t.suspend_users }}</option>
          <option value="activate">{{ t.activate_users }}</option>
          <option value="delete">{{ t.delete_users }}</option>
        </select>
        <input type="text" id="bulkUsers" placeholder="{{ t.usernames_placeholder }}" style="flex:2;">
        <button class="btn secondary" onclick="executeBulkAction()">
          <i class="fas fa-play"></i> {{ t.execute }}
        </button>
      </div>
      <div style="margin-top:25px">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> {{ t.export_csv }}
        </button>
        <button class="btn secondary" onclick="importUsers()">
          <i class="fas fa-upload"></i> {{ t.import_users }}
        </button>
      </div>
    </div>
  </div>

  <!-- Users Management Tab -->
  <div id="users" class="tab-content active">
    <div class="box" style="box-shadow:none;border:none;padding:0;margin:0;">
      <h3 class="label-c1"><i class="fas fa-users"></i> {{ t.user_management }}</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="{{ t.search_users }}" style="flex:1;">
        <button class="btn secondary" onclick="filterUsers()">
          <i class="fas fa-search"></i>
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> {{ t.user_label }}</th>
          <th><i class="fas fa-lock"></i> {{ t.password_label }}</th>
          <th><i class="fas fa-clock"></i> {{ t.expires_label }}</th>
          <th><i class="fas fa-server"></i> {{ t.port_label }}</th>
          <th><i class="fas fa-database"></i> {{ t.bandwidth_limit_label }}</th>
          <th><i class="fas fa-tachometer-alt"></i> {{ t.speed_limit_label }}</th>
          <th><i class="fas fa-chart-line"></i> {{ t.active_users }}</th>
          <th><i class="fas fa-cog"></i> {{ t.actions }}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.status == 'Expired' %}expired{% endif %}">
        <td style="color:var(--ok);"><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
        <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
        <td>
          {% if u.status == "Online" %}<span class="pill status-ok">{{ t.online }}</span>
          {% elif u.status == "Offline" %}<span class="pill status-bad">{{ t.offline }}</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">{{ t.expired }}</span>
          {% elif u.status == "suspended" %}<span class="pill status-bad">{{ t.suspended }}</span>
          {% else %}<span class="pill status-unk">{{ t.unknown }}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{ t.delete_confirm|format(u.user) }}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn secondary" style="padding:6px 12px;" onclick="editUser('{{u.user}}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == "suspended" or u.status == "Expired" %}
          <form class="delform" method="post" action="/activate">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" style="padding:6px 12px;">
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
    <div class="box" style="box-shadow:none;border:none;padding:0;margin:0;">
      <h3 class="label-c6"><i class="fas fa-chart-bar"></i> {{ t.reports }}</h3>
      <div class="row">
        <div><label>{{ t.from_date }}</label><input type="date" id="fromDate"></div>
        <div><label>{{ t.to_date }}</label><input type="date" id="toDate"></div>
        <div><label>{{ t.report_type }}</label>
          <select id="reportType">
            <option value="bandwidth">{{ t.bandwidth_usage }}</option>
            <option value="users">{{ t.user_activity }}</option>
            <option value="revenue">{{ t.revenue }}</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">
          <i class="fas fa-chart-bar"></i> {{ t.generate_report }}
        </button></div>
      </div>
    </div>
    <div id="reportResults" class="box" style="margin-top:20px;padding:15px;font-family:monospace;white-space:pre-wrap;overflow-x:auto;"></div>
  </div>
</div>

{% endif %}
</div>

<script>
const translations = {{ t | tojson }};
const lang = "{{ lang }}";
const loginRequired = {{ 'true' if login_enabled() else 'false' }};

function openTab(event, tabName) {
  document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  document.getElementById(tabName).classList.add('active');
  event.currentTarget.classList.add('active');
}

function t(key) {
  return translations[key] || key;
}

function toggleTheme() {
  const body = document.body;
  const currentTheme = body.classList.contains('light-mode') ? 'light' : 'dark';
  const newTheme = currentTheme === 'light' ? 'dark' : 'light';
  body.classList.toggle('light-mode');
  document.getElementById('theme-icon').className = newTheme === 'light' ? 'fas fa-sun' : 'fas fa-moon';
  localStorage.setItem('theme', newTheme);
}

function changeLang(newLang) {
  if (loginRequired && !{{ 'true' if authed else 'false' }}) {
    // If not authed, save to storage and reload login page
    localStorage.setItem('lang', newLang);
    window.location.href = '/login?lang=' + newLang;
  } else {
    // If authed, use server route to update session and reload
    window.location.href = '/lang?set=' + newLang;
  }
}

// Initialize theme on load
document.addEventListener('DOMContentLoaded', () => {
  const savedTheme = localStorage.getItem('theme');
  if (savedTheme === 'light') {
    document.body.classList.add('light-mode');
    document.getElementById('theme-icon').className = 'fas fa-sun';
  }
  // Ensure the language select is set correctly (only on unauthed page load)
  if (!{{ 'true' if authed else 'false' }} && loginRequired) {
    const urlParams = new URLSearchParams(window.location.search);
    const urlLang = urlParams.get('lang');
    const savedLang = localStorage.getItem('lang') || 'en';
    const effectiveLang = urlLang || savedLang;
    const langSelect = document.querySelector('.lang-select');
    if (langSelect) {
      langSelect.value = effectiveLang;
      localStorage.setItem('lang', effectiveLang); // Store effective lang
    }
  }
});

function executeBulkAction() {
  const action = document.getElementById('bulkAction').value;
  const users = document.getElementById('bulkUsers').value;
  if (!action || !users) { alert('{{ t("select_action") }}'); return; }
  
  fetch('/api/bulk', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
  }).then(r => r.json()).then(data => {
    alert(data.message || data.err); location.reload();
  });
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

function editUser(username) {
  const newPass = prompt(t('update_user') + ' ' + username + ':');
  if (newPass !== null && newPass.trim() !== "") {
    fetch('/api/user/update', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({user: username, password: newPass.trim()})
    }).then(r => r.json()).then(data => {
      alert(data.message || data.err); location.reload();
    });
  }
}

function generateReport() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const type = document.getElementById('reportType').value;
  document.getElementById('reportResults').innerHTML = t('generating_report');
  
  fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
    .then(r => r.json()).then(data => {
      if (data.error) {
        document.getElementById('reportResults').innerHTML = `<div class="err">${data.error}</div>`;
      } else {
        document.getElementById('reportResults').innerHTML = '<pre style="white-space:pre-wrap;">' + JSON.stringify(data, null, 2) + '</pre>';
      }
    }).catch(e => {
      document.getElementById('reportResults').innerHTML = `<div class="err">Error fetching report: ${e.message}</div>`;
    });
}

function importUsers() {
  alert('{{ t("import_users") }} - This feature requires manual file upload/database interaction currently.');
}
</script>
</body></html>"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

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

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, ROUND(CAST(bandwidth_used AS REAL) / (1024 * 1024 * 1024), 2) as bandwidth_used,
               speed_limit_up as speed_limit, concurrent_conn
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        # Convert GB back to Bytes for storage
        bw_limit_bytes = int(user_data.get('bandwidth_limit', 0)) * 1024 * 1024 * 1024
        
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), 'active', bw_limit_bytes,
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
        ))
        db.commit()
        
        # Add to billing if plan type specified
        if user_data.get('plan_type') and user_data.get('expires'):
            db.execute('''
                INSERT INTO billing (username, plan_type, expires_at)
                VALUES (?, ?, ?)
            ''', (user_data['user'], user_data['plan_type'], user_data['expires']))
            db.commit()
            
    finally:
        db.close()

def delete_user(username):
    db = get_db()
    try:
        # Also clear the port to ensure the lowest available port is reused quickly
        db.execute('UPDATE users SET port = NULL WHERE username = ?', (username,))
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
        total_bandwidth_bytes = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        # Simple server load simulation
        server_load = min(100, active_users * 5)
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth_bytes / (1024 * 1024 * 1024):.2f} GB",
            'server_load': server_load
        }
    finally:
        db.close()

def get_udp_listen_ports():
    # Gets all UDP ports actively listened to by the OS
    out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
    return set(re.findall(r":(\d+)\s", out))

def has_recent_udp_activity(port):
    if not port: return False
    try:
        # Check conntrack for activity within the last few minutes (default 300s/5min timeout for UDP)
        # We check if any connection is currently tracked for this port.
        out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                           shell=True, capture_output=True, text=True).stdout
        return bool(out.strip())
    except Exception:
        return False

def status_for_user(u):
    status = u.get('status', 'active')
    expires_str = u.get("expires", "")
    today_date = datetime.now().date()
    is_expired = False

    if expires_str:
        try:
            expires_dt=datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < today_date:
                is_expired=True
        except ValueError:
            pass
    
    if status == 'suspended' or is_expired:
        # If explicitly suspended or expired, report that status, regardless of connection
        return "Expired" if is_expired else "suspended"
    
    # If active, check connection state
    port = str(u.get("port",""))
    if not port: return "Unknown"
    
    if has_recent_udp_activity(port):
        return "Online"
    else:
        return "Offline"

def sync_config_passwords(mode="mirror"):
    users=load_users()
    users_pw=sorted({str(u["password"]) for u in users if u.get("password") and u.get("status") not in ["suspended", "Expired"]})
    
    cfg=read_json(CONFIG_FILE,{})
    if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
    cfg["auth"]["mode"]="passwords"
    cfg["auth"]["config"]=users_pw
    cfg["listen"]=cfg.get("listen") or ":5667"
    cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
    cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
    cfg["obfs"]=cfg.get("obfs") or "zivpn"
    
    write_json_atomic(CONFIG_FILE,cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True)

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True

def get_current_lang():
    # 1. Check URL parameter (for login page use)
    url_lang = request.args.get('lang')
    if url_lang and url_lang in LANGUAGES: return url_lang
    # 2. Check session
    session_lang = session.get('lang')
    if session_lang and session_lang in LANGUAGES: return session_lang
    # 3. Default
    return 'my' # Default to Burmese

@app.before_request
def set_language_from_session():
    if 'lang' not in session:
        session['lang'] = 'my' # Initial default

@app.route("/lang", methods=["GET"])
def set_language():
    new_lang = request.args.get('set')
    if new_lang in LANGUAGES:
        session['lang'] = new_lang
    return redirect(url_for('index'))


def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

def build_view(msg="", err=""):
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']

    if not require_login():
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), t=t, lang=lang, login_enabled=login_enabled)
    
    users=load_users()
    active=get_udp_listen_ports()
    stats = get_server_stats()
    
    view=[]
    for u in users:
        u_status = status_for_user(u)
        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":u.get("expires",""),
            "port":u.get("port",""),
            "status":u_status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": u.get('bandwidth_used', 0),
            "speed_limit": u.get('speed_limit', 0)
        }))
    
    view.sort(key=lambda x:(x.user or "").lower())
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL, 
                                users=view, msg=msg, err=err, stats=stats, t=t, lang=lang, login_enabled=login_enabled)

# Routes
@app.route("/login", methods=["GET","POST"])
def login():
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']
    
    if not login_enabled(): return redirect(url_for('index'))
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('index'))
        else:
            session["auth"]=False
            session["login_err"]=t['login_err']
            return redirect(url_for('login', lang=lang))
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), t=t, lang=lang, login_enabled=login_enabled)

@app.route("/logout", methods=["GET"])
def logout():
    lang = get_current_lang()
    session.pop("auth", None)
    return redirect(url_for('login', lang=lang) if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']
    if not require_login(): return redirect(url_for('login'))
    
    user_data = {
        'user': (request.form.get("user") or "").strip(),
        'password': (request.form.get("password") or "").strip(),
        'expires': (request.form.get("expires") or "").strip(),
        'port': (request.form.get("port") or "").strip(),
        'bandwidth_limit': int(request.form.get("bandwidth_limit") or 0),
        'speed_limit': int(request.form.get("speed_limit") or 0),
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1),
        'plan_type': (request.form.get("plan_type") or "").strip()
    }
    
    if not user_data['user'] or not user_data['password']:
        return build_view(err=t['user_pass_required'])
    
    # Handle expiration calculation (days or date)
    if user_data['expires'] and user_data['expires'].isdigit():
        try:
            days = int(user_data['expires'])
            user_data['expires'] = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
        except ValueError:
            return build_view(err=t['expires_invalid'])
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=t['expires_invalid'])
    
    if user_data['port']:
        try:
            if not (6000 <= int(user_data['port']) <= 19999):
                return build_view(err=t['port_range_invalid'])
        except ValueError:
            return build_view(err=t['port_range_invalid'])
    
    if not user_data['port']:
        # Auto assign port - find the lowest unused port
        used_ports = {str(u.get('port', '')) for u in load_users() if u.get('port')}
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                user_data['port'] = str(p)
                break
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=t['saved_msg'])

@app.route("/delete", methods=["POST"])
def delete_user_html():
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=t['user_label'] + ' ' + t['user_pass_required'])
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=t['deleted_msg'].format(user))

@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
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
        db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
        db.commit()
        db.close()
        sync_config_passwords()
    return redirect(url_for('index'))

# API Routes
@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']
    if not require_login(): return jsonify({"ok": False, "err": t['login_err']}), 401
    
    data = request.get_json() or {}
    action = data.get('action')
    users = data.get('users', [])
    
    db = get_db()
    try:
        affected_count = 0
        for user in users:
            user = user.strip()
            if not user: continue
            
            if action == 'extend':
                cursor = db.execute('UPDATE users SET expires = date(expires, "+7 days") WHERE username = ?', (user,))
            elif action == 'suspend':
                cursor = db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
            elif action == 'activate':
                cursor = db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
            elif action == 'delete':
                cursor = db.execute('DELETE FROM users WHERE username = ?', (user,))
            else:
                return jsonify({"ok": False, "err": "Invalid action"}), 400
            affected_count += cursor.rowcount
        
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": f"{affected_count} users processed with {action}"})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Status\n"
    for u in users:
        # Note: Bandwidth Limit is stored in Bytes in DB, displayed in GB here (u.get('bandwidth_limit') is in GB after load_users)
        bw_limit_gb = round(u.get('bandwidth_limit', 0) / (1024 * 1024 * 1024), 2)
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{u.get('bandwidth_used',0)},{bw_limit_gb},{u.get('speed_limit',0)},{u.get('status','')}\n"
    
    response = make_response(csv_data)
    response.headers["Content-Disposition"] = "attachment; filename=zivpn_users_export.csv"
    response.headers["Content-type"] = "text/csv"
    return response

@app.route("/api/reports")
def generate_reports():
    if not require_login(): return jsonify({"error": "Unauthorized"}), 401
    
    report_type = request.args.get('type', 'bandwidth')
    from_date = request.args.get('from')
    to_date = request.args.get('to')
    
    db = get_db()
    try:
        if report_type == 'bandwidth':
            data = db.execute('''
                SELECT username, ROUND(SUM(bytes_used) / (1024 * 1024 * 1024), 2) as total_gb_used 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username ORDER BY total_gb_used DESC
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date ORDER BY date
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        elif report_type == 'revenue':
            # Simple revenue report based on billing table
            data = db.execute('''
                SELECT plan_type, COUNT(*) as sales_count, SUM(amount) as estimated_revenue
                FROM billing 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY plan_type
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        else:
            return jsonify({"error": "Invalid report type"}), 400

        return jsonify([dict(d) for d in data])
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user():
    lang = get_current_lang()
    t = LANGUAGES.get(lang) or LANGUAGES['my']
    if not require_login(): return jsonify({"ok": False, "err": t['login_err']}), 401
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    
    if user and password:
        db = get_db()
        db.execute('UPDATE users SET password = ? WHERE username = ?', (password, user))
        db.commit()
        db.close()
        sync_config_passwords()
        return jsonify({"ok": True, "message": t['user_updated']})
    
    return jsonify({"ok": False, "err": "Invalid data"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY
# ===== API Service (api.py) =====
say "${Y}🔌 API Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/api.py <<'PY'
from flask import Flask, jsonify, request
import sqlite3, datetime
from datetime import timedelta
import re, subprocess

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
        # Convert Bytes to GB for easier display/handling if requested by external API client
        user_dict = dict(user)
        user_dict['bandwidth_used_gb'] = round(user_dict.pop('bandwidth_used') / (1024 * 1024 * 1024), 2)
        user_dict['bandwidth_limit_gb'] = round(user_dict.pop('bandwidth_limit') / (1024 * 1024 * 1024), 2)
        return jsonify(user_dict)
    return jsonify({"error": "User not found"}), 404

@app.route('/api/v1/bandwidth/<username>', methods=['POST'])
def update_bandwidth(username):
    data = request.get_json()
    bytes_used = int(data.get('bytes_used', 0))
    
    db = get_db()
    try:
        # Update bandwidth and check limits
        db.execute('''
            UPDATE users 
            SET bandwidth_used = bandwidth_used + ?, updated_at = CURRENT_TIMESTAMP 
            WHERE username = ?
        ''', (bytes_used, username))
        
        # Log bandwidth usage (in bytes)
        db.execute('''
            INSERT INTO bandwidth_logs (username, bytes_used) 
            VALUES (?, ?)
        ''', (username, bytes_used))
        
        db.commit()
        return jsonify({"message": "Bandwidth updated"})
    finally:
        db.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Telegram Bot (bot.py) =====
say "${Y}🤖 Telegram Bot Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/bot.py <<'PY'
import telegram
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import sqlite3, logging, os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATABASE_PATH = "/etc/zivpn/zivpn.db"
# NOTE: User needs to update this token in web.env or manually in this file
BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN_HERE') 

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def start(update, context):
    update.message.reply_text(
        '🤖 ZIVPN Bot မှ ကြိုဆိုပါတယ်!\n\n'
        'Commands:\n'
        '/stats - Server statistics\n'
        '/users - User list (Top 20)\n'
        '/myinfo <username> - User information\n'
        '/help - Help message'
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
    
    # Convert to GB
    total_bw_gb = stats['total_bandwidth'] / (1024 * 1024 * 1024) if stats['total_bandwidth'] else 0
    
    message = (
        f"📊 Server Statistics:\n"
        f"• Total Users: {stats['total_users']}\n"
        f"• Active Users: {stats['active_users']}\n"
        f"• Bandwidth Used: {total_bw_gb:.2f} GB"
    )
    update.message.reply_text(message)

def get_users(update, context):
    db = get_db()
    users = db.execute('SELECT username, status, expires FROM users LIMIT 20').fetchall()
    db.close()
    
    if not users:
        update.message.reply_text("No users found")
        return
    
    message = "👥 User List (Top 20):\n"
    for user in users:
        message += f"• {user['username']} - {user['status'].upper()} - Exp: {user['expires'] or 'Never'}\n"
    
    update.message.reply_text(message)

def get_user_info(update, context):
    if not context.args:
        update.message.reply_text("Usage: /myinfo <username>")
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
        update.message.reply_text("User not found")
        return
    
    # Convert to GB
    bw_used_gb = user['bandwidth_used'] / (1024 * 1024 * 1024) if user['bandwidth_used'] else 0
    bw_limit_gb = user['bandwidth_limit'] / (1024 * 1024 * 1024) if user['bandwidth_limit'] else 0
    
    message = (
        f"👤 User: {user['username']}\n"
        f"📊 Status: {user['status'].upper()}\n"
        f"⏰ Expires: {user['expires'] or 'Never'}\n"
        f"📦 Bandwidth: {bw_used_gb:.2f} GB / {bw_limit_gb:.2f} GB\n"
        f"⚡ Speed Limit: {user['speed_limit_up']} MB/s\n"
        f"🔗 Max Connections: {user['concurrent_conn']}"
    )
    update.message.reply_text(message)

def main():
    if BOT_TOKEN == 'YOUR_BOT_TOKEN_HERE':
        logger.error("Please set TELEGRAM_BOT_TOKEN environment variable or update the bot.py file manually.")
        # Do not exit, but let the service run so the user can see the error
        return
    
    try:
        updater = Updater(BOT_TOKEN, use_context=True)
        dp = updater.dispatcher
        
        dp.add_handler(CommandHandler("start", start))
        dp.add_handler(CommandHandler("stats", get_stats))
        dp.add_handler(CommandHandler("users", get_users))
        dp.add_handler(CommandHandler("myinfo", get_user_info))
        
        updater.start_polling()
        updater.idle()
    except Exception as e:
        logger.error(f"Error starting Telegram bot: {e}")

if __name__ == '__main__':
    main()
PY

# ===== Cleanup Script (cleanup.py) - Handles Auto-Suspend and Conntrack Cleanup =====
say "${Y}🧹 Auto Cleanup Script ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/cleanup.py <<'PY'
import sqlite3
from datetime import datetime
import subprocess
import os
import time
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

DATABASE_PATH = "/etc/zivpn/zivpn.db"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def run_cleanup_tasks():
    logging.info("Starting ZIVPN cleanup tasks...")
    db = get_db()
    try:
        # 1. Auto Suspend Expired Users
        now_date = datetime.now().strftime("%Y-%m-%d")
        logging.info(f"Checking for expired users before {now_date}...")
        
        # Select users who have expired but are still active
        expired_users = db.execute('''
            SELECT username, port FROM users
            WHERE status = 'active' AND expires IS NOT NULL AND expires < ?
        ''', (now_date,)).fetchall()
        
        for user in expired_users:
            username = user['username']
            port = user['port']
            
            # Update status in DB
            db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (username,))
            logging.warning(f"User {username} expired and set to 'suspended'.")
            
            # Forcefully clear conntrack entry to drop current connection
            if port:
                try:
                    subprocess.run(f"conntrack -D -p udp --dport {port} --orig-port {port}", shell=True, check=False, capture_output=True)
                    logging.info(f"Cleared conntrack for port {port} (user {username}).")
                except Exception as e:
                    logging.error(f"Failed to clear conntrack for {username}: {e}")

        db.commit()
        logging.info(f"Total {len(expired_users)} users suspended.")

        # 2. Bandwidth Limit Suspend/Reset (If over limit and active)
        # Convert GB limit back to Bytes for comparison
        over_limit_users = db.execute('''
            SELECT username, port FROM users
            WHERE status = 'active' AND bandwidth_limit > 0 AND bandwidth_used >= bandwidth_limit
        ''').fetchall()
        
        for user in over_limit_users:
            username = user['username']
            port = user['port']
            db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (username,))
            logging.warning(f"User {username} hit bandwidth limit and set to 'suspended'.")
            if port:
                subprocess.run(f"conntrack -D -p udp --dport {port} --orig-port {port}", shell=True, check=False, capture_output=True)

        db.commit()
        logging.info(f"Total {len(over_limit_users)} users suspended for hitting bandwidth limit.")

        # 3. Trigger ZIVPN config sync and restart to remove passwords of suspended users
        from web import sync_config_passwords
        # Temporarily change cwd to /etc/zivpn so the import works
        original_cwd = os.getcwd()
        os.chdir("/etc/zivpn")
        try:
            # Re-import web module in case of updates, then run sync
            import importlib
            import web
            importlib.reload(web)
            web.sync_config_passwords()
            logging.info("ZIVPN config synced and server restarted.")
        except Exception as e:
            logging.error(f"Failed to sync config and restart ZIVPN: {e}")
        finally:
            os.chdir(original_cwd)


    except Exception as e:
        logging.error(f"An error occurred during cleanup: {e}")
    finally:
        db.close()

if __name__ == '__main__':
    run_cleanup_tasks()
PY

# ===== Backup Script (backup.py) - Unchanged but included for completeness =====
say "${Y}💾 Backup System ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/backup.py <<'PY'
import sqlite3, shutil, datetime, os, gzip

BACKUP_DIR = "/etc/zivpn/backups"
DATABASE_PATH = "/etc/zivpn/zivpn.db"

def backup_database():
    if not os.path.exists(BACKUP_DIR):
        os.makedirs(BACKUP_DIR)
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(BACKUP_DIR, f"zivpn_backup_{timestamp}.db.gz")
    
    # Backup database
    with open(DATABASE_PATH, 'rb') as f_in:
        with gzip.open(backup_file, 'wb') as f_out:
            shutil.copyfileobj(f_in, f_out)
    
    # Cleanup old backups (keep last 7 days)
    for file in os.listdir(BACKUP_DIR):
        file_path = os.path.join(BACKUP_DIR, file)
        if os.path.isfile(file_path):
            file_time = datetime.datetime.fromtimestamp(os.path.getctime(file_path))
            if (datetime.datetime.now() - file_time).days > 7:
                os.remove(file_path)
    
    print(f"Backup created: {backup_file}")

if __name__ == '__main__':
    backup_database()
PY

# ===== systemd Services =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service - Unchanged
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

# Web Panel Service - Unchanged
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

# API Service - Unchanged
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

# Backup Service Timer - Unchanged
cat >/etc/systemd/system/zivpn-backup.service <<'EOF'
[Unit]
Description=ZIVPN Backup Service
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/backup.py

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-backup.timer <<'EOF'
[Unit]
Description=Daily ZIVPN Backup
Requires=zivpn-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# NEW: Cleanup Service and Timer
cat >/etc/systemd/system/zivpn-cleanup.service <<'EOF'
[Unit]
Description=ZIVPN Auto Cleanup and Suspend Service
After=zivpn-web.service

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
Description=Hourly ZIVPN Auto Cleanup
Requires=zivpn-cleanup.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF


# ===== Networking Setup =====
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
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 8081/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

# ===== Final Setup =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-backup.timer
systemctl enable --now zivpn-cleanup.timer # Enable new cleanup timer

# Initial cleanup and backup
python3 /etc/zivpn/backup.py
python3 /etc/zivpn/cleanup.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition Setup Complete (v2.0)!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "  ${M}Admin/Pass:${Z} ${WEB_USER}/${WEB_PASS}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "${C}📊 Database:${Z} ${Y}/etc/zivpn/zivpn.db${Z}"
echo -e "\n${M}📋 Services:${Z}"
echo -e "  ${Y}systemctl status zivpn${Z}      - VPN Server"
echo -e "  ${Y}systemctl status zivpn-web${Z}  - Web Panel"
echo -e "  ${Y}systemctl status zivpn-api${Z}  - API Server"
echo -e "  ${Y}systemctl list-timers${Z}       - (Daily Backup, Hourly Cleanup)"
echo -e "\n${G}🎯 New Features Enabled:${Z}"
echo -e "  ✓ Enhanced UI/UX with Dark/Light Mode"
echo -e "  ✓ Myanmar/English Language Support"
echo -e "  ✓ Accurate Online/Offline Status (via conntrack/DB status)"
echo -e "  ✓ Automated Hourly Cleanup & Expiry Suspend"
echo -e "$LINE"
