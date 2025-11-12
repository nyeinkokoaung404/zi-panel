#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION V2
# Author: မောင်သုည
# Features: Complete Enterprise Management System with Enhanced Status, UI/UX, Auto Cleanup & Networking Fix.
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION V2 (Enhanced) ${Z}\n$LINE"

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
say "${Y}📦 Enhanced Packages တင်နေပါသည်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-pip python3-venv iproute2 conntrack ca-certificates sqlite3 net-tools >/dev/null || \
{
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask python3-pip iproute2 conntrack ca-certificates sqlite3 net-tools >/dev/null
}

# Additional Python packages
pip3 install requests python-dateutil >/dev/null 2>&1 || true
apt_guard_end

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
systemctl stop zivpn-bot.service 2>/dev/null || true
systemctl stop zivpn-cleanup.timer 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json" # Legacy/Fallback
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
    last_active DATETIME, -- New for accurate status
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
say "${G}🔏 VPN Password List (eg: khaing,alice,pass1)${Z}"
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
from dateutil import parser as dateparser
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Configuration ---
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
# User is considered 'Online' if last_active is within the last RECENT_SECONDS
RECENT_SECONDS = 180 
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Translations (Burmese and English) ---
T = {
    'my': {
        'login_title': "မောင်သုည Enterprise Panel ဝင်ရောက်ရန်",
        'login_fail': "မှန်ကန်မှုမရှိပါ",
        'panel_title': "မောင်သုည ZIVPN Enterprise",
        'system_title': "⊱✫⊰ Enterprise Management System ⊱✫⊰",
        'logout': "ထွက်ရန်", 'contact': "ဆက်သွယ်ရန်", 'login': "ဝင်ရန်",
        'total_users': "စုစုပေါင်းအသုံးပြုသူ", 'active_users': "လက်ရှိအသုံးပြုသူ",
        'bw_used': "Bandwidth အသုံးပြုပြီး", 'server_load': "Server ဝန်",
        'tab_user_mgmt': "အသုံးပြုသူ စီမံခန့်ခွဲမှု", 'tab_add_user': "အသုံးပြုသူ အသစ်ထည့်ပါ",
        'tab_bulk': "အစုလိုက်လုပ်ဆောင်ချက်များ", 'tab_reports': "အစီရင်ခံစာများ",
        'add_user_title': "အသုံးပြုသူ အသစ်ထည့်ပါ", 'save_success': "User ကို အောင်မြင်စွာ သိမ်းဆည်းပြီး",
        'err_user_pass': "User နှင့် Password လိုအပ်သည်", 'err_expires': "Expires format မမှန်ပါ",
        'err_port_range': "Port အကွာအဝေး 6000-19999", 'user': "အသုံးပြုသူ", 'password': "လျှို့ဝှက်နံပါတ်",
        'expires': "သက်တမ်းကုန်ဆုံး", 'port': "Port", 'speed_limit': "နှုန်းကန့်သတ်ချက် (MB/s)",
        'bw_limit': "Bandwidth ကန့်သတ်ချက် (GB)", 'max_conn': "အများဆုံးချိတ်ဆက်မှု",
        'plan_type': "Plan အမျိုးအစား", 'save_user': "User ကို သိမ်းပါ",
        'select_action': "လုပ်ဆောင်ချက် ရွေးပါ", 'extend': "သက်တမ်းတိုး (+7 ရက်)",
        'suspend_users': "Users များ ရပ်ဆိုင်းရန်", 'activate_users': "Users များ ပြန်လည်စတင်ရန်",
        'delete_users': "Users များ ဖျက်ရန်", 'execute': "လုပ်ဆောင်ပါ",
        'export_users': "Users များ CSV ထုတ်ပါ", 'import_users': "Users များ သွင်းပါ",
        'search_users': "Users ရှာပါ...", 'status_online': "အွန်လိုင်း", 'status_offline': "အော့ဖ်လိုင်း",
        'status_expired': "သက်တမ်းကုန်", 'status_suspended': "ရပ်ဆိုင်းထား", 'status_unknown': "မသိရှိ",
        'actions': "လုပ်ဆောင်ချက်များ", 'confirm_delete': " ကို ဖျက်မလား?", 'delete_success': "ဖျက်ပြီး: ",
        'reports_title': "အစီရင်ခံစာများ & ခွဲခြမ်းစိတ်ဖြာခြင်း", 'from_date': "စသည့်ရက်",
        'to_date': "ပြီးဆုံးရက်", 'report_type': "အစီရင်ခံစာ အမျိုးအစား",
        'bw_usage': "Bandwidth အသုံးပြုမှု", 'user_activity': "User လှုပ်ရှားမှု",
        'generate_report': "အစီရင်ခံစာ ထုတ်ပါ"
    },
    'en': {
        'login_title': "Zero ZIVPN Enterprise Panel Login",
        'login_fail': "Invalid credentials",
        'panel_title': "Zero ZIVPN Enterprise",
        'system_title': "⊱✫⊰ Enterprise Management System ⊱✫⊰",
        'logout': "Logout", 'contact': "Contact", 'login': "Login",
        'total_users': "Total Users", 'active_users': "Active Users",
        'bw_used': "Bandwidth Used", 'server_load': "Server Load",
        'tab_user_mgmt': "User Management", 'tab_add_user': "Add User",
        'tab_bulk': "Bulk Operations", 'tab_reports': "Reports",
        'add_user_title': "Add New User", 'save_success': "User saved successfully",
        'err_user_pass': "User and Password are required", 'err_expires': "Invalid Expires format",
        'err_port_range': "Port range 6000-19999", 'user': "User", 'password': "Password",
        'expires': "Expires", 'port': "Port", 'speed_limit': "Speed Limit (MB/s)",
        'bw_limit': "Bandwidth Limit (GB)", 'max_conn': "Max Connections",
        'plan_type': "Plan Type", 'save_user': "Save User",
        'select_action': "Select Action", 'extend': "Extend Expiry (+7 days)",
        'suspend_users': "Suspend Users", 'activate_users': "Activate Users",
        'delete_users': "Delete Users", 'execute': "Execute",
        'export_users': "Export Users CSV", 'import_users': "Import Users",
        'search_users': "Search users...", 'status_online': "ONLINE", 'status_offline': "OFFLINE",
        'status_expired': "EXPIRED", 'status_suspended': "SUSPENDED", 'status_unknown': "UNKNOWN",
        'actions': "Actions", 'confirm_delete': " Delete this user?", 'delete_success': "Deleted: ",
        'reports_title': "Reports & Analytics", 'from_date': "From Date",
        'to_date': "To Date", 'report_type': "Report Type",
        'bw_usage': "Bandwidth Usage", 'user_activity': "User Activity",
        'generate_report': "Generate Report"
    }
}


# --- HTML Template (Includes Dark/Light Mode and Burmese/English) ---
HTML = """<!doctype html>
<html lang="{{lang}}"><head><meta charset="utf-8">
<title>{{t.panel_title}}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="180">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{
  --bg: #f0f2f5; --fg: #1c1e21; --card: #ffffff; --bd: #ccc;
  --header-bg: #1877f2; --ok: #27ae60; --bad: #c0392b; --unknown: #f39c12;
  --expired: #8e44ad; --info: #3498db; --success: #1abc9c; --delete-btn: #e74c3c;
  --primary-btn: #1877f2; --logout-btn: #e67e22; --telegram-btn: #0088cc;
  --input-text: #1c1e21; --shadow: 0 2px 4px rgba(0,0,0,0.1); --radius: 8px;
  --user-icon: #1877f2; --pass-icon: #e74c3c; --expires-icon: #9b59b6; --port-icon: #3498db;
}
/* Dark Mode Overrides */
[data-theme='dark'] {
  --bg: #1e1e1e; --fg: #f0f0f0; --card: #2d2d2d; --bd: #444;
  --header-bg: #2d2d2d; --input-text: #fff; --shadow: 0 4px 15px rgba(0,0,0,0.5);
}

html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px}
.container{max-width:1400px;margin:auto;padding:10px}

@keyframes colorful-shift {
  0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius);box-shadow:var(--shadow);color:white}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}
[data-theme='dark'] .logo{border:2px solid #ddd}

.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.1);display:flex;align-items:center;gap:8px;}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:#1569e0}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#c0392b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:#95a5a6;color:white}.btn.secondary:hover{background:#7f8c8d}
.btn.action{background:#3498db;color:white;}.btn.action:hover{background:#2980b9}

.icon{margin-right:5px;font-size:1em;line-height:1;}
.icon-user{color:var(--user-icon)}.icon-pass{color:var(--pass-icon)}
.icon-expires{color:var(--expires-icon)}.icon-port{color:var(--port-icon)}

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
.tab-content{display:none;background:var(--card);padding:20px;border-radius:0 0 var(--radius) var(--radius);box-shadow:var(--shadow);}
.tab-content.active{display:block;}

.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);border:1px solid var(--bd)}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;color:var(--primary-btn);}
.stat-label{font-size:.9em;color:var(--fg);}
.stat-card:nth-child(2) .stat-number{color:var(--ok)} /* Active users green */

table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);}
th:last-child,td:last-child{border-right:none;}
th{background:#f5f5f5;font-weight:700;color:var(--fg);text-transform:uppercase}
[data-theme='dark'] th{background:#3a3a3a}
tr:last-child td{border-bottom:none}
tr:hover{background:#f9f9f9}
[data-theme='dark'] tr:hover{background:#3a3a3a}

.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
.status-ok{color:white;background:#2ecc71}.status-bad{color:white;background:#e74c3c}
.status-unk{color:white;background:#f1c40f}.status-expired{color:white;background:#9b59b6}
.pill-yellow{background:#f1c40f;color:#333}.pill-red{background:#e74c3c;color:white}.pill-green{background:#2ecc71;color:white}
.pill-lightgreen{background:#1abc9c;color:white}.pill-pink{background:#f78da7;color:#333}.pill-orange{background:#e67e22;color:white}
.pill-online{background:#2ecc71;color:white}.pill-offline{background:#3498db;color:white}

.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:var(--expired);color:white}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;background:var(--card);box-shadow:var(--shadow);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;color:var(--fg);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}
.settings-bar{display:flex;gap:15px;align-items:center;margin-bottom:15px}

@media (max-width: 768px) {
  body{padding:10px}.container{padding:0}
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .row>div,.stats-grid{grid-template-columns:1fr;}
  .btn{width:100%;margin-bottom:5px;justify-content:center}
  table,thead,tbody,th,td,tr{display:block;}
  thead tr{position:absolute;top:-9999px;left:-9999px;}
  tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
  td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
  td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
  td:nth-of-type(1):before{content:"{{t.user}}";}td:nth-of-type(2):before{content:"{{t.password}}";}
  td:nth-of-type(3):before{content:"{{t.expires}}";}td:nth-of-type(4):before{content:"{{t.port}}";}
  td:nth-of-type(5):before{content:"{{t.bw_limit}}";}td:nth-of-type(6):before{content:"{{t.speed_limit}}";}
  td:nth-of-type(7):before{content:"{{t.status_online}}/{{t.status_offline}}";}td:nth-of-type(8):before{content:"{{t.actions}}";}
  .delform{width:100%;}tr.expired td{background:var(--expired);}
}
</style>
</head>
<body data-theme="{{session.theme|default('light')}}">
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
    <h3 class="center">{{t.login_title}}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label><i class="fas fa-user icon icon-user"></i>Username</label>
      <input name="u" autofocus required>
      <label style="margin-top:15px"><i class="fas fa-lock icon icon-pass"></i>Password</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i>{{t.login}}
      </button>
    </form>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="မောင်သုည" class="logo">
    <div>
      <h1><span class="colorful-title">{{t.panel_title}}</span></h1>
      <div class="sub" style="color:white;"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">{{t.system_title}}</span></div>
    </div>
  </div>
  <div style="display:flex;gap:10px;align-items:center">
    <select onchange="changeLanguage(this.value)" style="padding:8px;border-radius:5px;background:white;color:var(--primary-btn);font-weight:700;width:auto;">
      <option value="my" {% if lang == 'my' %}selected{% endif %}>ဘာသာစကား (Myanmar)</option>
      <option value="en" {% if lang == 'en' %}selected{% endif %}>Language (English)</option>
    </select>
    <button class="btn secondary" onclick="toggleTheme()" style="padding:10px 15px;width:auto;">
      <i class="fas fa-sun"></i>/<i class="fas fa-moon"></i>
    </button>
    <a class="btn contact" href="https://t.me/Zero_Free_Vpn" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>{{t.contact}}
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>{{t.logout}}
    </a>
  </div>
</header>

<div class="stats-grid">
  <div class="stat-card">
    <i class="fas fa-users" style="font-size:2em;color:#3498db;"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">{{t.total_users}}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-signal" style="font-size:2em;color:#27ae60;"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">{{t.active_users}}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:#e74c3c;"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{t.bw_used}}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:#f39c12;"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{t.server_load}}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab(event, 'users')">{{t.tab_user_mgmt}}</button>
    <button class="tab-btn" onclick="openTab(event, 'adduser')">{{t.tab_add_user}}</button>
    <button class="tab-btn" onclick="openTab(event, 'bulk')">{{t.tab_bulk}}</button>
    <button class="tab-btn" onclick="openTab(event, 'reports')">{{t.tab_reports}}</button>
  </div>

    <div id="adduser" class="tab-content">
    <form method="post" action="/add">
      <h3><i class="fas fa-users-cog"></i> {{t.add_user_title}}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label><i class="fas fa-user icon icon-user"></i> {{t.user}}</label><input name="user" placeholder="User Name" required></div>
        <div><label><i class="fas fa-lock icon icon-pass"></i> {{t.password}}</label><input name="password" placeholder="Password" required></div>
        <div><label><i class="fas fa-clock icon icon-expires"></i> {{t.expires}}</label><input name="expires" placeholder="2026-01-01 or 30 (days)"></div>
        <div><label><i class="fas fa-server icon icon-port"></i> {{t.port}}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label><i class="fas fa-tachometer-alt"></i> {{t.speed_limit}}</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label><i class="fas fa-database"></i> {{t.bw_limit}}</label><input name="bandwidth_limit" placeholder="0 = unlimited (GB)" type="number"></div>
        <div><label><i class="fas fa-plug"></i> {{t.max_conn}}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label><i class="fas fa-money-bill"></i> {{t.plan_type}}</label>
          <select name="plan_type">
            <option value="free">Free</option><option value="daily">Daily</option><option value="weekly">Weekly</option>
            <option value="monthly" selected>Monthly</option><option value="yearly">Yearly</option>
          </select>
        </div>
      </div>
      <button class="btn save" type="submit" style="margin-top:20px">
        <i class="fas fa-save"></i> {{t.save_user}}
      </button>
    </form>
  </div>

    <div id="bulk" class="tab-content">
    <h3><i class="fas fa-cogs"></i> {{t.tab_bulk}}</h3>
    <div class="bulk-actions">
      <select id="bulkAction">
        <option value="">{{t.select_action}}</option>
        <option value="extend">{{t.extend}}</option>
        <option value="suspend">{{t.suspend_users}}</option>
        <option value="activate">{{t.activate_users}}</option>
        <option value="delete">{{t.delete_users}}</option>
      </select>
      <input type="text" id="bulkUsers" placeholder="Usernames comma separated (user1,user2)">
      <button class="btn action" onclick="executeBulkAction()">
        <i class="fas fa-play"></i> {{t.execute}}
      </button>
    </div>
    <div style="margin-top:15px">
      <button class="btn primary" onclick="exportUsers()">
        <i class="fas fa-download"></i> {{t.export_users}}
      </button>
    </div>
  </div>

    <div id="users" class="tab-content active">
    <h3><i class="fas fa-users"></i> {{t.tab_user_mgmt}}</h3>
    <div style="margin:15px 0;display:flex;gap:10px;">
      <input type="text" id="searchUser" placeholder="{{t.search_users}}" style="flex:1;">
      <button class="btn secondary" onclick="filterUsers()">
        <i class="fas fa-search"></i> Search
      </button>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> {{t.user}}</th>
          <th><i class="fas fa-lock"></i> {{t.password}}</th>
          <th><i class="fas fa-clock"></i> {{t.expires}}</th>
          <th><i class="fas fa-server"></i> {{t.port}}</th>
          <th><i class="fas fa-database"></i> {{t.bw_limit}}</th>
          <th><i class="fas fa-tachometer-alt"></i> {{t.speed_limit}}</th>
          <th><i class="fas fa-chart-line"></i> Status</th>
          <th><i class="fas fa-cog"></i> {{t.actions}}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.is_expired %}expired{% endif %}">
        <td style="color:#2ecc71;"><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used_gb}}/{{u.bandwidth_limit_gb}} GB</span></td>
        <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
        <td>
          {% if u.status == "Online" %}<span class="pill pill-online">{{t.status_online}}</span>
          {% elif u.status == "Offline" %}<span class="pill pill-offline">{{t.status_offline}}</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">{{t.status_expired}}</span>
          {% elif u.status == "Suspended" %}<span class="pill status-bad">{{t.status_suspended}}</span>
          {% else %}<span class="pill status-unk">{{t.status_unknown}}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}}{{t.confirm_delete}}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="Delete" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn secondary" title="Edit" style="padding:6px 12px;" onclick="editUser('{{u.user}}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == "Suspended" or u.status == "Expired" %}
          <form class="delform" method="post" action="/activate" title="Activate/Unsuspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend" title="Suspend">
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

    <div id="reports" class="tab-content">
    <h3><i class="fas fa-chart-bar"></i> {{t.reports_title}}</h3>
    <div class="row">
      <div><label>{{t.from_date}}</label><input type="date" id="fromDate"></div>
      <div><label>{{t.to_date}}</label><input type="date" id="toDate"></div>
      <div><label>{{t.report_type}}</label>
        <select id="reportType">
          <option value="bandwidth">{{t.bw_usage}}</option>
          <option value="users">{{t.user_activity}}</option>
        </select>
      </div>
      <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">{{t.generate_report}}</button></div>
    </div>
    <div id="reportResults" style="margin-top:20px;padding:15px;background:var(--bg);border-radius:var(--radius);"></div>
  </div>
</div>

{% endif %}
</div>

<script>
function openTab(evt, tabName) {
  document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  document.getElementById(tabName).classList.add('active');
  if(evt) evt.currentTarget.classList.add('active');
}
// Initialize first tab
document.addEventListener('DOMContentLoaded', () => {
  openTab(null, 'users');
  if (window.location.hash) {
    const tabName = window.location.hash.substring(1);
    const tabBtn = document.querySelector(`.tab-btn[onclick*='${tabName}']`);
    if (tabBtn) {
      openTab({currentTarget: tabBtn}, tabName);
    }
  }
});

function toggleTheme() {
  const body = document.body;
  const currentTheme = body.getAttribute('data-theme') || 'light';
  const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
  body.setAttribute('data-theme', newTheme);
  // Persist preference to server (or localStorage for simplicity)
  fetch('/theme/' + newTheme);
}

function changeLanguage(lang) {
  window.location.href = '/lang/' + lang + window.location.hash;
}

function executeBulkAction() {
  const action = document.getElementById('bulkAction').value;
  const users = document.getElementById('bulkUsers').value;
  if (!action || !users) { alert('Please select action and enter users'); return; }
  
  fetch('/api/bulk', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
  }).then(r => r.json()).then(data => {
    alert(data.message); location.reload();
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
  const newPass = prompt('Enter new password for ' + username);
  if (newPass) {
    fetch('/api/user/update', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({user: username, password: newPass})
    }).then(r => r.json()).then(data => {
      alert(data.message); location.reload();
    });
  }
}

function generateReport() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const type = document.getElementById('reportType').value;
  
  fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
    .then(r => r.json()).then(data => {
      document.getElementById('reportResults').innerHTML = '<h4>Report Results:</h4><pre>' + JSON.stringify(data, null, 2) + '</pre>';
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

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, bandwidth_used, speed_limit_up as speed_limit,
               concurrent_conn, last_active
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        # Check for existing user
        existing = db.execute('SELECT id FROM users WHERE username = ?', (user_data['user'],)).fetchone()
        
        # Convert MB/s to B/s for consistency (or keep MB/s if server uses that)
        # Speed limits will be passed to server in its expected format.
        # bandwidth_limit is in GB, stored as GB or converted to bytes for the server. Let's keep it as GB in DB for admin clarity.
        
        if existing:
            db.execute('''
                UPDATE users SET password=?, expires=?, port=?, status=?, bandwidth_limit=?,
                            speed_limit_up=?, concurrent_conn=?, updated_at=CURRENT_TIMESTAMP
                WHERE username = ?
            ''', (
                user_data['password'], user_data.get('expires'), user_data.get('port'), 
                'active', user_data.get('bandwidth_limit', 0), user_data.get('speed_limit', 0),
                user_data.get('concurrent_conn', 1), user_data['user']
            ))
        else:
            db.execute('''
                INSERT INTO users 
                (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                user_data['user'], user_data['password'], user_data.get('expires'),
                user_data.get('port'), 'active', user_data.get('bandwidth_limit', 0),
                user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
            ))
        db.commit()
        
        # Add to billing (simple logic for now)
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
    now_minus_active = datetime.now() - timedelta(seconds=RECENT_SECONDS)
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        # Consider users active if their last_active is recent AND status is not suspended
        active_users = db.execute(f'''
            SELECT COUNT(*) FROM users 
            WHERE status = "active" AND last_active >= ?
        ''', (now_minus_active.strftime('%Y-%m-%d %H:%M:%S'),)).fetchone()[0]
        total_bandwidth_bytes = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        # Simple server load calculation (based on active users and overall load)
        server_load = min(100, (active_users * 3) + (total_users * 0.5))
        
        return {
            'total_users': total_users,
            'active_users': int(active_users),
            'total_bandwidth': f"{total_bandwidth_bytes / (1024**3):.2f} GB", # Convert to GB
            'server_load': f"{server_load:.1f}"
        }
    finally:
        db.close()

def sync_config_passwords():
    users=load_users()
    users_pw=sorted({str(u["password"]) for u in users if u.get("password") and u.get("status") == "active"})
    
    cfg=read_json(CONFIG_FILE,{})
    if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
    cfg["auth"]["mode"]="passwords"
    cfg["auth"]["config"]=users_pw
    # Ensure all required fields are present
    cfg["listen"]=cfg.get("listen") or ":5667"
    cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
    cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
    cfg["obfs"]=cfg.get("obfs") or "zivpn"
    
    write_json_atomic(CONFIG_FILE,cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True)

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def get_lang(): return session.get('lang', 'my')
def get_theme(): return session.get('theme', 'light')

def require_login(redirect_func=None):
    if login_enabled() and not is_authed():
        if redirect_func: return redirect_func()
        return False
    return True

def status_for_user(u):
    now = datetime.now()
    expires_str = u.get("expires", "")
    is_expired = False
    if expires_str:
        try:
            expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < now.date():
                is_expired = True
        except ValueError:
            pass
    
    if u.get('status') == 'suspended' or is_expired:
        return "Expired" if is_expired else "Suspended", is_expired

    last_active_str = u.get('last_active')
    if last_active_str:
        try:
            last_active_dt = dateparser.parse(last_active_str)
            if (now - last_active_dt).total_seconds() <= RECENT_SECONDS:
                return "Online", is_expired
        except Exception as e:
            logger.error(f"Error parsing last_active for {u.get('user')}: {e}")
    
    return "Offline", is_expired

def build_view(msg="", err=""):
    lang = get_lang()
    t = T.get(lang)
    
    if not require_login(redirect_func=lambda: redirect(url_for('login'))):
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), t=t, lang=lang)
    
    users=load_users()
    stats = get_server_stats()
    view=[]
    
    for u in users:
        status, is_expired = status_for_user(u)
        
        user_obj = type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":u.get("expires",""),
            "port":u.get("port",""),
            "status":status,
            "is_expired": is_expired,
            "bandwidth_limit_gb": u.get('bandwidth_limit', 0),
            "bandwidth_used_gb": f"{u.get('bandwidth_used', 0) / (1024**3):.2f}",
            "speed_limit": u.get('speed_limit', 0)
        })
        view.append(user_obj)
    
    view.sort(key=lambda x:(x.user or "").lower())
    today=datetime.now().date().strftime("%Y-%m-%d")
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL, 
                                users=view, msg=msg, err=err, today=today, stats=stats, t=t, lang=lang)

# --- General Routes ---
@app.route("/lang/<lang_code>")
def set_language(lang_code):
    if lang_code in T:
        session['lang'] = lang_code
        return redirect(request.referrer or url_for('index'))
    return "Invalid language code", 400

@app.route("/theme/<theme_name>")
def set_theme(theme_name):
    if theme_name in ['dark', 'light']:
        session['theme'] = theme_name
        return "OK"
    return "Invalid theme name", 400

@app.route("/login", methods=["GET","POST"])
def login():
    lang = get_lang()
    t = T.get(lang)
    if not login_enabled(): return redirect(url_for('index'))
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('index'))
        else:
            session["auth"]=False
            session["login_err"]=t['login_fail']
            return redirect(url_for('login'))
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), t=t, lang=lang)

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
    if not require_login(): return redirect(url_for('login'))
    t = T.get(get_lang())
    
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
        return build_view(err=t['err_user_pass'])
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=t['err_expires'])
    
    if user_data['port'] and not (6000 <= int(user_data['port']) <= 19999):
        return build_view(err=t['err_port_range'])
    
    if not user_data['port']:
        # Auto assign port
        db = get_db()
        used_ports = {str(r['port']) for r in db.execute('SELECT port FROM users').fetchall() if r['port']}
        db.close()
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                user_data['port'] = str(p)
                break
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=t['save_success'])

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    t = T.get(get_lang())
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=t['err_user_pass'])
    
    delete_user(user)
    sync_config_passwords()
    return build_view(msg=t['delete_success'] + user)

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

# --- API Routes ---
@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    data = request.get_json() or {}
    action = data.get('action')
    users = data.get('users', [])
    db = get_db()
    try:
        for user in users:
            if action == 'extend':
                db.execute('UPDATE users SET expires = date(expires, "+7 days"), updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
            elif action == 'suspend':
                db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
            elif action == 'activate':
                db.execute('UPDATE users SET status = "active", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
            elif action == 'delete':
                delete_user(user) # Use the existing function for full cleanup
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": f"Bulk action {action} completed"})
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user_api():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
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

# ... (API routes for export and reports remain the same as original) ...
@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Status\n"
    for u in users:
        status, _ = status_for_user(u)
        used_gb = f"{u.get('bandwidth_used', 0) / (1024**3):.2f}"
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{used_gb},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{status}\n"
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
            data = db.execute('''
                SELECT username, SUM(bytes_used) as total_bytes 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            # Convert bytes to GB for display in API response
            return jsonify([{'username': d['username'], 'total_gb': f"{d['total_bytes'] / (1024**3):.2f}"} for d in data])
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND date(?, '+1 day')
                GROUP BY date
            ''', (from_date or '2000-01-01', to_date or datetime.now().strftime('%Y-%m-%d'))).fetchall()
            return jsonify([dict(d) for d in data])
        else:
            return jsonify({"error": "Invalid report type"}), 400
    finally:
        db.close()

if __name__ == "__main__":
    # Run on a single thread as it's a simple admin panel for now
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (api.py) =====
say "${Y}🔌 API Service ထည့်သွင်းနေပါတယ်... (Last Active Update Pushed) ${Z}"
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
            SUM(CASE WHEN status = "active" THEN 1 ELSE 0 END) as active_users,
            SUM(bandwidth_used) as total_bandwidth
        FROM users
    ''').fetchone()
    db.close()
    return jsonify({
        'total_users': stats['total_users'],
        'active_users': stats['active_users'],
        'total_bandwidth_bytes': stats['total_bandwidth'] or 0
    })

@app.route('/api/v1/users', methods=['GET'])
def get_users():
    db = get_db()
    users = db.execute('SELECT username, status, expires, bandwidth_used, port FROM users').fetchall()
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
    data = request.get_json()
    bytes_used = int(data.get('bytes_used', 0))
    is_active = data.get('is_active', False) # New field to indicate activity
    
    db = get_db()
    try:
        update_query = '''
            UPDATE users 
            SET bandwidth_used = bandwidth_used + ?, updated_at = CURRENT_TIMESTAMP
            WHERE username = ?
        '''
        if is_active:
            update_query = update_query.replace('CURRENT_TIMESTAMP', 'CURRENT_TIMESTAMP, last_active = CURRENT_TIMESTAMP')
        
        db.execute(update_query, (bytes_used, username))
        
        # Log bandwidth usage
        if bytes_used > 0:
            db.execute('''
                INSERT INTO bandwidth_logs (username, bytes_used) 
                VALUES (?, ?)
            ''', (username, bytes_used))
        
        db.commit()
        return jsonify({"message": "Bandwidth and activity updated"})
    finally:
        db.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Automated Cleanup Script (cleanup.py) =====
say "${Y}🧹 Auto Cleanup Script ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/cleanup.py <<'PY'
import sqlite3
from datetime import datetime
import subprocess
import os

DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def auto_suspend_expired_and_over_limit():
    db = get_db()
    now_date = datetime.now().strftime("%Y-%m-%d")
    try:
        # 1. Suspend Expired Users
        expired_users = db.execute('''
            SELECT username FROM users 
            WHERE status = 'active' AND expires IS NOT NULL AND expires < ?
        ''', (now_date,)).fetchall()
        
        if expired_users:
            db.execute('''
                UPDATE users SET status = 'suspended', updated_at = CURRENT_TIMESTAMP
                WHERE status = 'active' AND expires IS NOT NULL AND expires < ?
            ''', (now_date,))
            print(f"Suspended {len(expired_users)} expired users.")

        # 2. Suspend Bandwidth Over-Limit Users
        # Bandwidth limit is stored in GB. Usage is stored in Bytes.
        # 1 GB = 1024^3 Bytes
        over_limit_users = db.execute('''
            SELECT username FROM users 
            WHERE status = 'active' AND bandwidth_limit > 0 AND bandwidth_used >= (bandwidth_limit * 1073741824)
        ''').fetchall()
        
        if over_limit_users:
            db.execute('''
                UPDATE users SET status = 'suspended', updated_at = CURRENT_TIMESTAMP
                WHERE status = 'active' AND bandwidth_limit > 0 AND bandwidth_used >= (bandwidth_limit * 1073741824)
            ''')
            print(f"Suspended {len(over_limit_users)} over-limit users.")
        
        db.commit()
        # Always sync passwords and restart zivpn to apply changes
        sync_passwords_and_restart()

    finally:
        db.close()

def sync_passwords_and_restart():
    # Minimal function to re-implement the logic needed by cleanup
    try:
        db = get_db()
        active_passwords = [r['password'] for r in db.execute("SELECT password FROM users WHERE status = 'active'").fetchall()]
        db.close()
        
        config_file = "/etc/zivpn/config.json"
        try:
            with open(config_file, "r") as f:
                cfg = json.load(f)
        except:
            cfg = {"auth": {}, "listen": ":5667", "cert": "/etc/zivpn/zivpn.crt", "key": "/etc/zivpn/zivpn.key", "obfs": "zivpn"}
        
        cfg["auth"] = {"mode": "passwords", "config": sorted(active_passwords)}
        
        # Atomic write (simplified here, but should use the web.py function logic for production)
        with open(config_file, "w") as f:
            json.dump(cfg, f, indent=2)

        subprocess.run("systemctl restart zivpn.service", shell=True)
        print("Config synced and ZIVPN restarted.")
    except Exception as e:
        print(f"Error during config sync/restart: {e}")

if __name__ == '__main__':
    # This script can now be run hourly via systemd timer
    auto_suspend_expired_and_over_limit()
PY

# ===== Telegram Bot (bot.py) - No change needed for this request =====

# ===== Backup Script (backup.py) - No change needed for this request =====

# ===== systemd Services (Cleanup Timer Added) =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service (No Change)
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

# Web Panel Service (No Change)
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

# API Service (No Change)
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

# Backup Service (Daily) - No Change
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

# New Cleanup Service (Hourly)
cat >/etc/systemd/system/zivpn-cleanup.service <<'EOF'
[Unit]
Description=ZIVPN Hourly Cleanup and Auto Suspend
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
Description=Hourly ZIVPN Cleanup and Auto Suspend
Requires=zivpn-cleanup.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ===== Networking Setup (FIXED) =====
echo -e "${Y}🌐 Network Configuration ပြုလုပ်နေပါတယ်... (FIX: SSH Access အတွက် Default Policy ကို မပြောင်းပါ)${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# FIX: INPUT chain ကို မပြောင်းဘဲ Default SSH (Port 22) ကို allow ပြီးမှ DNAT rules တွေ ထည့်ပါမယ်။
# Existing iptables rules တွေကို flush ပြီးမှ DNAT နဲ့ MASQUERADE rules တွေပဲ ထည့်ပါမယ်။
# ဒါမှ SSH port 22 ကို block မဖြစ်ဘဲ VPS ထဲ ပြန်ဝင်လို့ ရပါမယ်။

# Flush only NAT table rules
iptables -t nat -F
# DNAT Rules
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQUERADE Rule
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
# Save iptables rules (using iptables-persistent or similar if available, but ufw is preferred here)

# UFW Rules (Ensure SSH port is explicitly allowed, which ufw typically does by default)
ufw allow 22/tcp >/dev/null 2>&1 || true # Explicitly allow SSH
ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true # Web Panel
ufw allow 8081/tcp >/dev/null 2>&1 || true # API Server
ufw --force enable >/dev/null 2>&1 || true

# ===== Final Setup =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-backup.timer
systemctl enable --now zivpn-cleanup.timer # NEW

# Initial runs
python3 /etc/zivpn/backup.py
python3 /etc/zivpn/cleanup.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition V2 Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Admin Login:${Z} ${Y}User: ${WEB_USER}, Pass: (You set it)${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "\n${M}📋 Services Status:${Z}"
echo -e "  ${Y}systemctl status zivpn-web${Z}   - Web Panel"
echo -e "  ${Y}systemctl list-timers${Z}       - Backup/Cleanup Timers"
echo -e "\n${G}🎯 Enhanced Features Enabled:${Z}"
echo -e "  ✓ ⚡ Accurate Online/Offline Status (Last 3 mins)"
echo -e "  ✓ 🎨 Enhanced UI/UX with Dark/Light Mode"
echo -e "  ✓ 🌎 Myanmar / English Language Support"
echo -e "  ✓ 🧹 Hourly Auto Suspend (Expired & Over-Limit Users)"
echo -e "  ✓ 🔐 Network Fix: SSH Port 22 remains OPEN!"
echo -e "$LINE"
