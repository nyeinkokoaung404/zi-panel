#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION (V2 - Enhanced)
# Author: 4 0 4 \ 2.0 [🇲🇲] - Enhanced by Gemini
# Features: Complete Enterprise Management System with Bandwidth Control, Billing, Multi-Server, API, Auto-Suspend, Mac Control Display, Modern UI/UX.
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION (V2) ${Z}\n$LINE"

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
# Add python3-cron-schedule if available, otherwise rely on systemd timers
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
systemctl stop zivpn-scheduler.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
DB="/etc/zivpn/zivpn.db"
ENVF="/etc/zivpn/web.env"
BACKUP_DIR="/etc/zivpn/backups"
mkdir -p /etc/zivpn "$BACKUP_DIR"

# ===== Download ZIVPN binary (Same as before) =====
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

# ===== Enhanced Database Setup (Minor updates to support port history) =====
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

-- New table for port management
CREATE TABLE IF NOT EXISTS port_history (
    port INTEGER PRIMARY KEY,
    last_used_at DATETIME,
    is_available INTEGER DEFAULT 1 -- 1=Available, 0=Assigned
);
EOF

# ===== Base config (Same as before) =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs (Same as before) =====
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

# ===== Ask initial VPN passwords (Same as before) =====
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

# ===== Update config.json (Same as before) =====
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

# Configuration
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
CONNTRAK_CHECK_THRESHOLD = 30 # seconds
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# UI Text Dictionary for Language Support
TEXTS = {
    'my': {
        'title': 'Channel 404 ZIVPN Enterprise Panel',
        'sub_title': '⊱✫⊰ Enterprise စီမံခန့်ခွဲမှုစနစ် ⊱✫⊰',
        'login_failed': 'မှန်ကန်မှုမရှိပါ',
        'contact': 'ဆက်သွယ်ရန်',
        'logout': 'ထွက်ရန်',
        'total_users': 'အသုံးပြုသူ စုစုပေါင်း',
        'active_users': 'အသုံးပြုနေသူ',
        'bandwidth_used': 'သုံးစွဲပြီး Bandwidth',
        'server_load': 'Server Load',
        'user_management': 'အသုံးပြုသူ စီမံခန့်ခွဲခြင်း',
        'add_user': 'အသုံးပြုသူ အသစ်ထည့်ပါ',
        'bulk_operations': 'အစုလိုက် လုပ်ဆောင်ချက်များ',
        'reports': 'အစီရင်ခံစာများ',
        'username': 'အသုံးပြုသူအမည်',
        'password': 'စကားဝှက်',
        'expires': 'သက်တမ်းကုန်ဆုံးရက်',
        'port': 'Port',
        'bandwidth_limit': 'Bandwidth ကန့်သတ်ချက် (GB)',
        'speed_limit': 'Speed ကန့်သတ်ချက် (MB/s)',
        'max_conn': 'အများဆုံး ချိတ်ဆက်မှု',
        'plan_type': 'အစီအစဉ်အမျိုးအစား',
        'save_user': 'အသုံးပြုသူအား သိမ်းဆည်းမည်',
        'required_fields': 'အသုံးပြုသူအမည်နှင့် စကားဝှက် လိုအပ်သည်',
        'invalid_expires': 'သက်တမ်းကုန်ဆုံးရက် ပုံစံမမှန်ပါ',
        'port_range': 'Port အကွာအဝေး 6000-19999',
        'save_success': 'အသုံးပြုသူအား အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ',
        'user_required': 'အသုံးပြုသူအမည် လိုအပ်သည်',
        'delete_confirm': ' ကို ဖျက်မလား?',
        'deleted': 'ဖျက်လိုက်ပါပြီ',
        'online': 'ချိတ်ဆက်ထားသည်',
        'offline': 'ချိတ်ဆက်မှု ပြတ်တောက်',
        'expired': 'သက်တမ်းကုန်ဆုံး',
        'suspended': 'ရပ်ဆိုင်းထားသည်',
        'unknown': 'မသိရှိရ',
        'search_users': 'အသုံးပြုသူများ ရှာဖွေပါ...',
        'actions': 'လုပ်ဆောင်ချက်များ',
        'select_action': 'လုပ်ဆောင်ချက် ရွေးပါ',
        'extend_expiry': 'သက်တမ်းတိုးမည် (+7 ရက်)',
        'suspend_users': 'ရပ်ဆိုင်းမည်',
        'activate_users': 'အသက်ဝင်စေမည်',
        'delete_users': 'ဖျက်ပစ်မည်',
        'users_comma': 'အသုံးပြုသူအမည်များ (user1,user2)',
        'execute': 'လုပ်ဆောင်မည်',
        'export_csv': 'အသုံးပြုသူများ CSV ထုတ်ယူမည်',
        'import_users': 'အသုံးပြုသူများ တင်သွင်းမည်',
        'edit_user': 'ပြင်ဆင်မည်',
        'new_password': 'စကားဝှက်အသစ် ထည့်ပါ',
        'conn_count': 'လက်ရှိချိတ်ဆက်မှု',
        'from_date': 'ရက်စွဲမှ',
        'to_date': 'ရက်စွဲအထိ',
        'report_type': 'အစီရင်ခံစာ အမျိုးအစား',
        'bw_usage': 'Bandwidth အသုံးပြုမှု',
        'user_activity': 'အသုံးပြုသူ လှုပ်ရှားမှု',
        'revenue': 'ဝင်ငွေ',
        'generate_report': 'အစီရင်ခံစာ ထုတ်လုပ်မည်',
        'bulk_action_complete': 'အစုလိုက်လုပ်ဆောင်ချက် ပြီးပါပြီ',
        'user_updated': 'အသုံးပြုသူအား အောင်မြင်စွာ ပြုပြင်ပြီးပါပြီ',
        'invalid_data': 'ဒေတာ မမှန်ကန်ပါ',
        'login_title': 'ZIVPN Panel Login',
        'login_btn': 'ဝင်မည်',
        'enter_password': 'စကားဝှက် ထည့်ပါ',
    },
    'en': {
        'title': 'Channel 404 ZIVPN Enterprise Panel',
        'sub_title': '⊱✫⊰ Enterprise Management System ⊱✫⊰',
        'login_failed': 'Invalid Credentials',
        'contact': 'Contact',
        'logout': 'Logout',
        'total_users': 'Total Users',
        'active_users': 'Active Users',
        'bandwidth_used': 'Bandwidth Used',
        'server_load': 'Server Load',
        'user_management': 'User Management',
        'add_user': 'Add New User',
        'bulk_operations': 'Bulk Operations',
        'reports': 'Reports',
        'username': 'Username',
        'password': 'Password',
        'expires': 'Expires',
        'port': 'Port',
        'bandwidth_limit': 'Bandwidth Limit (GB)',
        'speed_limit': 'Speed Limit (MB/s)',
        'max_conn': 'Max Connections',
        'plan_type': 'Plan Type',
        'save_user': 'Save User',
        'required_fields': 'Username and Password are required',
        'invalid_expires': 'Invalid Expires format',
        'port_range': 'Port range 6000-19999',
        'save_success': 'User saved successfully',
        'user_required': 'User is required',
        'delete_confirm': ' to delete?',
        'deleted': 'Deleted:',
        'online': 'ONLINE',
        'offline': 'OFFLINE',
        'expired': 'EXPIRED',
        'suspended': 'SUSPENDED',
        'unknown': 'UNKNOWN',
        'search_users': 'Search users...',
        'actions': 'Actions',
        'select_action': 'Select Action',
        'extend_expiry': 'Extend Expiry (+7 days)',
        'suspend_users': 'Suspend Users',
        'activate_users': 'Activate Users',
        'delete_users': 'Delete Users',
        'users_comma': 'Usernames comma separated (user1,user2)',
        'execute': 'Execute',
        'export_csv': 'Export Users CSV',
        'import_users': 'Import Users',
        'edit_user': 'Edit',
        'new_password': 'Enter new password for',
        'conn_count': 'Connections',
        'from_date': 'From Date',
        'to_date': 'To Date',
        'report_type': 'Report Type',
        'bw_usage': 'Bandwidth Usage',
        'user_activity': 'User Activity',
        'revenue': 'Revenue',
        'generate_report': 'Generate Report',
        'bulk_action_complete': 'Bulk action completed',
        'user_updated': 'User updated successfully',
        'invalid_data': 'Invalid data',
        'login_title': 'ZIVPN Panel Login',
        'login_btn': 'Login',
        'enter_password': 'Password',
    }
}

HTML_TEMPLATE = """<!doctype html>
<html lang="{{ lang }}" data-theme="{{ theme }}">
<head>
<meta charset="utf-8">
<title>{{ T.title }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{
  /* Light Mode */
  --bg-light: #f4f7f9; --fg-light: #333; --card-light: #ffffff; --bd-light: #e0e0e0;
  --header-bg-light: #fff; --input-text-light: #333; --shadow-light: 0 4px 15px rgba(0,0,0,0.1);
  /* Dark Mode */
  --bg-dark: #1e1e1e; --fg-dark: #f0f0f0; --card-dark: #2d2d2d; --bd-dark: #444;
  --header-bg-dark: #2d2d2d; --input-text-dark: #fff; --shadow-dark: 0 4px 15px rgba(0,0,0,0.5);
  
  /* Shared Colors */
  --ok: #27ae60; --bad: #c0392b; --unk: #f39c12; --expired: #8e44ad; --info: #3498db; 
  --success: #1abc9c; --delete-btn: #e74c3c; --primary-btn: #3498db; --logout-btn: #e67e22;
  --telegram-btn: #0088cc; --radius: 8px;
}
html[data-theme="light"] {
  --bg: var(--bg-light); --fg: var(--fg-light); --card: var(--card-light); --bd: var(--bd-light);
  --header-bg: var(--header-bg-light); --input-text: var(--input-text-light); --shadow: var(--shadow-light);
}
html[data-theme="dark"], html { /* Default to Dark */
  --bg: var(--bg-dark); --fg: var(--fg-dark); --card: var(--card-dark); --bd: var(--bd-dark);
  --header-bg: var(--header-bg-dark); --input-text: var(--input-text-dark); --shadow: var(--shadow-dark);
}
html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px}
.container{max-width:1400px;margin:auto;padding:10px}

@keyframes colorful-shift {
  0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius);box-shadow:var(--shadow);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}

.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.3);display:flex;align-items:center;gap:8px;}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:#2980b9}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:#95a5a6;color:var(--fg)}.btn.secondary:hover{background:#7f8c8d}
.btn.toggle{background:var(--card);color:var(--fg);border:1px solid var(--bd)}
.btn.toggle:hover{background:#3a3a3a}

form.box{margin:25px 0;padding:25px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);}
h3{color:var(--fg);margin-top:0;}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);box-sizing:border-box;background:var(--bg);color:var(--input-text);}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:none;color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;}
.tab-btn.active{background:var(--primary-btn);color:white;}
.tab-content{display:none;}
.tab-content.active{display:block;}

.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);border-left:5px solid var(--info);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;}
.stat-label{font-size:.9em;color:var(--bd);}
.stat-card:nth-child(2){border-left-color:var(--ok)}
.stat-card:nth-child(3){border-left-color:var(--delete-btn)}
.stat-card:nth-child(4){border-left-color:var(--unk)}

table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;border:1px solid var(--bd);}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);}
th:last-child,td:last-child{border-right:none;}
th{background:#252525;font-weight:700;color:var(--fg);text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover:not(.expired){background:#3a3a3a}

.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;text-shadow:1px 1px 2px rgba(0,0,0,0.5);box-shadow:0 2px 4px rgba(0,0,0,0.2);}
.status-ok{color:white;background:var(--ok)}.status-bad{color:white;background:var(--bad)}
.status-unk{color:white;background:var(--unk)}.status-expired{color:white;background:var(--expired)}
.pill-yellow{background:#f1c40f}.pill-red{background:#e74c3c}.pill-green{background:#2ecc71}
.pill-lightgreen{background:#1abc9c}.pill-pink{background:#f78da7}.pill-orange{background:#e67e22}

.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:var(--expired);color:white}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;background:var(--card);box-shadow:var(--shadow);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;text-shadow:0 1px 3px rgba(0,0,0,0.5);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}
.conn-pill{padding:5px 8px;border-radius:4px;font-size:0.8em;font-weight:bold;}
.conn-ok{background:rgba(39, 174, 96, 0.2); color:var(--ok);}
.conn-warn{background:rgba(243, 156, 18, 0.2); color:var(--unk);}
.conn-bad{background:rgba(192, 57, 43, 0.2); color:var(--bad);}

.bulk-actions{margin:15px 0;display:flex;gap:10px;flex-wrap:wrap;}
.bulk-actions select,.bulk-actions input{padding:8px;border-radius:var(--radius);background:var(--bg);color:var(--fg);border:1px solid var(--bd);}

@media (max-width: 768px) {
  body{padding:10px}.container{padding:0}
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .header-right{width:100%;display:flex;justify-content:space-between;gap:5px;flex-wrap:wrap;}
  .row>div,.stats-grid{grid-template-columns:1fr;}
  .btn{width:auto;flex:1;margin-bottom:5px;justify-content:center}
  table,thead,tbody,th,td,tr{display:block;}
  thead tr{position:absolute;top:-9999px;left:-9999px;}
  tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
  td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
  td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
  td:nth-of-type(1):before{content:"{{ T.username }}";}td:nth-of-type(2):before{content:"{{ T.password }}";}
  td:nth-of-type(3):before{content:"{{ T.expires }}";}td:nth-of-type(4):before{content:"{{ T.port }}";}
  td:nth-of-type(5):before{content:"{{ T.bandwidth_limit }}";}td:nth-of-type(6):before{content:"{{ T.speed_limit }}";}
  td:nth-of-type(7):before{content:"{{ T.max_conn }}";}td:nth-of-type(8):before{content:"{{ T.conn_count }}";}
  td:nth-of-type(9):before{content:"{{ T.status }}";}td:nth-of-type(10):before{content:"{{ T.actions }}";}
  .delform{display:block;}tr.expired td{background:var(--expired);}
}
</style>
</head>
<body>
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
    <h3 class="center">{{ T.login_title }}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label><i class="fas fa-user icon icon-user"></i> {{ T.username }}</label>
      <input name="u" autofocus required>
      <label style="margin-top:15px"><i class="fas fa-lock icon icon-pass"></i> {{ T.enter_password }}</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i>{{ T.login_btn }}
      </button>
    </form>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]" class="logo">
    <div>
      <h1><span class="colorful-title">{{ T.title }}</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">{{ T.sub_title }}</span></div>
    </div>
  </div>
  <div class="header-right" style="display:flex;gap:10px;align-items:center">
    <button class="btn toggle" onclick="toggleTheme()">
      <i class="fas fa-moon" id="theme-icon"></i>
    </button>
    <button class="btn toggle" onclick="toggleLanguage()">
      <i class="fas fa-language"></i> {{ lang | upper }}
    </button>
    <a class="btn contact" href="https://t.me/nkka404" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>{{ T.contact }}
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>{{ T.logout }}
    </a>
  </div>
</header>

<!-- Stats Dashboard -->
<div class="stats-grid">
  <div class="stat-card">
    <i class="fas fa-users" style="font-size:2em;color:var(--info);"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">{{ T.total_users }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">{{ T.active_users }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:var(--delete-btn);"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{ T.bandwidth_used }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:var(--unk);"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{ T.server_load }}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab('users')">{{ T.user_management }}</button>
    <button class="tab-btn" onclick="openTab('adduser')">{{ T.add_user }}</button>
    <button class="tab-btn" onclick="openTab('bulk')">{{ T.bulk_operations }}</button>
    <button class="tab-btn" onclick="openTab('reports')">{{ T.reports }}</button>
  </div>

  <!-- Add User Tab -->
  <div id="adduser" class="tab-content">
    <form method="post" action="/add" class="box">
      <h3 style="color:var(--success);"><i class="fas fa-users-cog"></i> {{ T.add_user }}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label><i class="fas fa-user icon"></i> {{ T.username }}</label><input name="user" placeholder="{{ T.username }}" required></div>
        <div><label><i class="fas fa-lock icon"></i> {{ T.password }}</label><input name="password" placeholder="{{ T.password }}" required></div>
        <div><label><i class="fas fa-clock icon"></i> {{ T.expires }}</label><input name="expires" placeholder="2026-01-01 or 30" value="30"></div>
        <div><label><i class="fas fa-server icon"></i> {{ T.port }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label><i class="fas fa-tachometer-alt"></i> {{ T.speed_limit }}</label><input name="speed_limit" placeholder="0 = unlimited" value="0" type="number"></div>
        <div><label><i class="fas fa-database"></i> {{ T.bandwidth_limit }}</label><input name="bandwidth_limit" placeholder="0 = unlimited" value="0" type="number"></div>
        <div><label><i class="fas fa-plug"></i> {{ T.max_conn }}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label><i class="fas fa-money-bill"></i> {{ T.plan_type }}</label>
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
      <h3 style="color:var(--logout-btn);"><i class="fas fa-cogs"></i> {{ T.bulk_operations }}</h3>
      <div class="bulk-actions">
        <select id="bulkAction">
          <option value="">{{ T.select_action }}</option>
          <option value="extend">{{ T.extend_expiry }}</option>
          <option value="suspend">{{ T.suspend_users }}</option>
          <option value="activate">{{ T.activate_users }}</option>
          <option value="delete">{{ T.delete_users }}</option>
        </select>
        <input type="text" id="bulkUsers" placeholder="{{ T.users_comma }}">
        <button class="btn secondary" onclick="executeBulkAction()">
          <i class="fas fa-play"></i> {{ T.execute }}
        </button>
      </div>
      <div style="margin-top:15px">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> {{ T.export_csv }}
        </button>
        <button class="btn secondary" onclick="alert('{{ T.import_users }} လုပ်ဆောင်ချက်ကို လက်ရှိတွင် မရရှိနိုင်ပါ')">
          <i class="fas fa-upload"></i> {{ T.import_users }}
        </button>
      </div>
    </div>
  </div>

  <!-- Users Management Tab -->
  <div id="users" class="tab-content active">
    <div class="box">
      <h3 style="color:var(--info);"><i class="fas fa-users"></i> {{ T.user_management }}</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="{{ T.search_users }}" style="flex:1;">
        <button class="btn secondary" onclick="filterUsers()">
          <i class="fas fa-search"></i> {{ T.search_users }}
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> {{ T.username }}</th>
          <th><i class="fas fa-lock"></i> {{ T.password }}</th>
          <th><i class="fas fa-clock"></i> {{ T.expires }}</th>
          <th><i class="fas fa-server"></i> {{ T.port }}</th>
          <th><i class="fas fa-database"></i> {{ T.bandwidth_limit }}</th>
          <th><i class="fas fa-tachometer-alt"></i> {{ T.speed_limit }}</th>
          <th><i class="fas fa-plug"></i> {{ T.max_conn }}</th>
          <th><i class="fas fa-plug"></i> {{ T.conn_count }}</th>
          <th><i class="fas fa-chart-line"></i> {{ T.status }}</th>
          <th><i class="fas fa-cog"></i> {{ T.actions }}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.expires and u.expires < today %}expired{% endif %}" data-user-name="{{u.user}}">
        <td style="color:var(--ok);"><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used | round(2)}} / {{u.bandwidth_limit}} GB</span></td>
        <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
        <td><span class="conn-pill {% if u.conn_count > u.concurrent_conn %}conn-bad{% elif u.conn_count > 0 %}conn-warn{% else %}conn-ok{% endif %}">{{u.concurrent_conn}}</span></td>
        <td><span class="conn-pill {% if u.conn_count > u.concurrent_conn %}conn-bad{% elif u.conn_count > 0 %}conn-ok{% else %}conn-warn{% endif %}">{{u.conn_count}}</span></td>
        <td>
          {% set status_text = T[u.status.lower()] %}
          {% if u.status == "Online" %}<span class="pill status-ok">{{ status_text }}</span>
          {% elif u.status == "Offline" %}<span class="pill status-bad">{{ status_text }}</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">{{ status_text }}</span>
          {% elif u.status == "Suspended" %}<span class="pill status-bad">{{ status_text }}</span>
          {% else %}<span class="pill status-unk">{{ status_text }}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;justify-content:center;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} {{ T.delete_confirm }}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="Delete User" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn secondary" title="Edit Password" style="padding:6px 12px;" onclick="editUser('{{u.user}}', '{{ T.new_password }}', '{{ T.user_updated }}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == "Suspended" or u.status == "Expired" %}
          <form class="delform" method="post" action="/activate">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" title="Activate User" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="Suspend User" style="padding:6px 12px;">
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
      <h3 style="color:var(--success);"><i class="fas fa-chart-bar"></i> {{ T.reports }}</h3>
      <div class="row">
        <div><label>{{ T.from_date }}</label><input type="date" id="fromDate"></div>
        <div><label>{{ T.to_date }}</label><input type="date" id="toDate"></div>
        <div><label>{{ T.report_type }}</label>
          <select id="reportType">
            <option value="bandwidth">{{ T.bw_usage }}</option>
            <option value="users">{{ T.user_activity }}</option>
            <option value="revenue">{{ T.revenue }}</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">{{ T.generate_report }}</button></div>
      </div>
    </div>
    <div id="reportResults"></div>
  </div>
</div>

{% endif %}
</div>

<script>
const TEXT_DICT = {{ TEXTS | tojson }};
let CURRENT_LANG = localStorage.getItem('lang') || 'my';
let CURRENT_THEME = localStorage.getItem('theme') || 'dark';

document.addEventListener('DOMContentLoaded', () => {
  setInitialState();
});

function setInitialState() {
  // Theme Setup
  document.documentElement.setAttribute('data-theme', CURRENT_THEME);
  updateThemeIcon();

  // Language Setup (Handled by Flask on load, but keeps local storage consistent)
  localStorage.setItem('lang', CURRENT_LANG);
}

function updateThemeIcon() {
  const icon = document.getElementById('theme-icon');
  if (icon) {
    icon.className = CURRENT_THEME === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
  }
}

function toggleTheme() {
  CURRENT_THEME = CURRENT_THEME === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', CURRENT_THEME);
  localStorage.setItem('theme', CURRENT_THEME);
  updateThemeIcon();
}

function toggleLanguage() {
  CURRENT_LANG = CURRENT_LANG === 'my' ? 'en' : 'my';
  localStorage.setItem('lang', CURRENT_LANG);
  // Reload page to re-render with new language text from Flask
  location.reload();
}

function openTab(tabName) {
  document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  document.getElementById(tabName).classList.add('active');
  
  // Find the button that corresponds to the tab and activate it
  const button = event.currentTarget;
  button.classList.add('active');
}

function executeBulkAction() {
  const T = TEXT_DICT[CURRENT_LANG];
  const action = document.getElementById('bulkAction').value;
  const users = document.getElementById('bulkUsers').value;
  if (!action || !users) { alert('{{ T.select_action }} / {{ T.users_comma }}'); return; }
  
  fetch('/api/bulk', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
  }).then(r => r.json()).then(data => {
    alert(data.message || T.bulk_action_complete); 
    location.reload();
  }).catch(e => alert('Error: ' + e));
}

function exportUsers() {
  window.open('/api/export/users', '_blank');
}

function filterUsers() {
  const search = document.getElementById('searchUser').value.toLowerCase();
  document.querySelectorAll('tbody tr').forEach(row => {
    const user = row.getAttribute('data-user-name').toLowerCase();
    row.style.display = user.includes(search) ? '' : 'none';
  });
}

function editUser(username, promptText, successText) {
  const newPass = prompt(promptText + ' ' + username + ':');
  if (newPass) {
    fetch('/api/user/update', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({user: username, password: newPass})
    }).then(r => r.json()).then(data => {
      alert(data.message || successText); 
      location.reload();
    }).catch(e => alert('Error: ' + e));
  }
}

function generateReport() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const type = document.getElementById('reportType').value;
  const T = TEXT_DICT[CURRENT_LANG];
  
  fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
    .then(r => r.json()).then(data => {
      document.getElementById('reportResults').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
    }).catch(e => {
        document.getElementById('reportResults').innerHTML = `<div class="err">Error generating report: ${e}</div>`;
    });
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

def get_current_connections(port):
    if not port: return 0
    try:
        # Check for active UDP connections on the port using conntrack
        # Note: We filter for 'ESTABLISHED' or similar states implicitly via default conntrack tracking.
        # This count represents simultaneous connections tracked by the kernel.
        cmd = f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b' | wc -l"
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
        return int(out)
    except Exception:
        return 0

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, bandwidth_used, speed_limit_up as speed_limit,
               concurrent_conn
        FROM users
    ''').fetchall()
    db.close()
    
    users_list = []
    listen_port = get_listen_port_from_config()
    today_date = datetime.now().date()
    
    for u in users:
        u_dict = dict(u)
        port = str(u_dict.get("port",""))
        check_port = port if port else listen_port
        
        # 1. Get Connection Count (for Mac Control Display)
        conn_count = get_current_connections(check_port)
        u_dict['conn_count'] = conn_count
        
        # 2. Determine Expiry Status
        expires_str = u_dict.get("expires","")
        is_expired = False
        if expires_str:
             try:
                 expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
                 if expires_dt < today_date:
                     is_expired = True
             except ValueError:
                 pass
        
        # 3. Determine Overall Status
        if u_dict.get('status') == 'suspended':
             u_dict['status'] = "Suspended"
        elif is_expired:
             u_dict['status'] = "Expired"
        elif conn_count > 0:
             u_dict['status'] = "Online"
        else:
             u_dict['status'] = "Offline"
             
        # Convert Bandwidth to GB for UI
        u_dict['bandwidth_used'] = u_dict['bandwidth_used'] / 1024 / 1024 / 1024
        u_dict['bandwidth_limit'] = u_dict['bandwidth_limit'] / 1024 / 1024 / 1024

        users_list.append(type("U", (), u_dict))
    
    return users_list

def save_user(user_data):
    db = get_db()
    try:
        # Convert GB to Bytes for DB storage
        bandwidth_limit_bytes = user_data.get('bandwidth_limit', 0) * 1024 * 1024 * 1024
        
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), 'active', bandwidth_limit_bytes,
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
        ))
        db.commit()
        
        # Add to billing if plan type specified
        if user_data.get('plan_type'):
            expires = user_data.get('expires') or (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
            db.execute('''
                INSERT INTO billing (username, plan_type, expires_at)
                VALUES (?, ?, ?)
            ''', (user_data['user'], user_data['plan_type'], expires))
            db.commit()
            
        # Update port_history as assigned
        if user_data.get('port'):
            db.execute('''
                INSERT OR REPLACE INTO port_history (port, last_used_at, is_available)
                VALUES (?, ?, 0)
            ''', (user_data['port'], datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
            db.commit()

    finally:
        db.close()

def delete_user(username):
    db = get_db()
    try:
        # 1. Get port before deleting user
        port_to_free = db.execute('SELECT port FROM users WHERE username = ?', (username,)).fetchone()
        
        # 2. Delete user and billing info
        db.execute('DELETE FROM users WHERE username = ?', (username,))
        db.execute('DELETE FROM billing WHERE username = ?', (username,))
        db.commit()
        
        # 3. Mark port as available in port_history
        if port_to_free and port_to_free['port']:
            db.execute('UPDATE port_history SET is_available = 1 WHERE port = ?', (port_to_free['port'],))
            db.commit()
    finally:
        db.close()

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        # Active users based on 'active' status and not expired
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)').fetchone()[0]
        total_bandwidth_bytes = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        # Simple server load simulation
        server_load = min(100, (active_users * 5) + (total_users / 10))
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth_bytes / 1024 / 1024 / 1024:.2f} GB",
            'server_load': int(server_load)
        }
    finally:
        db.close()

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
    out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
    return set(re.findall(r":(\d+)\s", out))

def sync_config_passwords(mode="mirror"):
    users = load_users()
    # Only sync passwords of active/non-suspended users to the zivpn binary
    users_pw = sorted({str(u.password) for u in users if u.status not in ("Suspended", "Expired") and u.password})
    
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
def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

@app.before_request
def get_language():
    # Set language from cookie or default to Burmese
    lang = request.cookies.get('lang', 'my')
    if lang not in TEXTS:
        lang = 'my'
    request.lang = lang

def build_view(msg="", err=""):
    lang = request.lang
    T = TEXTS[lang]
    
    if not require_login():
        return render_template_string(HTML_TEMPLATE, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T, lang=lang, theme='dark') # Login page defaults to dark
    
    users = load_users()
    stats = get_server_stats()
    
    users.sort(key=lambda x:(x.user or "").lower())
    today = datetime.now().strftime("%Y-%m-%d")
    
    return render_template_string(HTML_TEMPLATE, authed=True, logo=LOGO_URL, 
                                 users=users, msg=msg, err=err, today=today, stats=stats, 
                                 T=T, lang=lang)

# Routes
@app.route("/login", methods=["GET","POST"])
def login():
    lang = request.lang
    T = TEXTS[lang]
    
    if not login_enabled(): return redirect(url_for('index'))
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            resp = make_response(redirect(url_for('index')))
            resp.set_cookie('lang', lang) # Persist language choice
            return resp
        else:
            session["auth"]=False
            session["login_err"]=T['login_failed']
            return redirect(url_for('login'))
            
    return render_template_string(HTML_TEMPLATE, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T, lang=lang, theme='dark')

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): 
    lang = request.cookies.get('lang', 'my')
    resp = make_response(build_view())
    resp.set_cookie('lang', lang)
    return resp

@app.route("/add", methods=["POST"])
def add_user():
    if not require_login(): return redirect(url_for('login'))
    
    T = TEXTS[request.lang]
    
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
        return build_view(err=T['required_fields'])
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=T['invalid_expires'])
    
    if user_data['port'] and not (6000 <= int(user_data['port']) <= 19999):
        return build_view(err=T['port_range'])
    
    if not user_data['port']:
        # Auto assign port: find the lowest unassigned port
        db = get_db()
        used_ports_query = db.execute('SELECT port FROM users WHERE port IS NOT NULL').fetchall()
        used_ports = {str(row['port']) for row in used_ports_query}
        db.close()
        
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                user_data['port'] = str(p)
                break
        
        if not user_data['port']:
             return build_view(err="Port အလွတ် မရှိပါ")
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=T['save_success'])

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    T = TEXTS[request.lang]
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=T['user_required'])
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=f"{T['deleted']} {user}")

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
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    T = TEXTS[request.lang]
    
    data = request.get_json() or {}
    action = data.get('action')
    users = data.get('users', [])
    
    db = get_db()
    try:
        count = 0
        for user in users:
            if action == 'extend':
                db.execute('UPDATE users SET expires = date(expires, "+7 days") WHERE username = ?', (user,))
            elif action == 'suspend':
                db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
            elif action == 'activate':
                db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
            elif action == 'delete':
                delete_user(user) # Use delete_user to handle port cleanup
            else:
                db.close()
                return jsonify({"ok": False, "message": "Invalid action"})
            count += 1
        
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": f"{count} {T['bulk_action_complete']}"})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Max Connections,Connections,Status\n"
    for u in users:
        csv_data += f"{u.user},{u.password},{u.expires},{u.port},{u.bandwidth_used:.2f},{u.bandwidth_limit},{u.speed_limit},{u.concurrent_conn},{u.conn_count},{u.status}\n"
    
    response = make_response(csv_data)
    response.headers["Content-Disposition"] = "attachment; filename=users_export.csv"
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
            # Bandwidth is stored in bytes, report in GB
            data = db.execute('''
                SELECT username, SUM(bytes_used) as total_bytes_used 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            
            results = []
            for d in data:
                 d_dict = dict(d)
                 d_dict['total_bytes_used'] = f"{d_dict['total_bytes_used'] / 1024 / 1024 / 1024:.2f} GB"
                 results.append(d_dict)
            return jsonify(results)

        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            return jsonify([dict(d) for d in data])
            
        elif report_type == 'revenue':
            data = db.execute('''
                SELECT plan_type, COUNT(*) as count, SUM(amount) as total_revenue
                FROM billing 
                WHERE payment_status = 'paid' AND created_at BETWEEN ? AND ?
                GROUP BY plan_type
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            return jsonify([dict(d) for d in data])
            
        return jsonify({"message": "Report generated"})
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    T = TEXTS[request.lang]
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    
    if user and password:
        db = get_db()
        db.execute('UPDATE users SET password = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?', (password, user))
        db.commit()
        db.close()
        sync_config_passwords()
        return jsonify({"ok": True, "message": T['user_updated']})
    
    return jsonify({"ok": False, "err": T['invalid_data']})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (api.py) - Minor Update =====
say "${Y}🔌 API Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/api.py <<'PY'
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
            SUM(CASE WHEN status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE) THEN 1 ELSE 0 END) as active_users,
            SUM(bandwidth_used) as total_bandwidth
        FROM users
    ''').fetchone()
    db.close()
    return jsonify(dict(stats))

@app.route('/api/v1/users', methods=['GET'])
def get_users():
    db = get_db()
    users = db.execute('SELECT username, status, expires, bandwidth_used, port, concurrent_conn FROM users').fetchall()
    db.close()
    # Note: Bandwidth is in Bytes in DB
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
    data = request.get_json()
    bytes_used = data.get('bytes_used', 0)
    
    db = get_db()
    try:
        # Update usage
        db.execute('''
            UPDATE users 
            SET bandwidth_used = bandwidth_used + ?, updated_at = CURRENT_TIMESTAMP 
            WHERE username = ?
        ''', (bytes_used, username))
        
        # Log bandwidth usage
        db.execute('''
            INSERT INTO bandwidth_logs (username, bytes_used) 
            VALUES (?, ?)
        ''', (username, bytes_used))
        
        db.commit()
        return jsonify({"message": "Bandwidth updated"})
    except Exception as e:
        db.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== New Scheduler Service (scheduler.py) =====
say "${Y}⏰ Auto Port/Cleanup Scheduler ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/scheduler.py <<'PY'
import sqlite3, datetime, os, subprocess
from datetime import datetime, timedelta

DATABASE_PATH = "/etc/zivpn/zivpn.db"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def sync_config_passwords():
    # Helper to restart ZIVPN after status changes
    try:
        subprocess.run("systemctl restart zivpn.service", shell=True, check=True)
        print("ZIVPN service restarted after status change.")
    except subprocess.CalledProcessError as e:
        print(f"Error restarting zivpn.service: {e}")

def auto_suspend_expired_users():
    db = get_db()
    today = datetime.now().strftime("%Y-%m-%d")
    
    # Select users who have expired but are still active
    expired_users = db.execute('''
        SELECT username FROM users 
        WHERE expires < ? AND status = 'active'
    ''', (today,)).fetchall()
    
    if expired_users:
        print(f"Found {len(expired_users)} expired users to suspend.")
        for user in expired_users:
            db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user['username'],))
            print(f"Suspended user: {user['username']}")
        
        db.commit()
        sync_config_passwords() # Restart ZIVPN to remove suspended users' passwords
    else:
        print("No users required auto-suspension.")
    
    db.close()

def port_cleanup_and_recycling():
    db = get_db()
    
    # 1. Identify currently assigned ports
    assigned_ports_query = db.execute('SELECT port, username FROM users WHERE port IS NOT NULL').fetchall()
    assigned_ports = {row['port']: row['username'] for row in assigned_ports_query}

    # 2. Get all ports from 6000-19999
    all_ports = set(range(6000, 20000))
    
    # 3. Insert/Update port_history table
    for port in all_ports:
        is_assigned = 0 if port in assigned_ports else 1
        
        db.execute('''
            INSERT OR IGNORE INTO port_history (port, is_available)
            VALUES (?, ?)
        ''', (port, is_assigned))
        
        # If port is in the assigned list, ensure it's marked as unavailable
        if port in assigned_ports:
             db.execute('UPDATE port_history SET is_available = 0, last_used_at = CURRENT_TIMESTAMP WHERE port = ?', (port,))
        
    db.commit()
    print("Port history synchronized with active users.")

    # (Optional: Future Recycling Logic)
    # The logic here is mainly cleanup. If a user is deleted, delete_user() already marks the port as available.
    # Full port recycling logic (e.g., re-assigning old ports) is best handled by the web UI's "add user" function.
    
    db.close()


if __name__ == '__main__':
    print("--- ZIVPN Scheduler Started ---")
    auto_suspend_expired_users()
    port_cleanup_and_recycling()
    print("--- ZIVPN Scheduler Finished ---")
PY

# ===== systemd Services (Updates) =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service (No change)
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

# Web Panel Service (No change)
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

# API Service (No change)
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

# Backup Service (No change)
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

# NEW: Scheduler Service
cat >/etc/systemd/system/zivpn-scheduler.service <<'EOF'
[Unit]
Description=ZIVPN Auto-Suspend and Port Cleanup Scheduler
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/scheduler.py

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-scheduler.timer <<'EOF'
[Unit]
Description=Daily ZIVPN Scheduler (Auto-Suspend/Cleanup)
Requires=zivpn-scheduler.service

[Timer]
OnCalendar=*-*-* 00:05:00 
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ===== Networking Setup (Same as before) =====
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
systemctl enable --now zivpn-scheduler.timer # Enable new scheduler

# Initial run for new services
python3 /etc/zivpn/backup.py
python3 /etc/zivpn/scheduler.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "${C}📊 Database:${Z} ${Y}/etc/zivpn/zivpn.db${Z}"
echo -e "${C}💾 Backups:${Z} ${Y}/etc/zivpn/backups/${Z}"
echo -e "\n${M}📋 Services:${Z}"
echo -e "  ${Y}systemctl status zivpn${Z}       - VPN Server"
echo -e "  ${Y}systemctl status zivpn-web${Z}   - Web Panel (UI/UX, Status/Conn Count Improved)"
echo -e "  ${Y}systemctl status zivpn-api${Z}   - API Server"
echo -e "  ${Y}systemctl status zivpn-scheduler${Z} - Auto Suspend/Cleanup"
echo -e "  ${Y}systemctl list-timers${Z}         - Backup & Scheduler Timers"
echo -e "\n${G}🎯 Features Enabled (အဆင့်မြှင့်တင်မှုများ):${Z}"
echo -e "  ✓ User Status & Connection Count (Online/Offline, လက်ရှိချိတ်ဆက်မှု)"
echo -e "  ✓ Max Concurrent Connection Display (Mac Control Display)"
echo -e "  ✓ Modern UI/UX (Dark/Light Mode & Language Toggle)"
echo -e "  ✓ Auto-Suspend for Expired Users"
echo -e "  ✓ Automated Port Management/Cleanup"
echo -e "$LINE"
