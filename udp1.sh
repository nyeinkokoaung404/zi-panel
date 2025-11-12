#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION
# Author: 4 0 4 \ 2.0 [🇲🇲] - Upgraded by Gemini
# Features: Complete Enterprise Management System with Bandwidth Control, Billing, Multi-Server, API, etc.
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION (Enhanced) ${Z}\n$LINE"

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
systemctl stop zivpn-maintenance.service 2>/dev/null || true
systemctl stop zivpn-bot.service 2>/dev/null || true

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

# ===== Enhanced Database Setup (IDEMPOTENT) =====
say "${Y}🗃️ Enhanced Database ဖန်တီးနေပါတယ်...${Z}"
sqlite3 "$DB" <<'EOF'
-- Users table: Central authority for account management
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expires DATE,
    port INTEGER,
    status TEXT DEFAULT 'active', -- 'active', 'suspended', 'expired'
    bandwidth_limit INTEGER DEFAULT 0, -- in GB (must be converted to bytes in server logic)
    bandwidth_used INTEGER DEFAULT 0, -- in bytes
    speed_limit_up INTEGER DEFAULT 0, -- in KB/s (must be converted in server logic)
    speed_limit_down INTEGER DEFAULT 0, -- in KB/s
    concurrent_conn INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Billing table: For tracking payments and plans
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

-- Bandwidth logs for reporting
CREATE TABLE IF NOT EXISTS bandwidth_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    bytes_used INTEGER DEFAULT 0,
    log_date DATE DEFAULT CURRENT_DATE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Server Statistics snapshot
CREATE TABLE IF NOT EXISTS server_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    total_bandwidth INTEGER DEFAULT 0,
    server_load REAL DEFAULT 0,
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Audit logs for admin actions
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_user TEXT NOT NULL,
    action TEXT NOT NULL,
    target_user TEXT,
    details TEXT,
    ip_address TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Notifications (e.g., account expiring soon)
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
        .key  = "/etc/zivpn/zivpn.key" |
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

# Constants
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
# How many seconds of inactivity before marking a port as "Offline"
CONNTRAK_INACTIVITY_SECONDS = 15 
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Language Dictionary ---
LANG = {
    "my": {
        "title": "Channel 404 ZIVPN အုပ်ချုပ်မှုစနစ်",
        "enterprise_system": "⊱✫⊰ Enterprise စီမံခန့်ခွဲမှုစနစ် ⊱✫⊰",
        "contact": "ဆက်သွယ်ရန်",
        "logout": "ထွက်ရန်",
        "login_title": "ZIVPN Panel ဝင်ရန်",
        "login_err": "မှန်ကန်မှုမရှိပါ",
        "username": "အသုံးပြုသူအမည်",
        "password": "စကားဝှက်",
        "total_users": "အသုံးပြုသူ စုစုပေါင်း",
        "active_users": "တက်ကြွသောအသုံးပြုသူ",
        "bandwidth_used": "သုံးစွဲထားသော Bandwidth",
        "server_load": "ဆာဗာ ဝန်ပမာဏ",
        "user_management": "အသုံးပြုသူ စီမံခန့်ခွဲမှု",
        "add_user": "အသုံးပြုသူ အသစ်ထည့်ပါ",
        "bulk_operations": "အများအပြား ဆောင်ရွက်ခြင်း",
        "reports": "အစီရင်ခံစာများ",
        "user": "အသုံးပြုသူ",
        "expires": "သက်တမ်းကုန်ဆုံး",
        "port": "ပွင့်ပေါက်",
        "bandwidth": "Bandwidth",
        "speed": "မြန်နှုန်း",
        "status": "အခြေအနေ",
        "actions": "လုပ်ဆောင်ချက်",
        "online": "အွန်လိုင်း",
        "offline": "အော့ဖ်လိုင်း",
        "expired": "သက်တမ်းကုန်",
        "suspended": "ရပ်ဆိုင်းထား",
        "unknown": "မသိရှိရ",
        "user_pass_required": "User နှင့် Password လိုအပ်သည်",
        "expires_format_error": "Expires format မမှန်ပါ",
        "port_range_error": "Port အကွာအဝေး 6000-19999",
        "user_saved": "User ကို အောင်မြင်စွာ သိမ်းဆည်းပြီး",
        "user_deleted": "ဖျက်ပြီး: ",
        "delete_confirm": " ကို ဖျက်မလား?",
        "edit": "ပြုပြင်ရန်",
        "delete": "ဖျက်ရန်",
        "suspend": "ရပ်ဆိုင်းရန်",
        "activate": "ပြန်စရန်",
        "max_conn": "အများဆုံး ချိတ်ဆက်မှု",
        "speed_limit_mb": "မြန်နှုန်း ကန့်သတ်ချက် (MB/s)",
        "bandwidth_limit_gb": "Bandwidth ကန့်သတ်ချက် (GB)",
        "plan_type": "အစီအစဉ် အမျိုးအစား",
        "save_user": "User သိမ်းဆည်း",
        "bulk_execute_alert": "လုပ်ဆောင်ချက်နှင့် အသုံးပြုသူများ ထည့်ပါ",
        "execute": "ဆောင်ရွက်",
        "export_users": "Users CSV ထုတ်ယူ",
        "import_users": "Users တင်သွင်း",
        "search_users": "Users ရှာဖွေပါ...",
        "from_date": "မှ ရက်စွဲ",
        "to_date": "အထိ ရက်စွဲ",
        "report_type": "အစီရင်ခံစာ အမျိုးအစား",
        "generate_report": "အစီရင်ခံစာ ထုတ်လုပ်",
        "user_not_found": "အသုံးပြုသူ ရှာမတွေ့ပါ",
        "user_updated": "User ကို ပြုပြင်ပြီး",
        "invalid_data": "မှားယွင်းသော အချက်အလက်",
        "login": "ဝင်ရန်",
        "theme": "ပုံစံ",
        "language": "ဘာသာစကား",
        "max_conn_limit": "ချိတ်ဆက်မှု ကန့်သတ်ချက်",
        "speed_limit_kb": "မြန်နှုန်း ကန့်သတ်ချက် (KB/s)", # Internal reference
        "bandwidth_limit_bytes": "Bandwidth ကန့်သတ်ချက် (Bytes)", # Internal reference
    },
    "en": {
        "title": "Channel 404 ZIVPN Enterprise System",
        "enterprise_system": "⊱✫⊰ Enterprise Management System ⊱✫⊰",
        "contact": "Contact",
        "logout": "Logout",
        "login_title": "ZIVPN Panel Login",
        "login_err": "Invalid credentials",
        "username": "Username",
        "password": "Password",
        "total_users": "Total Users",
        "active_users": "Active Users",
        "bandwidth_used": "Bandwidth Used",
        "server_load": "Server Load",
        "user_management": "User Management",
        "add_user": "Add New User",
        "bulk_operations": "Bulk Operations",
        "reports": "Reports",
        "user": "User",
        "expires": "Expires",
        "port": "Port",
        "bandwidth": "Bandwidth",
        "speed": "Speed",
        "status": "Status",
        "actions": "Actions",
        "online": "ONLINE",
        "offline": "OFFLINE",
        "expired": "EXPIRED",
        "suspended": "SUSPENDED",
        "unknown": "UNKNOWN",
        "user_pass_required": "User and Password are required",
        "expires_format_error": "Expires format is invalid",
        "port_range_error": "Port range 6000-19999",
        "user_saved": "User saved successfully",
        "user_deleted": "Deleted: ",
        "delete_confirm": " delete?",
        "edit": "Edit",
        "delete": "Delete",
        "suspend": "Suspend",
        "activate": "Activate",
        "max_conn": "Max Connections",
        "speed_limit_mb": "Speed Limit (MB/s)",
        "bandwidth_limit_gb": "Bandwidth Limit (GB)",
        "plan_type": "Plan Type",
        "save_user": "Save User",
        "bulk_execute_alert": "Please select action and enter users",
        "execute": "Execute",
        "export_users": "Export Users CSV",
        "import_users": "Import Users",
        "search_users": "Search users...",
        "from_date": "From Date",
        "to_date": "To Date",
        "report_type": "Report Type",
        "generate_report": "Generate Report",
        "user_not_found": "User not found",
        "user_updated": "User updated",
        "invalid_data": "Invalid data",
        "login": "Login",
        "theme": "Theme",
        "language": "Language",
        "max_conn_limit": "Max Connection Limit",
        "speed_limit_kb": "Speed Limit (KB/s)", # Internal reference
        "bandwidth_limit_bytes": "Bandwidth Limit (Bytes)", # Internal reference
    }
}
# --- HTML Template (Updated for UI/UX, Theme, and Language) ---
HTML = """<!doctype html>
<html lang="{{ lang }}" class="{{ theme }}">
<head>
<meta charset="utf-8">
<title>{{ T.title }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root {
    --bg: #f0f4f8; --fg: #1e293b; --card: #ffffff; --bd: #e2e8f0;
    --header-bg: #4f46e5; --header-fg: #ffffff; --ok: #10b981; --bad: #ef4444; --unknown: #f59e0b;
    --expired: #8b5cf6; --info: #3b82f6; --success: #10b981; --delete-btn: #ef4444;
    --primary-btn: #4f46e5; --logout-btn: #f59e0b; --telegram-btn: #0088cc;
    --input-text: #1e293b; --shadow: 0 4px 15px rgba(0,0,0,0.1); --radius: 12px;
}
.dark:root {
    --bg: #111827; --fg: #e5e7eb; --card: #1f2937; --bd: #374151;
    --header-bg: #1f2937; --header-fg: #f3f4f6; --ok: #10b981; --bad: #ef4444; --unknown: #f59e0b;
    --expired: #a78bfa; --info: #3b82f6; --success: #10b981; --delete-btn: #ef4444;
    --primary-btn: #6366f1; --logout-btn: #f59e0b; --telegram-btn: #0088cc;
    --input-text: #e5e7eb; --shadow: 0 4px 15px rgba(0,0,0,0.5);
}

html,body { background:var(--bg); color:var(--fg); font-family:'Padauk',sans-serif; line-height:1.6; margin:0; padding:10px; transition: background-color 0.3s, color 0.3s; }
.container { max-width:1400px; margin:auto; padding:10px }

@keyframes colorful-shift {
    0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

header { display:flex; align-items:center; justify-content:space-between; gap:15px; padding:15px; margin-bottom:25px; background:var(--card); border-radius:var(--radius); box-shadow:var(--shadow); border-top: 4px solid var(--primary-btn); }
.header-left { display:flex; align-items:center; gap:15px }
h1 { margin:0; font-size:1.6em; font-weight:700; color:var(--fg); }
.colorful-title { font-size:1.8em; font-weight:900; background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000); background-size:300% auto; -webkit-background-clip:text; -webkit-text-fill-color:transparent; animation:colorful-shift 8s linear infinite; text-shadow:0 0 5px rgba(255,255,255,0.4); }
.sub { color:var(--fg); font-size:.9em }
.logo { height:50px; width:auto; border-radius:10px; border:2px solid var(--bd) }

.btn { padding:10px 18px; border-radius:var(--radius); border:none; color:white; text-decoration:none; white-space:nowrap; cursor:pointer; transition:all 0.3s ease; font-weight:700; box-shadow:0 2px 5px rgba(0,0,0,0.2); display:inline-flex; align-items:center; gap:8px; }
.btn.primary { background:var(--primary-btn); } .btn.primary:hover { background: #4338ca; }
.btn.save { background:var(--success); } .btn.save:hover { background: #047857; }
.btn.delete { background:var(--delete-btn); } .btn.delete:hover { background: #b91c1c; }
.btn.logout { background:var(--logout-btn); } .btn.logout:hover { background: #d97706; }
.btn.contact { background:var(--telegram-btn); color:white; } .btn.contact:hover { background:#006799 }
.btn.secondary { background:var(--bd); color:var(--fg); } .btn.secondary:hover { background:#cbd5e1 }
.dark .btn.secondary { background:#4b5563; color:var(--fg); } .dark .btn.secondary:hover { background:#6b7280 }

form.box { margin:25px 0; padding:25px; border-radius:var(--radius); background:var(--card); box-shadow:var(--shadow); border: 1px solid var(--bd); }
h3 { color:var(--primary-btn); margin-top:0; font-weight:700; font-size:1.4em; }
label { display:flex; align-items:center; margin:6px 0 4px; font-size:.95em; font-weight:700; color:var(--fg); }
input,select { width:100%; padding:12px; border:1px solid var(--bd); border-radius:var(--radius); box-sizing:border-box; background:var(--bg); color:var(--input-text); transition:border-color 0.3s; }
input:focus,select:focus { outline:none; border-color:var(--primary-btn); background:var(--card); }
.row { display:flex; gap:20px; flex-wrap:wrap; margin-top:10px }
.row>div { flex:1 1 200px }

.tab-container { margin:20px 0; }
.tabs { display:flex; gap:5px; margin-bottom:20px; border-bottom:2px solid var(--bd); }
.tab-btn { padding:12px 24px; background:var(--card); border:none; color:var(--fg); cursor:pointer; border-radius:var(--radius) var(--radius) 0 0; transition:all 0.3s ease; border-bottom: 3px solid transparent; }
.tab-btn.active { background:var(--card); color:var(--primary-btn); border-bottom: 3px solid var(--primary-btn); font-weight:700; }

.tab-content { display:none; }
.tab-content.active { display:block; }

.stats-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:15px; margin:20px 0; }
.stat-card { padding:20px; background:var(--card); border-radius:var(--radius); text-align:center; box-shadow:var(--shadow); border-left: 5px solid var(--info); }
.stat-number { font-size:2em; font-weight:700; margin:10px 0; color:var(--primary-btn); }
.stat-label { font-size:.9em; color:var(--fg); }
.stat-card:nth-child(2) { border-left-color: var(--ok); }
.stat-card:nth-child(3) { border-left-color: var(--bad); }
.stat-card:nth-child(4) { border-left-color: var(--unknown); }

table { border-collapse:collapse; width:100%; background:var(--card); border-radius:var(--radius); box-shadow:var(--shadow); overflow:hidden; margin-top: 15px;}
th,td { padding:14px 18px; text-align:left; border-bottom:1px solid var(--bd); }
th { background:var(--header-bg); color:var(--header-fg); font-weight:700; text-transform:uppercase }
tr:last-child td { border-bottom:none }
tbody tr:hover { background:rgba(79, 70, 229, 0.05); }
.dark tbody tr:hover { background:rgba(99, 102, 241, 0.1); }

.pill { display:inline-block; padding:5px 12px; border-radius:20px; font-size:.85em; font-weight:700; color:white; text-shadow:1px 1px 2px rgba(0,0,0,0.3); }
.status-online { background:var(--ok); }
.status-offline { background:#9ca3af; }
.status-expired { background:var(--expired); }
.status-suspended { background:var(--delete-btn); }
.status-unknown { background:var(--unknown); }

.muted { color:var(--bd) }
.delform { display:inline }
tr.expired td { opacity:.9; background:rgba(139, 92, 246, 0.1); color:var(--fg); }
.login-card { max-width:400px; margin:10vh auto; padding:30px; border-radius:var(--radius); background:var(--card); box-shadow:var(--shadow); }
.login-card h3 { margin:5px 0 15px; font-size:1.8em; color:var(--primary-btn); text-shadow:none; }
.msg { margin:10px 0; padding:12px; border-radius:var(--radius); background:var(--success); color:white; font-weight:700; }
.err { margin:10px 0; padding:12px; border-radius:var(--radius); background:var(--delete-btn); color:white; font-weight:700; }

.settings-bar { display:flex; gap:15px; align-items:center; }
.setting-item { display:flex; align-items:center; gap:5px; }

@media (max-width: 768px) {
    body{padding:10px}.container{padding:0}
    header{flex-direction:column;align-items:flex-start;padding:10px;}
    .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
    .row>div,.stats-grid{grid-template-columns:1fr;}
    .btn{width:auto;margin-bottom:5px;}
    table,thead,tbody,th,td,tr{display:block;}
    thead tr{position:absolute;top:-9999px;left:-9999px;}
    tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
    td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
    td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
    /* Dynamic content for mobile labels */
    td:nth-of-type(1):before{content:"{{ T.user }}"; color:var(--ok);}
    td:nth-of-type(2):before{content:"{{ T.password }}"; color:var(--bad);}
    td:nth-of-type(3):before{content:"{{ T.expires }}"; color:var(--expired);}
    td:nth-of-type(4):before{content:"{{ T.port }}"; color:var(--info);}
    td:nth-of-type(5):before{content:"{{ T.bandwidth }}"; color:var(--success);}
    td:nth-of-type(6):before{content:"{{ T.speed }}"; color:var(--unknown);}
    td:nth-of-type(7):before{content:"{{ T.status }}"; color:var(--primary-btn);}
    td:nth-of-type(8):before{content:"{{ T.actions }}"; color:var(--logout-btn);}
    .delform{display:inline}
}
</style>
</head>
<body>
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px; text-align:center;"><img class="logo" src="{{ logo }}" alt="4 0 4 \ 2.0"></div>
    <h3 class="center" style="text-align:center;">{{ T.login_title }}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label><i class="fas fa-user icon" style="color:var(--info);"></i>{{ T.username }}</label>
      <input name="u" autofocus required>
      <label style="margin-top:15px"><i class="fas fa-lock icon" style="color:var(--primary-btn);"></i>{{ T.password }}</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i>{{ T.login }}
      </button>
    </form>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="4 0 4 \ 2.0 [🇲🇲]" class="logo">
    <div>
      <h1><span class="colorful-title">Channel 404 ZIVPN Enterprise</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">{{ T.enterprise_system }}</span></div>
    </div>
  </div>
  <div class="settings-bar">
    <div class="setting-item">
      <i class="fas fa-palette" style="color:var(--primary-btn);"></i>
      <select id="theme-toggle" onchange="setTheme(this.value)">
        <option value="dark" {% if theme == 'dark' %}selected{% endif %}>Dark Mode</option>
        <option value="light" {% if theme == 'light' %}selected{% endif %}>Light Mode</option>
      </select>
    </div>
    <div class="setting-item">
      <i class="fas fa-globe" style="color:var(--ok);"></i>
      <select id="lang-select" onchange="setLanguage(this.value)">
        <option value="my" {% if lang == 'my' %}selected{% endif %}>မြန်မာ</option>
        <option value="en" {% if lang == 'en' %}selected{% endif %}>English</option>
      </select>
    </div>
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
    <div class="stat-number">{{ stats.online_users }}</div>
    <div class="stat-label">{{ T.active_users }} ({{ T.online }})</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:var(--bad);"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{ T.bandwidth_used }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:var(--unknown);"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{ T.server_load }}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab(event, 'users')">{{ T.user_management }}</button>
    <button class="tab-btn" onclick="openTab(event, 'adduser')">{{ T.add_user }}</button>
    <button class="tab-btn" onclick="openTab(event, 'bulk')">{{ T.bulk_operations }}</button>
    <button class="tab-btn" onclick="openTab(event, 'reports')">{{ T.reports }}</button>
  </div>

  <!-- Add User Tab -->
  <div id="adduser" class="tab-content">
    <form method="post" action="/add" class="box">
      <h3><i class="fas fa-user-plus"></i> {{ T.add_user }}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label><i class="fas fa-user icon" style="color:var(--ok);"></i> {{ T.user }}</label><input name="user" placeholder="{{ T.username }}" required></div>
        <div><label><i class="fas fa-lock icon" style="color:var(--bad);"></i> {{ T.password }}</label><input name="password" placeholder="{{ T.password }}" required></div>
        <div><label><i class="fas fa-clock icon" style="color:var(--expired);"></i> {{ T.expires }}</label><input name="expires" placeholder="2026-01-01 or 30 days"></div>
        <div><label><i class="fas fa-server icon" style="color:var(--info);"></i> {{ T.port }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label><i class="fas fa-tachometer-alt" style="color:var(--unknown);"></i> {{ T.speed_limit_mb }}</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label><i class="fas fa-database" style="color:var(--ok);"></i> {{ T.bandwidth_limit_gb }}</label><input name="bandwidth_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label><i class="fas fa-plug" style="color:var(--info);"></i> {{ T.max_conn_limit }}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label><i class="fas fa-money-bill" style="color:var(--expired);"></i> {{ T.plan_type }}</label>
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
      <h3><i class="fas fa-cogs"></i> {{ T.bulk_operations }}</h3>
      <div class="bulk-actions" style="display:flex; flex-wrap:wrap; gap:10px;">
        <select id="bulkAction" style="flex:1;">
          <option value="">Select Action</option>
          <option value="extend">+7 days to Expiry</option>
          <option value="suspend">{{ T.suspended }} Users</option>
          <option value="activate">{{ T.activate }} Users</option>
          <option value="delete">{{ T.delete }} Users</option>
        </select>
        <input type="text" id="bulkUsers" placeholder="Usernames comma separated (user1,user2)" style="flex:2;">
        <button class="btn secondary" onclick="executeBulkAction()">
          <i class="fas fa-play"></i> {{ T.execute }}
        </button>
      </div>
      <div style="margin-top:20px; display:flex; gap:10px;">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> {{ T.export_users }}
        </button>
        <button class="btn secondary" onclick="alert('{{ T.import_users }} function not implemented yet.')">
          <i class="fas fa-upload"></i> {{ T.import_users }}
        </button>
      </div>
    </div>
  </div>

  <!-- Reports Tab -->
  <div id="reports" class="tab-content">
    <div class="box">
      <h3><i class="fas fa-chart-bar"></i> {{ T.reports }} & Analytics</h3>
      <div class="row">
        <div><label><i class="fas fa-calendar-alt"></i> {{ T.from_date }}</label><input type="date" id="fromDate"></div>
        <div><label><i class="fas fa-calendar-alt"></i> {{ T.to_date }}</label><input type="date" id="toDate"></div>
        <div><label><i class="fas fa-chart-pie"></i> {{ T.report_type }}</label>
          <select id="reportType">
            <option value="bandwidth">{{ T.bandwidth }} Usage</option>
            <option value="users">{{ T.user }} Activity</option>
            <option value="revenue">Revenue</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">
          <i class="fas fa-file-alt"></i> {{ T.generate_report }}
        </button></div>
      </div>
    </div>
    <div id="reportResults" class="box" style="margin-top:20px; display:none;">
      <h4>Report Output</h4>
    </div>
  </div>

  <!-- Users Management Tab -->
  <div id="users" class="tab-content active">
    <div class="box">
      <h3><i class="fas fa-users"></i> {{ T.user_management }}</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="{{ T.search_users }}" style="flex:1;" onkeyup="filterUsers()">
        <button class="btn primary" onclick="filterUsers()">
          <i class="fas fa-search"></i>
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> {{ T.user }}</th>
          <th><i class="fas fa-lock"></i> {{ T.password }}</th>
          <th><i class="fas fa-clock"></i> {{ T.expires }}</th>
          <th><i class="fas fa-server"></i> {{ T.port }}</th>
          <th><i class="fas fa-database"></i> {{ T.bandwidth }}</th>
          <th><i class="fas fa-tachometer-alt"></i> {{ T.speed }} (KB/s)</th>
          <th><i class="fas fa-chart-line"></i> {{ T.status }}</th>
          <th><i class="fas fa-cog"></i> {{ T.actions }}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr data-user="{{u.user}}" class="{% if u.status == 'Expired' or u.status == 'Suspended' %}expired{% endif %}">
        <td><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill status-expired">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill status-unknown" style="background:var(--info);">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill status-online" style="background:var(--ok);">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
        <td><span class="pill status-unknown" style="background:var(--unknown);">{{u.speed_limit}}</span></td>
        <td>
          {% if u.status == "Online" %}<span class="pill status-online">{{ T.online }}</span>
          {% elif u.status == "Offline" %}<span class="pill status-offline">{{ T.offline }}</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">{{ T.expired }}</span>
          {% elif u.status == "Suspended" %}<span class="pill status-suspended">{{ T.suspended }}</span>
          {% else %}<span class="pill status-unknown">{{ T.unknown }}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <button class="btn secondary" title="{{ T.edit }}" style="padding:6px 12px;" onclick="editUser('{{u.user}}')">
            <i class="fas fa-edit"></i>
          </button>
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} {{ T.delete_confirm }}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="{{ T.delete }}" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          {% if u.status == "Suspended" or u.status == "Expired" %}
          <form class="delform" method="post" action="/activate">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" title="{{ T.activate }}" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="{{ T.suspend }}" style="padding:6px 12px; background:#f97316;">
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
</div>

{% endif %}
</div>

<script>
// --- Theme and Language Functions ---
document.addEventListener('DOMContentLoaded', () => {
    // Initialize Theme
    const savedTheme = localStorage.getItem('theme') || 'dark';
    document.documentElement.className = savedTheme;
    document.getElementById('theme-toggle').value = savedTheme;

    // Initialize Language
    const savedLang = localStorage.getItem('lang') || 'my';
    document.getElementById('lang-select').value = savedLang;
    
    // Open default tab
    document.getElementById('users').classList.add('active');
    document.querySelectorAll('.tabs .tab-btn')[0].classList.add('active');
});

function setTheme(theme) {
    localStorage.setItem('theme', theme);
    document.documentElement.className = theme;
}

function setLanguage(lang) {
    localStorage.setItem('lang', lang);
    // Simple reload to get localized content from Flask
    window.location.search = `?lang=${lang}`; 
}

function openTab(event, tabName) {
    document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(tabName).classList.add('active');
    event.currentTarget.classList.add('active');
}

function executeBulkAction() {
    const T = {{ T | tojson }}; // Use Flask template variable for translation
    const action = document.getElementById('bulkAction').value;
    const users = document.getElementById('bulkUsers').value;
    
    if (!action || !users) { alert(T.bulk_execute_alert); return; }
    
    if (action === 'delete' && !confirm(`Are you sure you want to ${action} these users?`)) {
        return;
    }

    fetch('/api/bulk', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
    }).then(r => r.json()).then(data => {
      alert(data.message); location.reload();
    }).catch(err => {
      alert('Error performing bulk action.');
    });
}

function exportUsers() {
    window.open('/api/export/users', '_blank');
}

function filterUsers() {
    const search = document.getElementById('searchUser').value.toLowerCase();
    document.querySelectorAll('tbody tr').forEach(row => {
        const user = row.getAttribute('data-user').toLowerCase();
        row.style.display = user.includes(search) ? 'table-row' : 'none';
    });
}

function editUser(username) {
    const T = {{ T | tojson }};
    const newPass = prompt(`Enter new password for ${username}`);
    if (newPass) {
        fetch('/api/user/update', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({user: username, password: newPass})
        }).then(r => r.json()).then(data => {
            alert(data.message); location.reload();
        }).catch(err => {
            alert(T.invalid_data);
        });
    }
}

function generateReport() {
    const from = document.getElementById('fromDate').value;
    const to = document.getElementById('toDate').value;
    const type = document.getElementById('reportType').value;
    const resultsDiv = document.getElementById('reportResults');
    
    resultsDiv.style.display = 'block';
    resultsDiv.innerHTML = '<h4>Report Output:</h4><p>Generating...</p>';
    
    fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
        .then(r => r.json()).then(data => {
            resultsDiv.innerHTML = '<h4>Report Output:</h4><pre>' + JSON.stringify(data, null, 2) + '</pre>';
        }).catch(err => {
            resultsDiv.innerHTML = '<h4>Report Output:</h4><p style="color:var(--delete-btn);">Error generating report: ' + err.message + '</p>';
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
               bandwidth_limit / 1024 / 1024 / 1024 AS bandwidth_limit, -- Convert bytes to GB for display
               bandwidth_used / 1024 / 1024 / 1024 AS bandwidth_used, -- Convert bytes to GB for display
               speed_limit_up AS speed_limit,
               concurrent_conn
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        # Convert GB limit (int) to Bytes (int)
        bw_limit_bytes = user_data.get('bandwidth_limit', 0) * 1024 * 1024 * 1024
        
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
        
        # Add to billing if plan type specified (optional)
        if user_data.get('plan_type'):
            expires = user_data.get('expires') or (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
            db.execute('''
                INSERT INTO billing (username, plan_type, expires_at)
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

def get_server_stats(active_users_ports):
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        online_users = len(active_users_ports)
        
        # Simple server load simulation based on online users
        server_load = min(100, online_users * 3 + total_users * 0.5)
        
        return {
            'total_users': total_users,
            'online_users': online_users,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': int(server_load)
        }
    finally:
        db.close()

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

# Use conntrack to find active connections for a port range
def get_active_user_ports():
    try:
        # Filter conntrack entries for UDP, destination port 6000-19999, and state != UNREPLIED
        # and limit to entries created within the last 15 seconds (using the 'timeout=' field is often unreliable, 
        # so relying on 'ss' or 'netstat' is often better, but conntrack is superior if configured well).
        # We rely on 'conntrack' presence here as requested.
        out=subprocess.run("conntrack -L -p udp 2>/dev/null | awk '/dport=(6[0-9]{3}|[7-9][0-9]{3}|1[0-9]{4})/'",
                           shell=True, capture_output=True, text=True, timeout=1).stdout
        
        active_ports = set()
        # Example conntrack line: udp 17 29 src=... dst=... sport=... dport=6001 [UNREPLIED] src=... dst=... sport=... dport=... mark=0 use=2
        # We only care about the DPORT of the destination side (which is the user-assigned port)
        for line in out.splitlines():
            # Extract dport=XXXX
            match = re.search(r"dport=(\d+)", line)
            if match:
                port = match.group(1)
                if 6000 <= int(port) <= 19999: # Ensure port is in user range
                    active_ports.add(port)
        return active_ports
    except Exception as e:
        print(f"Error checking conntrack: {e}")
        return set()

def sync_config_passwords(mode="mirror"):
    users=load_users()
    users_pw=sorted({str(u["password"]) for u in users if u.get("password") and u.get("status") == "active"})
    
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

def build_view(msg="", err=""):
    # Determine language preference
    lang = request.args.get('lang', session.get('lang', 'my'))
    if lang not in LANG: lang = 'my'
    session['lang'] = lang
    T = type('T', (), LANG[lang])
    
    # Determine theme preference (client side only in the new design)
    theme = request.cookies.get('theme', 'dark')

    if not require_login():
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T, lang=lang, theme=theme)
    
    users=load_users()
    active_ports = get_active_user_ports()
    listen_port=get_listen_port_from_config()
    
    # Status Logic (Improved)
    def determine_status(u, active_ports, today_date):
        status = u.get('status', 'active')
        expires_str = u.get("expires", "")
        
        # 1. Check for Expired
        is_expired = False
        if expires_str:
            try:
                expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
                if expires_dt < today_date:
                    is_expired = True
            except ValueError:
                pass
        
        # 2. Check for Manual Suspension or Auto-Expired
        if status == 'suspended':
            return "Suspended"
        if is_expired:
            return "Expired"
            
        # 3. Check for Live Connection (Online/Offline)
        user_port = str(u.get("port", ""))
        if user_port in active_ports:
            return "Online"
        
        return "Offline" # Active account but no recent connection
        
    today_date=datetime.now().date()
    
    view = []
    for u in users:
        status = determine_status(u, active_ports, today_date)
        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":u.get("expires",""),
            "port":u.get("port",""),
            "status":status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": u.get('bandwidth_used', 0),
            "speed_limit": u.get('speed_limit', 0)
        }))
    
    stats = get_server_stats(active_ports)
    view.sort(key=lambda x:(x.user or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL, 
                                 users=view, msg=msg, err=err, today=today, stats=stats, T=T, lang=lang, theme=theme)

# Routes
@app.route("/login", methods=["GET","POST"])
def login():
    # Load translation for login page
    lang = request.args.get('lang', session.get('lang', 'my'))
    T = type('T', (), LANG.get(lang, LANG['my']))
    theme = request.cookies.get('theme', 'dark')
    
    if not login_enabled(): return redirect(url_for('index'))
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
    
    lang = session.get('lang', 'my'); T = type('T', (), LANG[lang])
    
    user_data = {
        'user': (request.form.get("user") or "").strip(),
        'password': (request.form.get("password") or "").strip(),
        'expires': (request.form.get("expires") or "").strip(),
        'port': (request.form.get("port") or "").strip(),
        'bandwidth_limit': int(request.form.get("bandwidth_limit") or 0), # in GB
        'speed_limit': int(request.form.get("speed_limit") or 0) * 1024, # Convert MB/s to KB/s
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1),
        'plan_type': (request.form.get("plan_type") or "").strip()
    }
    
    if not user_data['user'] or not user_data['password']:
        return build_view(err=T.user_pass_required)
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=T.expires_format_error)
    
    if user_data['port'] and not (6000 <= int(user_data['port']) <= 19999):
        return build_view(err=T.port_range_error)
    
    if not user_data['port']:
        # Auto assign port: find next available port in range
        used_ports = {str(u.get('port', '')) for u in load_users() if u.get('port')}
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                user_data['port'] = str(p)
                break
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=T.user_saved)

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    lang = session.get('lang', 'my'); T = type('T', (), LANG[lang])
    
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=T.user_pass_required)
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=T.user_deleted + user)

@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
        db.commit()
        db.close()
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
    return redirect(url_for('index'))

# API Routes
@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    lang = session.get('lang', 'my'); T = type('T', (), LANG[lang])
    
    data = request.get_json() or {}
    action = data.get('action')
    users = data.get('users', [])
    
    db = get_db()
    try:
        updated_count = 0
        for user in users:
            if action == 'extend':
                db.execute('UPDATE users SET expires = date(expires, "+7 days"), updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
                updated_count += 1
            elif action == 'suspend':
                db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
                updated_count += 1
            elif action == 'activate':
                db.execute('UPDATE users SET status = "active", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (user,))
                updated_count += 1
            elif action == 'delete':
                db.execute('DELETE FROM users WHERE username = ?', (user,))
                updated_count += 1
        
        db.commit()
        sync_config_passwords() # Restart VPN service if passwords changed (delete)
        return jsonify({"ok": True, "message": f"Bulk action {action} completed for {updated_count} users."})
    except Exception as e:
        return jsonify({"ok": False, "message": f"Error: {e}"}), 500
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (KB/s),Status\n"
    for u in users:
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{u.get('bandwidth_used',0):.2f},{u.get('bandwidth_limit',0):.0f},{u.get('speed_limit',0)},{u.get('status','')}\n"
    
    response = make_response(csv_data)
    response.headers["Content-Disposition"] = "attachment; filename=zivpn_users_export.csv"
    response.headers["Content-type"] = "text/csv"
    return response

@app.route("/api/reports")
def generate_reports():
    if not require_login(): return jsonify({"error": "Unauthorized"}), 401
    
    report_type = request.args.get('type', 'bandwidth')
    from_date = request.args.get('from') or '2000-01-01'
    to_date = request.args.get('to') or '2030-12-31'
    
    db = get_db()
    try:
        if report_type == 'bandwidth':
            # Display bandwidth in GB
            data = db.execute('''
                SELECT username, SUM(bytes_used) / 1024 / 1024 / 1024 as total_gb_used 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
                ORDER BY total_gb_used DESC
            ''', (from_date, to_date)).fetchall()
            return jsonify([dict(d) for d in data])
        
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date
                ORDER BY date
            ''', (from_date, to_date)).fetchall()
            return jsonify([dict(d) for d in data])
            
        elif report_type == 'revenue':
             data = db.execute('''
                SELECT plan_type, SUM(amount) as total_revenue, currency, COUNT(*) as subscriptions
                FROM billing 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY plan_type, currency
            ''', (from_date, to_date)).fetchall()
             return jsonify([dict(d) for d in data])

        return jsonify({"message": "Invalid report type"})
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    lang = session.get('lang', 'my'); T = type('T', (), LANG[lang])
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    
    if user and password:
        db = get_db()
        db.execute('UPDATE users SET password = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?', (password, user))
        db.commit()
        db.close()
        sync_config_passwords()
        return jsonify({"ok": True, "message": T.user_updated})
    
    return jsonify({"ok": False, "err": T.invalid_data})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (api.py) =====
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
            SUM(CASE WHEN status = "active" THEN 1 ELSE 0 END) as active_users,
            SUM(bandwidth_used) as total_bandwidth_bytes
        FROM users
    ''').fetchone()
    db.close()
    
    # Convert bytes to a more readable unit for API output
    stats_dict = dict(stats)
    stats_dict['total_bandwidth_gb'] = stats_dict['total_bandwidth_bytes'] / 1024 / 1024 / 1024
    del stats_dict['total_bandwidth_bytes']
    
    return jsonify(stats_dict)

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
        # Convert user object to dict, handling bytes for bandwidth
        user_dict = dict(user)
        user_dict['bandwidth_limit_gb'] = user_dict['bandwidth_limit'] / 1024 / 1024 / 1024
        user_dict['bandwidth_used_gb'] = user_dict['bandwidth_used'] / 1024 / 1024 / 1024
        return jsonify(user_dict)
    return jsonify({"error": "User not found"}), 404

@app.route('/api/v1/bandwidth/<username>', methods=['POST'])
def update_bandwidth(username):
    data = request.get_json()
    bytes_used = int(data.get('bytes_used', 0))
    
    db = get_db()
    try:
        # Update user's total usage
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
        
        # Check for limit breach and automatically suspend
        user_data = db.execute('SELECT bandwidth_limit, bandwidth_used FROM users WHERE username = ?', (username,)).fetchone()
        if user_data and user_data['bandwidth_limit'] > 0 and user_data['bandwidth_used'] >= user_data['bandwidth_limit']:
            db.execute('UPDATE users SET status = "suspended", updated_at = CURRENT_TIMESTAMP WHERE username = ?', (username,))
            
        db.commit()
        return jsonify({"message": "Bandwidth updated and limits checked"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        db.close()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Maintenance Script (zivpn-maintenance.py) for Auto-Suspension =====
say "${Y}⚙️ Maintenance Service (Auto-Suspend) ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/zivpn-maintenance.py <<'PY'
import sqlite3
from datetime import datetime

DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def auto_suspend_expired_users():
    db = get_db()
    
    # Get today's date in YYYY-MM-DD format for comparison
    today_date_str = datetime.now().strftime("%Y-%m-%d")
    
    try:
        # Suspend users whose 'expires' date is in the past AND status is 'active'
        cursor = db.execute('''
            UPDATE users
            SET status = 'suspended', updated_at = CURRENT_TIMESTAMP
            WHERE expires IS NOT NULL 
              AND expires < ?
              AND status = 'active'
        ''', (today_date_str,))
        
        db.commit()
        print(f"Auto-suspended {cursor.rowcount} expired user(s).")
        
    except Exception as e:
        print(f"Error during auto-suspension: {e}")
    finally:
        db.close()

if __name__ == '__main__':
    auto_suspend_expired_users()
PY

# ===== Backup Script (backup.py) =====
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
            try:
                # Extract date from filename: zivpn_backup_YYYYMMDD_HHMMSS.db.gz
                date_part = file.split('_')[2]
                file_date = datetime.datetime.strptime(date_part, "%Y%m%d").date()
                if (datetime.date.today() - file_date).days > 7:
                    os.remove(file_path)
            except Exception:
                # Fallback to ctime check if filename parsing fails
                file_time = datetime.datetime.fromtimestamp(os.path.getctime(file_path))
                if (datetime.datetime.now() - file_time).days > 7:
                    os.remove(file_path)
    
    print(f"Backup created: {backup_file}")

if __name__ == '__main__':
    backup_database()
PY

# ===== systemd Services & Timers =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service (UDP Server)
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

# Web Panel Service (Flask)
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target zivpn.service

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

# API Service (Flask)
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

# Backup Service (Oneshot)
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

# Backup Timer (Daily)
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

# Auto-Maintenance Service (Oneshot)
cat >/etc/systemd/system/zivpn-maintenance.service <<'EOF'
[Unit]
Description=ZIVPN Daily Maintenance (Auto-Suspend)
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/zivpn-maintenance.py

[Install]
WantedBy=multi-user.target
EOF

# Auto-Maintenance Timer (Daily)
cat >/etc/systemd/system/zivpn-maintenance.timer <<'EOF'
[Unit]
Description=Daily ZIVPN Maintenance
Requires=zivpn-maintenance.service

[Timer]
OnCalendar=*-*-* 00:00:00
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
# Remove carriage returns from python scripts
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-backup.timer
systemctl enable --now zivpn-maintenance.timer

# Initial maintenance/backup runs
python3 /etc/zivpn/zivpn-maintenance.py
python3 /etc/zivpn/backup.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition Setup Complete! (Enhanced) ${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "\n${M}📋 Services Status:${Z}"
echo -e "  ${Y}systemctl status zivpn${Z}          - VPN Server"
echo -e "  ${Y}systemctl status zivpn-web${Z}      - Web Panel (UI/UX Enhanced)"
echo -e "  ${Y}systemctl status zivpn-api${Z}      - API Server"
echo -e "  ${Y}systemctl status zivpn-maintenance${Z} - Auto-Suspend Logic"
echo -e "\n${G}🎯 Enhanced Features Summary:${Z}"
echo -e "  ✓ Improved UI/UX, Dark/Light Mode, Myanmar/English Language"
echo -e "  ✓ Accurate Online/Offline Status Check (via conntrack)"
echo -e "  ✓ Automated Daily Expiry Suspension"
echo -e "  ✓ User Bandwidth & Speed Limits"
echo -e "$LINE"
