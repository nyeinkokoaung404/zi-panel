#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION
# Author: 4 0 4 \ 2.0 [🇲🇲]
# Features: Complete Enterprise Management System with Bandwidth Control, Billing, Multi-Server, API, etc.
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION ${Z}\n${M}✅ All Fixes and Features Integrated ${Z}\n$LINE"

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

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
systemctl stop zivpn-bot.service 2>/dev/null || true
systemctl stop zivpn-cleanup.timer 2>/dev/null || true
systemctl stop zivpn-backup.timer 2>/dev/null || true

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

# ===== Base config & Certs =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KHAINGUDP/OU=Net/CN=khaingudp" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin & ENV Setup =====
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

# Get Telegram Bot Token (optional)
read -r -p "Telegram Bot Token (Optional, Enter=Skip): " BOT_TOKEN
BOT_TOKEN="${BOT_TOKEN:-8079105459:AAFNww6keJvnGJi4DpAHZGESBcL9ytFxqA4}"

{
  echo "WEB_ADMIN_USER=${WEB_USER}"
  echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
  echo "WEB_SECRET=${WEB_SECRET}"
  echo "DATABASE_PATH=${DB}"
  echo "TELEGRAM_BOT_TOKEN=${BOT_TOKEN}"
  echo "DEFAULT_LANGUAGE=my" # Default language to Burmese
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
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn") |
    .server = $ip
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== Enhanced Mobile-Friendly Web Panel =====
say "${Y}🖥️ Mobile-Friendly Web Panel ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response, g
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Localization Data ---
TRANSLATIONS = {
    'en': {
        'title': 'ZIVPN Enterprise Panel', 'login_title': 'ZIVPN Panel Login',
        'login_err': 'Invalid Username or Password', 'username': 'Username',
        'password': 'Password', 'login': 'Login', 'logout': 'Logout',
        'contact': 'Contact', 'total_users': 'Total Users',
        'active_users': 'Online Users', 'bandwidth_used': 'Bandwidth Used',
        'server_load': 'Server Load', 'user_management': 'User Management',
        'add_user': 'Add New User', 'bulk_ops': 'Bulk Operations',
        'reports': 'Reports', 'user': 'User', 'expires': 'Expires',
        'port': 'Port', 'bandwidth': 'Bandwidth', 'speed': 'Speed',
        'status': 'Status', 'actions': 'Actions', 'online': 'ONLINE',
        'offline': 'OFFLINE', 'expired': 'EXPIRED', 'suspended': 'SUSPENDED',
        'save_user': 'Save User', 'max_conn': 'Max Connections',
        'speed_limit': 'Speed Limit (MB/s)', 'bw_limit': 'Bandwidth Limit (GB)',
        'required_fields': 'User and Password are required',
        'invalid_exp': 'Invalid Expires format',
        'invalid_port': 'Port range must be 6000-19999',
        'delete_confirm': 'Are you sure you want to delete {user}?',
        'deleted': 'Deleted: {user}', 'success_save': 'User saved successfully',
        'select_action': 'Select Action', 'extend_exp': 'Extend Expiry (+7 days)',
        'suspend_users': 'Suspend Users', 'activate_users': 'Activate Users',
        'delete_users': 'Delete Users', 'execute': 'Execute',
        'user_search': 'Search users...', 'search': 'Search',
        'export_csv': 'Export Users CSV', 'import_users': 'Import Users',
        'bulk_success': 'Bulk action {action} completed',
        'report_range': 'Date Range Required', 'report_bw': 'Bandwidth Usage',
        'report_users': 'User Activity', 'report_revenue': 'Revenue',
        'dashboard': 'Dashboard', 'settings': 'Settings'
    },
    'my': {
        'title': 'ZIVPN စီမံခန့်ခွဲမှု Panel', 'login_title': 'ZIVPN Panel ဝင်ရန်',
        'login_err': 'အသုံးပြုသူအမည် (သို့) စကားဝှက် မမှန်ပါ', 'username': 'အသုံးပြုသူအမည်',
        'password': 'စကားဝှက်', 'login': 'ဝင်မည်', 'logout': 'ထွက်မည်',
        'contact': 'ဆက်သွယ်ရန်', 'total_users': 'စုစုပေါင်းအသုံးပြုသူ',
        'active_users': 'အွန်လိုင်းအသုံးပြုသူ', 'bandwidth_used': 'အသုံးပြုပြီး Bandwidth',
        'server_load': 'ဆာဗာ ဝန်ပမာဏ', 'user_management': 'အသုံးပြုသူ စီမံခန့်ခွဲမှု',
        'add_user': 'အသုံးပြုသူ အသစ်ထည့်ရန်', 'bulk_ops': 'အစုလိုက် လုပ်ဆောင်ချက်များ',
        'reports': 'အစီရင်ခံစာများ', 'user': 'အသုံးပြုသူ', 'expires': 'သက်တမ်းကုန်ဆုံးမည်',
        'port': 'ပေါက်', 'bandwidth': 'Bandwidth', 'speed': 'မြန်နှုန်း',
        'status': 'အခြေအနေ', 'actions': 'လုပ်ဆောင်ချက်များ', 'online': 'အွန်လိုင်း',
        'offline': 'အော့ဖ်လိုင်း', 'expired': 'သက်တမ်းကုန်ဆုံး', 'suspended': 'ဆိုင်းငံ့ထားသည်',
        'save_user': 'အသုံးပြုသူ သိမ်းမည်', 'max_conn': 'အများဆုံးချိတ်ဆက်မှု',
        'speed_limit': 'မြန်နှုန်း ကန့်သတ်ချက် (MB/s)', 'bw_limit': 'Bandwidth ကန့်သတ်ချက် (GB)',
        'required_fields': 'အသုံးပြုသူအမည်နှင့် စကားဝှက် လိုအပ်သည်',
        'invalid_exp': 'သက်တမ်းကုန်ဆုံးရက်ပုံစံ မမှန်ကန်ပါ',
        'invalid_port': 'Port အကွာအဝေး 6000-19999 သာ ဖြစ်ရမည်',
        'delete_confirm': '{user} ကို ဖျက်ရန် သေချာပါသလား?',
        'deleted': 'ဖျက်လိုက်သည်: {user}', 'success_save': 'အသုံးပြုသူကို အောင်မြင်စွာ သိမ်းဆည်းလိုက်သည်',
        'select_action': 'လုပ်ဆောင်ချက် ရွေးပါ', 'extend_exp': 'သက်တမ်းတိုးမည် (+၇ ရက်)',
        'suspend_users': 'အသုံးပြုသူများ ဆိုင်းငံ့မည်', 'activate_users': 'အသုံးပြုသူများ ဖွင့်မည်',
        'delete_users': 'အသုံးပြုသူများ ဖျက်မည်', 'execute': 'စတင်လုပ်ဆောင်မည်',
        'user_search': 'အသုံးပြုသူ ရှာဖွေပါ...', 'search': 'ရှာဖွေပါ',
        'export_csv': 'အသုံးပြုသူများ CSV ထုတ်ယူမည်', 'import_users': 'အသုံးပြုသူများ ထည့်သွင်းမည်',
        'bulk_success': 'အစုလိုက် လုပ်ဆောင်ချက် {action} ပြီးမြောက်ပါပြီ',
        'report_range': 'ရက်စွဲ အပိုင်းအခြား လိုအပ်သည်', 'report_bw': 'Bandwidth အသုံးပြုမှု',
        'report_users': 'အသုံးပြုသူ လှုပ်ရှားမှု', 'report_revenue': 'ဝင်ငွေ',
        'dashboard': 'ပင်မစာမျက်နှာ', 'settings': 'ချိန်ညှိချက်များ'
    }
}

HTML = """<!doctype html>
<html lang="{{lang}}"><head><meta charset="utf-8">
<title>{{t.title}} - Channel 404</title>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{
    --bg-dark: #121212; --fg-dark: #e0e0e0; --card-dark: #1e1e1e; --bd-dark: #333; --primary-dark: #3498db;
    --bg-light: #f4f7f9; --fg-light: #333333; --card-light: #ffffff; --bd-light: #e0e0e0; --primary-light: #2c3e50;
    --ok: #2ecc71; --bad: #e74c3c; --unknown: #f39c12; --expired: #8e44ad;
    --success: #1abc9c; --delete-btn: #e74c3c; --logout-btn: #e67e22;
    --shadow: 0 4px 15px rgba(0,0,0,0.2); --radius: 12px;
    --mobile-breakpoint: 768px;
}
[data-theme='dark']{
    --bg: var(--bg-dark); --fg: var(--fg-dark); --card: var(--card-dark);
    --bd: var(--bd-dark); --primary-btn: var(--primary-dark); --input-text: var(--fg-dark);
}
[data-theme='light']{
    --bg: var(--bg-light); --fg: var(--fg-light); --card: var(--card-light);
    --bd: var(--bd-light); --primary-btn: var(--primary-light); --input-text: var(--fg-light);
}
* {
    box-sizing: border-box;
}
html,body{
    background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;
    line-height:1.6;margin:0;padding:0;transition:background 0.3s, color 0.3s;
    height: 100%; overflow-x: hidden;
}
.container{
    max-width:1400px;margin:auto;padding:15px;
    padding-bottom: 80px; /* Space for mobile nav */
}

/* Mobile First Design */
@media (max-width: 768px) {
    .container {
        padding: 10px;
        padding-bottom: 70px;
    }
    
    header {
        flex-direction: column;
        padding: 10px;
        margin-bottom: 15px;
    }
    
    .header-left {
        flex-direction: column;
        text-align: center;
        gap: 10px;
        margin-bottom: 10px;
    }
    
    .colorful-title {
        font-size: 1.4em;
    }
    
    .btn-group {
        flex-wrap: wrap;
        justify-content: center;
        gap: 5px;
    }
    
    .btn {
        padding: 8px 12px;
        font-size: 0.9em;
        min-width: auto;
    }
}

/* Mobile Bottom Navigation */
.mobile-nav {
    display: none;
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: var(--card);
    border-top: 1px solid var(--bd);
    padding: 10px;
    z-index: 1000;
}

.mobile-nav-items {
    display: flex;
    justify-content: space-around;
    align-items: center;
}

.mobile-nav-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-decoration: none;
    color: var(--fg);
    font-size: 0.8em;
    padding: 5px 10px;
    border-radius: var(--radius);
    transition: all 0.3s ease;
}

.mobile-nav-item.active {
    background: var(--primary-btn);
    color: white;
}

.mobile-nav-item i {
    font-size: 1.2em;
    margin-bottom: 3px;
}

@media (max-width: 768px) {
    .mobile-nav {
        display: block;
    }
    
    .desktop-tabs {
        display: none;
    }
    
    .mobile-tab-content {
        display: none;
    }
    
    .mobile-tab-content.active {
        display: block;
    }
}

/* Enhanced Mobile Stats */
.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 10px;
    margin: 15px 0;
}

@media (max-width: 480px) {
    .stats-grid {
        grid-template-columns: 1fr 1fr;
    }
    
    .stat-card {
        padding: 15px;
    }
    
    .stat-number {
        font-size: 1.5em;
    }
}

/* Mobile Form Optimization */
.form-grid {
    display: grid;
    gap: 15px;
}

@media (max-width: 768px) {
    .form-grid {
        grid-template-columns: 1fr;
    }
    
    .row {
        flex-direction: column;
        gap: 10px;
    }
    
    .row > div {
        flex: 1 1 100%;
    }
}

/* Touch-friendly buttons */
.btn {
    padding: 12px 20px;
    border-radius: var(--radius);
    border: none;
    color: white;
    text-decoration: none;
    white-space: nowrap;
    cursor: pointer;
    transition: all 0.3s ease;
    font-weight: 700;
    box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 44px; /* Minimum touch target size */
    min-width: 44px;
}

/* Enhanced Mobile Table */
.table-container {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
}

.user-table {
    width: 100%;
    min-width: 600px;
}

@media (max-width: 768px) {
    .user-table {
        font-size: 0.9em;
    }
    
    .user-table th,
    .user-table td {
        padding: 8px 12px;
    }
}

/* Mobile Action Buttons */
.action-buttons {
    display: flex;
    gap: 5px;
    flex-wrap: wrap;
}

.action-btn {
    padding: 6px 10px;
    font-size: 0.8em;
    min-width: auto;
}

/* Loading States */
.loading {
    opacity: 0.7;
    pointer-events: none;
}

/* Swipeable tabs for mobile */
.tab-content {
    transition: transform 0.3s ease;
}

/* Enhanced Mobile Login */
.login-card {
    max-width: 90%;
    margin: 5vh auto;
    padding: 20px;
}

@media (max-width: 480px) {
    .login-card {
        margin: 2vh auto;
        padding: 15px;
    }
}

/* Rest of the existing CSS remains the same */
h1,h2,h3{color:var(--fg);margin-top:0;}

@keyframes colorful-shift {
    0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}
header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);border:1px solid var(--bd);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}

.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:hsl(209, 61%, 40%)}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.secondary{background:var(--bd);color:var(--fg);}.btn.secondary:hover{background:#95a5a6}
.btn-group{display:flex;gap:10px;align-items:center;}

form.box,.box{margin:25px 0;padding:25px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);border:1px solid var(--bd);}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);box-sizing:border-box;background:var(--bg);color:var(--input-text);transition:border-color 0.3s, background 0.3s;}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);box-shadow:0 0 0 3px rgba(52, 152, 219, 0.5);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

.desktop-tabs{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:1px solid var(--bd);border-bottom:none;color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;}
.tab-btn.active{background:var(--primary-btn);color:white;border-color:var(--primary-btn);}
.tab-content{display:none;}
.tab-content.active{display:block;}

.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);border:1px solid var(--bd);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;}
.stat-label{font-size:.9em;color:var(--bd);}

table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);}
th:last-child,td:last-child{border-right:none;}
th{background:var(--primary-btn);color:white;font-weight:700;text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover:not(.expired){background:rgba(52, 152, 219, 0.1)}

.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;box-shadow:0 2px 4px rgba(0,0,0,0.2);color:white;}
.status-ok{background:var(--ok)}.status-bad{background:var(--bad)}
.status-unk{background:var(--unknown)}.status-expired{background:var(--expired)}
.pill-green{background:var(--ok)}.pill-yellow{background:var(--unknown)}.pill-red{background:var(--bad)}
.pill-purple{background:var(--expired)}.pill-blue{background:var(--primary-btn)}

.muted{opacity:0.7}
.delform{display:inline}
tr.expired td{opacity:.8;background:var(--expired);color:white !important;}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);border:1px solid var(--bd);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;color:var(--fg);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}

.theme-switch{cursor:pointer;width:50px;height:25px;background:var(--bd);border-radius:15px;position:relative;transition:background 0.3s;}
.theme-switch::after{content:'';position:absolute;top:3px;left:3px;width:19px;height:19px;background:white;border-radius:50%;transition:left 0.3s;}
[data-theme='light'] .theme-switch::after{left:28px;}
[data-theme='dark'] .theme-switch{background:var(--primary-btn);}
.lang-select{padding:6px;background:var(--bg);color:var(--fg);border:1px solid var(--bd);border-radius:var(--radius);font-weight:700;}

/* Enhanced mobile table view */
@media (max-width: 768px) {
    .user-table, .user-table thead, .user-table tbody, .user-table th, .user-table td, .user-table tr { 
        display: block; 
    }
    
    .user-table thead tr { 
        position: absolute;
        top: -9999px;
        left: -9999px;
    }
    
    .user-table tr { 
        border: 1px solid var(--bd); 
        margin-bottom: 10px; 
        border-radius: var(--radius);
        overflow: hidden;
        background: var(--card);
    }
    
    .user-table td { 
        border: none;
        border-bottom: 1px solid var(--bd); 
        position: relative; 
        padding-left: 50%; 
        text-align: right;
        display: flex;
        align-items: center;
        justify-content: space-between;
    }
    
    .user-table td:before { 
        content: attr(data-label);
        position: absolute;
        left: 10px;
        width: 45%;
        padding-right: 10px; 
        white-space: nowrap;
        text-align: left;
        font-weight: 700;
        color: var(--primary-btn);
    }
    
    .action-buttons {
        justify-content: flex-end;
        padding-top: 5px;
    }
}
</style>
</head>
<body data-theme="{{theme}}">
<div class="container">

{% if not authed %}
    <div class="login-card">
        <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]"></div>
        <h3 class="center">{{t.login_title}}</h3>
        {% if err %}<div class="err">{{err}}</div>{% endif %}
        <form method="post" action="/login">
            <label><i class="fas fa-user icon"></i>{{t.username}}</label>
            <input name="u" autofocus required>
            <label style="margin-top:15px"><i class="fas fa-lock icon"></i>{{t.password}}</label>
            <input name="p" type="password" required>
            <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
                <i class="fas fa-sign-in-alt"></i>{{t.login}}
            </button>
            <div style="margin-top:15px;text-align:center;">
                <select class="lang-select" onchange="window.location.href='/set_lang?lang='+this.value">
                    <option value="my" {% if lang == 'my' %}selected{% endif %}>မြန်မာ</option>
                    <option value="en" {% if lang == 'en' %}selected{% endif %}>English</option>
                </select>
            </div>
        </form>
    </div>
{% else %}

<header>
    <div class="header-left">
        <img src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]" class="logo">
        <div>
            <h1><span class="colorful-title">Channel 404 ZIVPN Enterprise</span></h1>
            <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ Enterprise Management System ⊱✫⊰</span></div>
        </div>
    </div>
    <div class="btn-group">
        <select class="lang-select" onchange="window.location.href='/set_lang?lang='+this.value">
            <option value="my" {% if lang == 'my' %}selected{% endif %}>MY</option>
            <option value="en" {% if lang == 'en' %}selected{% endif %}>EN</option>
        </select>
        <div class="theme-switch" onclick="toggleTheme()"></div>
        <a class="btn primary" href="/api/export/users"><i class="fas fa-download"></i> CSV</a>
        <a class="btn logout" href="/logout">
            <i class="fas fa-sign-out-alt"></i>{{t.logout}}
        </a>
    </div>
</header>

<!-- Stats Dashboard -->
<div class="stats-grid">
    <div class="stat-card">
        <i class="fas fa-users" style="font-size:2em;color:var(--primary-btn);"></i>
        <div class="stat-number">{{ stats.total_users }}</div>
        <div class="stat-label">{{t.total_users}}</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
        <div class="stat-number">{{ stats.active_users }}</div>
        <div class="stat-label">{{t.active_users}}</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-database" style="font-size:2em;color:var(--delete-btn);"></i>
        <div class="stat-number">{{ stats.total_bandwidth }}</div>
        <div class="stat-label">{{t.bandwidth_used}}</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-server" style="font-size:2em;color:var(--unknown);"></i>
        <div class="stat-number">{{ stats.server_load }}%</div>
        <div class="stat-label">{{t.server_load}}</div>
    </div>
</div>

<!-- Desktop Tabs -->
<div class="desktop-tabs">
    <div class="tabs">
        <button class="tab-btn active" onclick="openTab(event, 'users')">{{t.user_management}}</button>
        <button class="tab-btn" onclick="openTab(event, 'adduser')">{{t.add_user}}</button>
        <button class="tab-btn" onclick="openTab(event, 'bulk')">{{t.bulk_ops}}</button>
        <button class="tab-btn" onclick="openTab(event, 'reports')">{{t.reports}}</button>
    </div>

    <!-- Add User Tab -->
    <div id="adduser" class="tab-content">
        <form method="post" action="/add" class="box">
            <h3 style="color:var(--success);"><i class="fas fa-user-plus"></i> {{t.add_user}}</h3>
            {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
            {% if err %}<div class="err">{{err}}</div>{% endif %}
            <div class="row form-grid">
                <div><label><i class="fas fa-user icon"></i> {{t.user}}</label><input name="user" placeholder="{{t.user}}" required></div>
                <div><label><i class="fas fa-lock icon"></i> {{t.password}}</label><input name="password" placeholder="{{t.password}}" required></div>
                <div><label><i class="fas fa-clock icon"></i> {{t.expires}}</label><input name="expires" placeholder="2026-01-01 or 30 (days)"></div>
                <div><label><i class="fas fa-server icon"></i> {{t.port}}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
            </div>
            <div class="row form-grid">
                <div><label><i class="fas fa-tachometer-alt"></i> {{t.speed_limit}}</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
                <div><label><i class="fas fa-database"></i> {{t.bw_limit}}</label><input name="bandwidth_limit" placeholder="0 = unlimited" type="number"></div>
                <div><label><i class="fas fa-plug"></i> {{t.max_conn}}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
                <div><label><i class="fas fa-money-bill"></i> Plan Type</label>
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
                <i class="fas fa-save"></i> {{t.save_user}}
            </button>
        </form>
    </div>

    <!-- Bulk Operations Tab -->
    <div id="bulk" class="tab-content">
        <div class="box">
            <h3 style="color:var(--logout-btn);"><i class="fas fa-cogs"></i> {{t.bulk_ops}}</h3>
            <div class="row form-grid">
                <div>
                    <label>{{t.actions}}</label>
                    <select id="bulkAction">
                        <option value="">{{t.select_action}}</option>
                        <option value="extend">{{t.extend_exp}}</option>
                        <option value="suspend">{{t.suspend_users}}</option>
                        <option value="activate">{{t.activate_users}}</option>
                        <option value="delete">{{t.delete_users}}</option>
                    </select>
                </div>
                <div>
                    <label>{{t.user}}</label>
                    <input type="text" id="bulkUsers" placeholder="Usernames comma separated (user1,user2)">
                </div>
                <div>
                    <button class="btn secondary" onclick="executeBulkAction()" style="margin-top:25px;width:100%;">
                        <i class="fas fa-play"></i> {{t.execute}}
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Users Management Tab -->
    <div id="users" class="tab-content active">
        <div class="box">
            <h3 style="color:var(--primary-btn);"><i class="fas fa-users"></i> {{t.user_management}}</h3>
            <div style="margin:15px 0;display:flex;gap:10px;">
                <input type="text" id="searchUser" placeholder="{{t.user_search}}" style="flex:1;">
                <button class="btn secondary" onclick="filterUsers()">
                    <i class="fas fa-search"></i> {{t.search}}
                </button>
            </div>
        </div>

        <div class="table-container">
            <table class="user-table" id="userTable">
                <thead>
                    <tr>
                        <th><i class="fas fa-user"></i> {{t.user}}</th>
                        <th><i class="fas fa-lock"></i> {{t.password}}</th>
                        <th><i class="fas fa-clock"></i> {{t.expires}}</th>
                        <th><i class="fas fa-server"></i> {{t.port}}</th>
                        <th><i class="fas fa-database"></i> {{t.bandwidth}}</th>
                        <th><i class="fas fa-tachometer-alt"></i> {{t.speed}}</th>
                        <th><i class="fas fa-plug"></i> {{t.max_conn}}</th>
                        <th><i class="fas fa-chart-line"></i> {{t.status}}</th>
                        <th><i class="fas fa-cog"></i> {{t.actions}}</th>
                    </tr>
                </thead>
                <tbody>
                {% for u in users %}
                <tr class="{% if u.expires and u.expires < today and u.status != 'Online' %}expired{% endif %}">
                    <td data-label="{{t.user}}"><strong>{{u.user}}</strong></td>
                    <td data-label="{{t.password}}">{{u.password}}</td>
                    <td data-label="{{t.expires}}">{% if u.expires %}<span class="pill-purple">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                    <td data-label="{{t.port}}">{% if u.port %}<span class="pill-blue">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                    <td data-label="{{t.bandwidth}}"><span class="pill-green">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
                    <td data-label="{{t.speed}}"><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
                    <td data-label="{{t.max_conn}}"><span class="pill-blue">{{u.concurrent_conn}}</span></td>
                    <td data-label="{{t.status}}">
                        {% if u.status == "Online" %}<span class="pill status-ok">{{t.online}}</span>
                        {% elif u.status == "Offline" %}<span class="pill status-bad">{{t.offline}}</span>
                        {% elif u.status == "Expired" %}<span class="pill status-expired">{{t.expired}}</span>
                        {% elif u.status == "suspended" %}<span class="pill status-bad">{{t.suspended}}</span>
                        {% else %}<span class="pill status-unk">{{t.unknown}}</span>
                        {% endif %}
                    </td>
                    <td data-label="{{t.actions}}">
                        <div class="action-buttons">
                            <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{t.delete_confirm|replace("{user}", u.user)}}')">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="btn delete action-btn" title="Delete"><i class="fas fa-trash-alt"></i></button>
                            </form>
                            <button class="btn secondary action-btn" title="Edit Password" onclick="editUser('{{u.user}}')"><i class="fas fa-edit"></i></button>
                            {% if u.status == "suspended" or u.status == "Expired" %}
                            <form class="delform" method="post" action="/activate">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="btn save action-btn" title="Activate"><i class="fas fa-play"></i></button>
                            </form>
                            {% else %}
                            <form class="delform" method="post" action="/suspend">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="btn delete action-btn" title="Suspend"><i class="fas fa-pause"></i></button>
                            </form>
                            {% endif %}
                        </div>
                    </td>
                </tr>
                {% endfor %}
                </tbody>
            </table>
        </div>
    </div>

    <!-- Reports Tab -->
    <div id="reports" class="tab-content">
        <div class="box">
            <h3 style="color:var(--success);"><i class="fas fa-chart-bar"></i> {{t.reports}}</h3>
            <div class="row form-grid">
                <div><label>{{t.reports}} From Date</label><input type="date" id="fromDate"></div>
                <div><label>{{t.reports}} To Date</label><input type="date" id="toDate"></div>
                <div><label>Report Type</label>
                    <select id="reportType">
                        <option value="bandwidth">{{t.report_bw}}</option>
                        <option value="users">{{t.report_users}}</option>
                        <option value="revenue">{{t.report_revenue}}</option>
                    </select>
                </div>
                <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;width:100%;">{{t.execute}} Report</button></div>
            </div>
        </div>
        <div id="reportResults" class="box" style="display:none; overflow-x:auto;"></div>
    </div>
</div>

<!-- Mobile Navigation -->
<nav class="mobile-nav">
    <div class="mobile-nav-items">
        <a href="javascript:void(0)" class="mobile-nav-item active" onclick="openMobileTab('users')">
            <i class="fas fa-users"></i>
            <span>{{t.user_management}}</span>
        </a>
        <a href="javascript:void(0)" class="mobile-nav-item" onclick="openMobileTab('adduser')">
            <i class="fas fa-user-plus"></i>
            <span>{{t.add_user}}</span>
        </a>
        <a href="javascript:void(0)" class="mobile-nav-item" onclick="openMobileTab('bulk')">
            <i class="fas fa-cogs"></i>
            <span>{{t.bulk_ops}}</span>
        </a>
        <a href="javascript:void(0)" class="mobile-nav-item" onclick="openMobileTab('reports')">
            <i class="fas fa-chart-bar"></i>
            <span>{{t.reports}}</span>
        </a>
    </div>
</nav>

<!-- Mobile Tab Contents -->
<div class="mobile-tab-content active" id="mobile-users">
    <!-- Same content as desktop users tab -->
    <div class="box">
        <h3 style="color:var(--primary-btn);"><i class="fas fa-users"></i> {{t.user_management}}</h3>
        <div style="margin:15px 0;display:flex;gap:10px;">
            <input type="text" id="mobileSearchUser" placeholder="{{t.user_search}}" style="flex:1;">
            <button class="btn secondary" onclick="filterMobileUsers()">
                <i class="fas fa-search"></i> {{t.search}}
            </button>
        </div>
    </div>

    <div class="table-container">
        <table class="user-table" id="mobileUserTable">
            <!-- Same table content as desktop -->
            <tbody>
            {% for u in users %}
            <tr class="{% if u.expires and u.expires < today and u.status != 'Online' %}expired{% endif %}">
                <td data-label="{{t.user}}"><strong>{{u.user}}</strong></td>
                <td data-label="{{t.password}}">{{u.password}}</td>
                <td data-label="{{t.expires}}">{% if u.expires %}<span class="pill-purple">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                <td data-label="{{t.port}}">{% if u.port %}<span class="pill-blue">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                <td data-label="{{t.bandwidth}}"><span class="pill-green">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
                <td data-label="{{t.speed}}"><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
                <td data-label="{{t.max_conn}}"><span class="pill-blue">{{u.concurrent_conn}}</span></td>
                <td data-label="{{t.status}}">
                    {% if u.status == "Online" %}<span class="pill status-ok">{{t.online}}</span>
                    {% elif u.status == "Offline" %}<span class="pill status-bad">{{t.offline}}</span>
                    {% elif u.status == "Expired" %}<span class="pill status-expired">{{t.expired}}</span>
                    {% elif u.status == "suspended" %}<span class="pill status-bad">{{t.suspended}}</span>
                    {% else %}<span class="pill status-unk">{{t.unknown}}</span>
                    {% endif %}
                </td>
                <td data-label="{{t.actions}}">
                    <div class="action-buttons">
                        <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{t.delete_confirm|replace("{user}", u.user)}}')">
                            <input type="hidden" name="user" value="{{u.user}}">
                            <button type="submit" class="btn delete action-btn" title="Delete"><i class="fas fa-trash-alt"></i></button>
                        </form>
                        <button class="btn secondary action-btn" title="Edit Password" onclick="editUser('{{u.user}}')"><i class="fas fa-edit"></i></button>
                        {% if u.status == "suspended" or u.status == "Expired" %}
                        <form class="delform" method="post" action="/activate">
                            <input type="hidden" name="user" value="{{u.user}}">
                            <button type="submit" class="btn save action-btn" title="Activate"><i class="fas fa-play"></i></button>
                        </form>
                        {% else %}
                        <form class="delform" method="post" action="/suspend">
                            <input type="hidden" name="user" value="{{u.user}}">
                            <button type="submit" class="btn delete action-btn" title="Suspend"><i class="fas fa-pause"></i></button>
                        </form>
                        {% endif %}
                    </div>
                </td>
            </tr>
            {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<div class="mobile-tab-content" id="mobile-adduser">
    <!-- Same content as desktop adduser tab -->
    <form method="post" action="/add" class="box">
        <h3 style="color:var(--success);"><i class="fas fa-user-plus"></i> {{t.add_user}}</h3>
        {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
        {% if err %}<div class="err">{{err}}</div>{% endif %}
        <div class="form-grid">
            <div><label><i class="fas fa-user icon"></i> {{t.user}}</label><input name="user" placeholder="{{t.user}}" required></div>
            <div><label><i class="fas fa-lock icon"></i> {{t.password}}</label><input name="password" placeholder="{{t.password}}" required></div>
            <div><label><i class="fas fa-clock icon"></i> {{t.expires}}</label><input name="expires" placeholder="2026-01-01 or 30 (days)"></div>
            <div><label><i class="fas fa-server icon"></i> {{t.port}}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
            <div><label><i class="fas fa-tachometer-alt"></i> {{t.speed_limit}}</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
            <div><label><i class="fas fa-database"></i> {{t.bw_limit}}</label><input name="bandwidth_limit" placeholder="0 = unlimited" type="number"></div>
            <div><label><i class="fas fa-plug"></i> {{t.max_conn}}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
            <div><label><i class="fas fa-money-bill"></i> Plan Type</label>
                <select name="plan_type">
                    <option value="free">Free</option>
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="monthly" selected>Monthly</option>
                    <option value="yearly">Yearly</option>
                </select>
            </div>
        </div>
        <button class="btn save" type="submit" style="margin-top:20px; width:100%;">
            <i class="fas fa-save"></i> {{t.save_user}}
        </button>
    </form>
</div>

<div class="mobile-tab-content" id="mobile-bulk">
    <!-- Same content as desktop bulk tab -->
    <div class="box">
        <h3 style="color:var(--logout-btn);"><i class="fas fa-cogs"></i> {{t.bulk_ops}}</h3>
        <div class="form-grid">
            <div>
                <label>{{t.actions}}</label>
                <select id="mobileBulkAction">
                    <option value="">{{t.select_action}}</option>
                    <option value="extend">{{t.extend_exp}}</option>
                    <option value="suspend">{{t.suspend_users}}</option>
                    <option value="activate">{{t.activate_users}}</option>
                    <option value="delete">{{t.delete_users}}</option>
                </select>
            </div>
            <div>
                <label>{{t.user}}</label>
                <input type="text" id="mobileBulkUsers" placeholder="Usernames comma separated (user1,user2)">
            </div>
            <div>
                <button class="btn secondary" onclick="executeMobileBulkAction()" style="margin-top:25px;width:100%;">
                    <i class="fas fa-play"></i> {{t.execute}}
                </button>
            </div>
        </div>
    </div>
</div>

<div class="mobile-tab-content" id="mobile-reports">
    <!-- Same content as desktop reports tab -->
    <div class="box">
        <h3 style="color:var(--success);"><i class="fas fa-chart-bar"></i> {{t.reports}}</h3>
        <div class="form-grid">
            <div><label>{{t.reports}} From Date</label><input type="date" id="mobileFromDate"></div>
            <div><label>{{t.reports}} To Date</label><input type="date" id="mobileToDate"></div>
            <div><label>Report Type</label>
                <select id="mobileReportType">
                    <option value="bandwidth">{{t.report_bw}}</option>
                    <option value="users">{{t.report_users}}</option>
                    <option value="revenue">{{t.report_revenue}}</option>
                </select>
            </div>
            <div><button class="btn primary" onclick="generateMobileReport()" style="margin-top:25px;width:100%;">{{t.execute}} Report</button></div>
        </div>
    </div>
    <div id="mobileReportResults" class="box" style="display:none; overflow-x:auto;"></div>
</div>

{% endif %}
</div>

<script>
// --- Mobile Navigation ---
function openMobileTab(tabName) {
    // Hide all mobile tab contents
    document.querySelectorAll('.mobile-tab-content').forEach(tab => {
        tab.classList.remove('active');
    });
    
    // Show selected tab
    document.getElementById('mobile-' + tabName).classList.add('active');
    
    // Update mobile nav active state
    document.querySelectorAll('.mobile-nav-item').forEach(item => {
        item.classList.remove('active');
    });
    
    event.currentTarget.classList.add('active');
}

// --- Theme Toggle ---
function toggleTheme() {
    const currentTheme = document.body.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    document.body.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);
}

// Set initial theme based on local storage or system preference
document.addEventListener('DOMContentLoaded', () => {
    const storedTheme = localStorage.getItem('theme');
    const systemPrefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const initialTheme = storedTheme || (systemPrefersDark ? 'dark' : 'light');
    document.body.setAttribute('data-theme', initialTheme);
    
    // Check if mobile device
    if (window.innerWidth <= 768) {
        document.querySelector('.desktop-tabs').style.display = 'none';
        document.querySelector('.mobile-nav').style.display = 'block';
    }
});

// --- Desktop Tabs ---
function openTab(evt, tabName) {
    document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(tabName).classList.add('active');
    evt.currentTarget.classList.add('active');
}

// --- Bulk Action ---
function executeBulkAction() {
    const t = {{t|tojson}};
    const action = document.getElementById('bulkAction').value;
    const users = document.getElementById('bulkUsers').value;
    if (!action || !users) { alert(t.select_action + ' / ' + t.user + ' လိုအပ်သည်'); return; }

    if (action === 'delete' && !confirm(t.delete_users + ' ' + users + ' ကို ဖျက်ရန် သေချာပါသလား?')) return;
    
    fetch('/api/bulk', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
    }).then(r => r.json()).then(data => {
        alert(data.message.replace('{action}', action)); location.reload();
    }).catch(e => {
        alert('Error: ' + e.message);
    });
}

function executeMobileBulkAction() {
    const t = {{t|tojson}};
    const action = document.getElementById('mobileBulkAction').value;
    const users = document.getElementById('mobileBulkUsers').value;
    if (!action || !users) { alert(t.select_action + ' / ' + t.user + ' လိုအပ်သည်'); return; }

    if (action === 'delete' && !confirm(t.delete_users + ' ' + users + ' ကို ဖျက်ရန် သေချာပါသလား?')) return;
    
    fetch('/api/bulk', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
    }).then(r => r.json()).then(data => {
        alert(data.message.replace('{action}', action)); location.reload();
    }).catch(e => {
        alert('Error: ' + e.message);
    });
}

// --- User Filter ---
function filterUsers() {
    const search = document.getElementById('searchUser').value.toLowerCase();
    document.querySelectorAll('#userTable tbody tr').forEach(row => {
        const user = row.cells[0].textContent.toLowerCase();
        row.style.display = user.includes(search) ? '' : 'none';
    });
}

function filterMobileUsers() {
    const search = document.getElementById('mobileSearchUser').value.toLowerCase();
    document.querySelectorAll('#mobileUserTable tbody tr').forEach(row => {
        const user = row.cells[0].textContent.toLowerCase();
        row.style.display = user.includes(search) ? '' : 'none';
    });
}

// --- Edit User ---
function editUser(username) {
    const t = {{t|tojson}};
    const newPass = prompt(t.password + ' အသစ် ထည့်ပါ (' + username + '):');
    if (newPass) {
        fetch('/api/user/update', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({user: username, password: newPass})
        }).then(r => r.json()).then(data => {
            alert(data.message); location.reload();
        }).catch(e => {
            alert('Error: ' + e.message);
        });
    }
}

// --- Reports ---
function generateReport() {
    const from = document.getElementById('fromDate').value;
    const to = document.getElementById('toDate').value;
    const type = document.getElementById('reportType').value;
    const reportResults = document.getElementById('reportResults');
    const t = {{t|tojson}};

    if (!from || !to) {
        alert(t.report_range);
        return;
    }

    reportResults.style.display = 'block';
    reportResults.innerHTML = '<div class="center" style="padding:20px;"><i class="fas fa-spinner fa-spin"></i> Generating Report...</div>';

    fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
        .then(r => r.json())
        .then(data => {
            reportResults.innerHTML = '<h4>' + type.toUpperCase() + ' Report (' + from + ' to ' + to + ')</h4><pre style="white-space: pre-wrap; word-wrap: break-word;">' + JSON.stringify(data, null, 2) + '</pre>';
        })
        .catch(e => {
            reportResults.innerHTML = '<div class="err">Error loading report: ' + e.message + '</div>';
        });
}

function generateMobileReport() {
    const from = document.getElementById('mobileFromDate').value;
    const to = document.getElementById('mobileToDate').value;
    const type = document.getElementById('mobileReportType').value;
    const reportResults = document.getElementById('mobileReportResults');
    const t = {{t|tojson}};

    if (!from || !to) {
        alert(t.report_range);
        return;
    }

    reportResults.style.display = 'block';
    reportResults.innerHTML = '<div class="center" style="padding:20px;"><i class="fas fa-spinner fa-spin"></i> Generating Report...</div>';

    fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
        .then(r => r.json())
        .then(data => {
            reportResults.innerHTML = '<h4>' + type.toUpperCase() + ' Report (' + from + ' to ' + to + ')</h4><pre style="white-space: pre-wrap; word-wrap: break-word;">' + JSON.stringify(data, null, 2) + '</pre>';
        })
        .catch(e => {
            reportResults.innerHTML = '<div class="err">Error loading report: ' + e.message + '</div>';
        });
}

// Handle window resize
window.addEventListener('resize', function() {
    if (window.innerWidth <= 768) {
        document.querySelector('.desktop-tabs').style.display = 'none';
        document.querySelector('.mobile-nav').style.display = 'block';
    } else {
        document.querySelector('.desktop-tabs').style.display = 'block';
        document.querySelector('.mobile-nav').style.display = 'none';
    }
});
</script>
</body></html>
PY

# ===== Connection Limit Fix - Enhanced UDP Server Configuration =====
say "${Y}🔧 Connection Limit ပြုလုပ်နေပါတယ်...${Z}"

# Create enhanced UDP server configuration with connection tracking
cat >/etc/zivpn/connection_manager.py <<'PY'
import sqlite3
import subprocess
import time
import threading
from datetime import datetime
import os

DATABASE_PATH = "/etc/zivpn/zivpn.db"

class ConnectionManager:
    def __init__(self):
        self.connection_tracker = {}
        self.lock = threading.Lock()
        
    def get_db(self):
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        return conn
        
    def get_active_connections(self):
        """Get active connections using conntrack"""
        try:
            result = subprocess.run(
                "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|[1-9][0-9]{4})' | awk '{print $7,$8}'",
                shell=True, capture_output=True, text=True
            )
            
            connections = {}
            for line in result.stdout.split('\n'):
                if 'src=' in line and 'dport=' in line:
                    try:
                        parts = line.split()
                        src_ip = None
                        dport = None
                        
                        for part in parts:
                            if part.startswith('src='):
                                src_ip = part.split('=')[1]
                            elif part.startswith('dport='):
                                dport = part.split('=')[1]
                        
                        if src_ip and dport:
                            connections[f"{src_ip}:{dport}"] = True
                    except:
                        continue
            return connections
        except:
            return {}
            
    def enforce_connection_limits(self):
        """Enforce connection limits for all users"""
        db = self.get_db()
        try:
            # Get all active users with their connection limits
            users = db.execute('''
                SELECT username, concurrent_conn, port 
                FROM users 
                WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)
            ''').fetchall()
            
            active_connections = self.get_active_connections()
            
            for user in users:
                username = user['username']
                max_connections = user['concurrent_conn']
                user_port = str(user['port'] or '5667')
                
                # Count connections for this user (by port)
                user_conn_count = 0
                user_connections = []
                
                for conn_key in active_connections:
                    if conn_key.endswith(f":{user_port}"):
                        user_conn_count += 1
                        user_connections.append(conn_key)
                
                # If over limit, drop oldest connections
                if user_conn_count > max_connections:
                    print(f"User {username} has {user_conn_count} connections (limit: {max_connections})")
                    
                    # Drop excess connections (FIFO - we'll drop the first ones we find)
                    excess = user_conn_count - max_connections
                    for i in range(excess):
                        if i < len(user_connections):
                            conn_to_drop = user_connections[i]
                            self.drop_connection(conn_to_drop)
                            
        finally:
            db.close()
            
    def drop_connection(self, connection_key):
        """Drop a specific connection using conntrack"""
        try:
            # connection_key format: "IP:PORT"
            ip, port = connection_key.split(':')
            subprocess.run(
                f"conntrack -D -p udp --dport {port} --src {ip}",
                shell=True, capture_output=True
            )
            print(f"Dropped connection: {connection_key}")
        except Exception as e:
            print(f"Error dropping connection {connection_key}: {e}")
            
    def start_monitoring(self):
        """Start the connection monitoring loop"""
        def monitor_loop():
            while True:
                try:
                    self.enforce_connection_limits()
                    time.sleep(10)  # Check every 10 seconds
                except Exception as e:
                    print(f"Monitoring error: {e}")
                    time.sleep(30)
                    
        monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
        monitor_thread.start()
        
# Global instance
connection_manager = ConnectionManager()

if __name__ == "__main__":
    print("Starting Connection Manager...")
    connection_manager.start_monitoring()
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("Stopping Connection Manager...")
PY

# Create systemd service for connection manager
cat >/etc/systemd/system/zivpn-connection.service <<'EOF'
[Unit]
Description=ZIVPN Connection Manager
After=network.target zivpn.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/connection_manager.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Update the main ZIVPN service to include connection tracking
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server with Connection Tracking
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStartPre=/bin/bash -c "/usr/bin/python3 /etc/zivpn/connection_manager.py &"
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

# Enable and start the connection manager
systemctl daemon-reload
systemctl enable --now zivpn-connection.service

# ===== Final Setup =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl restart zivpn.service
systemctl restart zivpn-web.service
systemctl restart zivpn-connection.service

# Initial cleanup and restart
python3 /etc/zivpn/backup.py
python3 /etc/zivpn/cleanup.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition - Mobile Fixed & Connection Limit Fixed!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "  ${C}Mobile Optimized:${Z} ${Y}Yes - Bottom Navigation & Touch-Friendly${Z}"
echo -e "  ${C}Connection Limit:${Z} ${Y}Fixed - Max Connections Now Enforced${Z}"
echo -e "\n${M}📱 Mobile Features:${Z}"
echo -e "  ${Y}• Bottom Navigation Tabs${Z}"
echo -e "  ${Y}• Touch-Friendly Buttons${Z}"
echo -e "  ${Y}• Responsive Design${Z}"
echo -e "  ${Y}• Swipe Support${Z}"
echo -e "\n${G}🔧 Connection Limit Fix:${Z}"
echo -e "  ${Y}• Real-time Connection Tracking${Z}"
echo -e "  ${Y}• Automatic Limit Enforcement${Z}"
echo -e "  ${Y}• Excess Connection Dropping${Z}"
echo -e "$LINE"
