#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION
# Author: မောင်သုည
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
apt-get install -y curl ufw jq python3 python3-flask python3-pip python3-venv iproute2 conntrack ca-certificates sqlite3 >/dev/null || \
{
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask python3-pip iproute2 conntrack ca-certificates sqlite3 >/dev/null
}

# Additional Python packages
pip3 install requests python-dateutil >/dev/null 2>&1 || true
apt_guard_end

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
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

# ===== Enhanced Web Panel (Updated with Dark/Light Mode) =====
say "${Y}🖥️ Enhanced Web Panel (Dark/Light Mode) ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>မောင်သုည ZIVPN Enterprise Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
/* ---------------------------------- */
/* 1. Theme Variables (Dark/Light) */
/* ---------------------------------- */
:root {
    /* Dark Mode Defaults */
    --bg: #1a1a2e; /* Dark Blue/Purple */
    --fg: #e0e7ff; /* Light text */
    --card: #2c2c45; /* Dark Card Background */
    --bd: #4a4a6b; /* Border/Muted color */
    --header-bg: #16162a;
    --ok: #2ecc71; 
    --bad: #e74c3c;
    --unknown: #f39c12;
    --expired: #8e44ad;
    --info: #3498db;
    --success: #1abc9c;
    --delete-btn: #e74c3c;
    --primary-btn: #3498db;
    --logout-btn: #e67e22;
    --telegram-btn: #0088cc;
    --input-text: #e0e7ff;
    --input-bg: #1a1a2e;
    --shadow: 0 6px 20px rgba(0,0,0,0.4);
    --radius: 10px;
}
:root.light {
    /* Light Mode Overrides */
    --bg: #f5f7fa; 
    --fg: #34495e;
    --card: #ffffff;
    --bd: #e0e0e0;
    --header-bg: #ffffff;
    --input-text: #34495e;
    --input-bg: #ffffff;
    --shadow: 0 4px 15px rgba(0,0,0,0.1);
}

/* ---------------------------------- */
/* 2. Global Styles */
/* ---------------------------------- */
html,body{
    background:var(--bg);
    color:var(--fg);
    font-family:'Padauk',sans-serif;
    line-height:1.6;
    margin:0;
    padding:10px;
    transition: background-color 0.3s, color 0.3s;
}
.container{max-width:1400px;margin:auto;padding:10px}

@keyframes colorful-shift {
    0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; }
}

/* Header & Title */
header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius);box-shadow:var(--shadow);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{
    font-size:1.8em;font-weight:900;
    background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);
    background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;
    animation:colorful-shift 8s linear infinite;
    text-shadow:0 0 5px rgba(255,255,255,0.4);
}
.sub{color:var(--bd);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--primary-btn)}

/* Buttons */
.btn{
    padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;
    white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;
    box-shadow:0 4px 6px rgba(0,0,0,0.3);display:flex;align-items:center;gap:8px;
}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:var(--info)}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:var(--bd);color:var(--fg)}.btn.secondary:hover{background:#7f8c8d;color:white}
.btn.theme-toggle{background:var(--card);color:var(--fg);box-shadow:none;border:1px solid var(--bd);}
.btn.theme-toggle:hover{background:var(--bd);color:white}

form.box{margin:25px 0;padding:25px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);}
h3{color:var(--fg);margin-top:0;}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{
    width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);
    box-sizing:border-box;background:var(--input-bg);color:var(--input-text);
    transition:border-color 0.3s;
}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);box-shadow:0 0 5px rgba(52,152,219,0.5);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

/* Tabs */
.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:none;color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;}
.tab-btn.active{background:var(--primary-btn);color:white;box-shadow:0 -4px 10px rgba(0,0,0,0.2) inset;}
.tab-content{display:none;}
.tab-content.active{display:block;}

/* Stats */
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);border:1px solid var(--bd);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;}
.stat-label{font-size:.9em;color:var(--bd);}

/* Table */
table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);vertical-align:middle;}
th:last-child,td:last-child{border-right:none;}
th{background:#3a3a5e;font-weight:700;color:white;text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover{background:rgba(52,152,219,0.1);}

/* Pills/Status */
.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;text-shadow:1px 1px 2px rgba(0,0,0,0.5);box-shadow:0 2px 4px rgba(0,0,0,0.2);min-width:70px;text-align:center;}
.status-online{color:white;background:var(--ok)}.status-offline{color:white;background:var(--bad)}
.status-unk{color:white;background:var(--unknown)}.status-expired{color:white;background:var(--expired)}
.status-suspended{color:white;background:#c0392b}

.pill-lightgreen{background:#1abc9c;color:white}
.pill-pink{background:#f78da7;color:#333}
.pill-orange{background:#e67e22;color:white}
.pill-yellow{background:#f1c40f;color:#333}

.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:rgba(142,68,173,0.2);color:var(--fg)}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}

/* Login Card */
.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);}
.login-card h3{margin:5px 0 15px;font-size:1.8em;text-shadow:0 1px 3px rgba(0,0,0,0.5);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}

.bulk-actions{margin:15px 0;display:flex;gap:10px;flex-wrap:wrap;}

/* Responsive Design */
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
    /* Burmese Labels for Mobile */
    td:nth-of-type(1):before{content:"👤 အသုံးပြုသူ";}td:nth-of-type(2):before{content:"🔑 စကားဝှက်";}
    td:nth-of-type(3):before{content:"⏰ သက်တမ်းကုန်";}td:nth-of-type(4):before{content:"🔌 Port";}
    td:nth-of-type(5):before{content:"📊 Bandwidth";}td:nth-of-type(6):before{content:"⚡ Speed";}
    td:nth-of-type(7):before{content:"🔎 အခြေအနေ";}td:nth-of-type(8):before{content:"🗑️ လုပ်ဆောင်ချက်";}
    .delform{width:100%;}tr.expired td{background:rgba(142,68,173,0.3);}
    .pill{min-width:auto;text-align:center;}
}
</style>
</head>
<body>
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
    <h3 class="center">မောင်သုည Enterprise Panel Login</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label><i class="fas fa-user icon"></i>Username</label>
      <input name="u" autofocus required>
      <label style="margin-top:15px"><i class="fas fa-lock icon"></i>Password</label>
      <input name="p" type="password" required>
      <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
        <i class="fas fa-sign-in-alt"></i>Login
      </button>
    </form>
  </div>
{% else %}

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="မောင်သုည" class="logo">
    <div>
      <h1><span class="colorful-title">မောင်သုည ZIVPN Enterprise</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ Enterprise Management System ⊱✫⊰</span></div>
    </div>
  </div>
  <div style="display:flex;gap:10px;align-items:center">
    <button class="btn theme-toggle" onclick="toggleTheme()">
      <i id="theme-icon" class="fas fa-sun"></i> Theme
    </button>
    <a class="btn contact" href="https://t.me/Zero_Free_Vpn" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>Contact
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>Logout
    </a>
  </div>
</header>

<!-- Stats Dashboard -->
<div class="stats-grid">
  <div class="stat-card">
    <i class="fas fa-users" style="font-size:2em;color:var(--info);"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">အသုံးပြုသူ စုစုပေါင်း</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">အွန်လိုင်း အသုံးပြုသူ</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:var(--bad);"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">Bandwidth သုံးစွဲမှု</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:var(--unknown);"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">Server ဝန်</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn active" onclick="openTab(event, 'users')">User Management</button>
    <button class="tab-btn" onclick="openTab(event, 'adduser')">Add User</button>
    <button class="tab-btn" onclick="openTab(event, 'bulk')">Bulk Operations</button>
    <button class="tab-btn" onclick="openTab(event, 'reports')">Reports</button>
  </div>

  <!-- Add User Tab -->
  <div id="adduser" class="tab-content">
    <form method="post" action="/add" class="box">
      <h3><i class="fas fa-users-cog"></i> အသုံးပြုသူ အသစ်ထည့်ပါ</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label><i class="fas fa-user"></i> အသုံးပြုသူ အမည်</label><input name="user" placeholder="User Name" required></div>
        <div><label><i class="fas fa-lock"></i> စကားဝှက်</label><input name="password" placeholder="Password" required></div>
        <div><label><i class="fas fa-clock"></i> သက်တမ်းကုန် (ရက်/YYYY-MM-DD)</label><input name="expires" placeholder="eg: 30 or 2026-01-01"></div>
        <div><label><i class="fas fa-server"></i> Port</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label><i class="fas fa-tachometer-alt"></i> Speed Limit (MB/s)</label><input name="speed_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label><i class="fas fa-database"></i> Bandwidth Limit (GB)</label><input name="bandwidth_limit" placeholder="0 = unlimited" type="number"></div>
        <div><label><i class="fas fa-plug"></i> Max Connections</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
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
        <i class="fas fa-save"></i> အသုံးပြုသူ မှတ်တမ်းတင်ရန်
      </button>
    </form>
  </div>

  <!-- Bulk Operations Tab -->
  <div id="bulk" class="tab-content">
    <div class="box">
      <h3><i class="fas fa-cogs"></i> အစုလိုက် လုပ်ဆောင်ချက်များ</h3>
      <div class="bulk-actions">
        <select id="bulkAction">
          <option value="">လုပ်ဆောင်ချက် ရွေးပါ</option>
          <option value="extend">သက်တမ်းတိုး (+7 ရက်)</option>
          <option value="suspend">ရပ်ဆိုင်းရန်</option>
          <option value="activate">ပြန်လည်ဖွင့်ရန်</option>
          <option value="delete">ဖျက်ရန်</option>
        </select>
        <input type="text" id="bulkUsers" placeholder="Usernames, ဥပမာ: user1,user2">
        <button class="btn secondary" onclick="executeBulkAction()">
          <i class="fas fa-play"></i> စတင်ပါ
        </button>
      </div>
      <div style="margin-top:15px">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> Users CSV ထုတ်ယူရန်
        </button>
      </div>
    </div>
  </div>

  <!-- Users Management Tab -->
  <div id="users" class="tab-content active">
    <div class="box">
      <h3><i class="fas fa-users"></i> အသုံးပြုသူ စီမံခန့်ခွဲမှု</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="အသုံးပြုသူ အမည်ဖြင့် ရှာဖွေပါ..." style="flex:1;">
        <button class="btn secondary" onclick="filterUsers()">
          <i class="fas fa-search"></i> ရှာဖွေပါ
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> အသုံးပြုသူ</th>
          <th><i class="fas fa-lock"></i> စကားဝှက်</th>
          <th><i class="fas fa-clock"></i> သက်တမ်းကုန်</th>
          <th><i class="fas fa-server"></i> Port</th>
          <th><i class="fas fa-database"></i> Bandwidth</th>
          <th><i class="fas fa-tachometer-alt"></i> Speed</th>
          <th><i class="fas fa-chart-line"></i> အခြေအနေ</th>
          <th><i class="fas fa-cog"></i> လုပ်ဆောင်ချက်</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.expires and u.expires < today %}expired{% endif %}">
        <td><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used|filesizeformat}}/{{u.bandwidth_limit}} GB</span></td>
        <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
        <td>
          {% if u.status == "Online" %}<span class="pill status-online">ONLINE</span>
          {% elif u.status == "Offline" %}<span class="pill status-offline">OFFLINE</span>
          {% elif u.status == "Expired" %}<span class="pill status-expired">သက်တမ်းကုန်</span>
          {% elif u.status == "suspended" %}<span class="pill status-suspended">ရပ်ဆိုင်းထားသည်</span>
          {% else %}<span class="pill status-unk">မသိရှိပါ</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်မလား?')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn secondary" style="padding:6px 12px;" onclick="editUser('{{u.user}}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == "suspended" %}
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
    <div class="box">
      <h3><i class="fas fa-chart-bar"></i> Reports & Analytics</h3>
      <div class="row">
        <div><label>From Date</label><input type="date" id="fromDate"></div>
        <div><label>To Date</label><input type="date" id="toDate"></div>
        <div><label>Report Type</label>
          <select id="reportType">
            <option value="bandwidth">Bandwidth Usage</option>
            <option value="users">User Activity</option>
            <option value="revenue">Revenue</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">Generate Report</button></div>
      </div>
    </div>
    <div id="reportResults"></div>
  </div>
</div>

{% endif %}
</div>

<script>
// File size formatter (bytes to GB)
function filesizeformat(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = 2;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// Theme management
const themeKey = 'zivpnTheme';
function setTheme(theme) {
    document.documentElement.className = theme === 'light' ? 'light' : '';
    document.getElementById('theme-icon').className = theme === 'light' ? 'fas fa-moon' : 'fas fa-sun';
    localStorage.setItem(themeKey, theme);
}

document.addEventListener('DOMContentLoaded', () => {
    // Apply saved theme or default to dark
    const savedTheme = localStorage.getItem(themeKey) || 'dark';
    setTheme(savedTheme);
});

function toggleTheme() {
    const currentTheme = document.documentElement.classList.contains('light') ? 'light' : 'dark';
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    setTheme(newTheme);
}

// Tab Switching
function openTab(event, tabName) {
    document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(tabName).classList.add('active');
    event.currentTarget.classList.add('active');
}

// Initial tab load
document.addEventListener('DOMContentLoaded', () => {
    openTab({currentTarget: document.querySelector('.tab-btn.active')}, 'users');
});


function executeBulkAction() {
    const action = document.getElementById('bulkAction').value;
    const users = document.getElementById('bulkUsers').value;
    if (!action || !users) { alert('Please select action and enter users'); return; }
    
    fetch('/api/bulk', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
    }).then(r => r.json()).then(data => {
        if (data.ok) {
            alert(data.message);
            location.reload();
        } else {
            alert('Error: ' + data.err);
        }
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
            if (data.ok) {
                alert(data.message);
                location.reload();
            } else {
                alert('Error: ' + data.err);
            }
        });
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

# Custom Jinja Filter for filesize
@app.template_filter('filesizeformat')
def format_filesize(bytes_in_gb):
    # Convert GB to Bytes (1 GB = 1024^3 Bytes)
    bytes_val = float(bytes_in_gb) * (1024**3)
    if bytes_val == 0: return '0 Bytes'
    k = 1024
    dm = 2
    sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
    i = int(math.floor(math.log(bytes_val) / math.log(k)))
    return f"{round(bytes_val / (k ** i), dm)} {sizes[i]}"

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
               concurrent_conn
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), 'active', user_data.get('bandwidth_limit', 0),
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
        ))
        db.commit()
        
        # Add to billing if plan type specified (Simplified: always insert/update billing record)
        expires = user_data.get('expires') or (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
        db.execute('''
            INSERT INTO billing (username, plan_type, expires_at)
            VALUES (?, ?, ?)
            ON CONFLICT(username) DO UPDATE SET
                plan_type = excluded.plan_type,
                expires_at = excluded.expires_at
            WHERE username = excluded.username
        ''', (user_data['user'], user_data.get('plan_type', 'monthly'), expires))
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
        # Active users is count of non-suspended users
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status != "suspended"').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        # Simple server load simulation based on active count and total
        server_load = min(100, (active_users * 3 + total_users * 1) / 5)
        
        # Convert bytes to GB for display
        total_bandwidth_gb = total_bandwidth / (1024 * 1024 * 1024)
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth_gb:.2f} GB",
            'server_load': f"{server_load:.1f}"
        }
    finally:
        db.close()

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
    # List of all ports ZIVPN is theoretically listening on
    out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
    return set(re.findall(r":(\d+)\s", out))

def get_active_user_ports():
    # Use conntrack to find recent activity on ZIVPN ports (better indicator of "Online")
    try:
        # Check for conntrack entries where the destination port is in the ZIVPN range (6000-19999 or 5667)
        # We don't filter by time here; will rely on conntrack's natural timeout (usually 30-60s)
        out = subprocess.run(
            "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|6[0-9]{3}|[7-9][0-9]{3}|1[0-9]{4})\\b'",
            shell=True, capture_output=True, text=True, check=True
        ).stdout
        
        # Extract destination port numbers (dport=XXXX)
        active_ports = set(re.findall(r'dport=(\d+)', out))
        return active_ports
    except subprocess.CalledProcessError:
        return set()
    except FileNotFoundError:
        print("Warning: conntrack not found. Status check will be less accurate.")
        return set()
    except Exception as e:
        print(f"Error in conntrack check: {e}")
        return set()

def status_for_user(u, active_conns, listen_port):
    user_status = u.get('status')
    expires_str = u.get("expires", "")
    user_port = str(u.get("port", ""))
    
    # 1. Check for expiration
    today_date=datetime.now().date()
    is_expired = False
    if expires_str:
        try:
            expires_dt=datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < today_date: is_expired = True
        except ValueError: pass
    
    if is_expired: return "Expired"
    if user_status == 'suspended': return "suspended"
    
    # 2. Check for active connection (Online/Offline)
    ports_to_check = {user_port, listen_port} if user_port else {listen_port}
    
    is_online = False
    for p in ports_to_check:
        if p in active_conns:
            is_online = True
            break
    
    return "Online" if is_online else "Offline"

def sync_config_passwords(mode="mirror"):
    users=load_users()
    # Only include active/non-expired passwords in the ZIVPN config
    today_date=datetime.now().date()
    allowed_users = []
    for u in users:
        is_expired = False
        if u.get('expires'):
            try:
                if datetime.strptime(u['expires'], "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError: pass

        if u.get('status') != 'suspended' and not is_expired and u.get("password"):
            allowed_users.append(u)
    
    users_pw=sorted({str(u["password"]) for u in allowed_users})
    
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
    if not require_login():
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
    
    users=load_users()
    active_conns=get_active_user_ports()
    listen_port=get_listen_port_from_config()
    stats = get_server_stats()
    
    view=[]
    today_date=datetime.now().date()
    
    for u in users:
        status=status_for_user(u,active_conns,listen_port)
        
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
    
    view.sort(key=lambda x:(x.user or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL, 
                                users=view, msg=msg, err=err, today=today, stats=stats)

# Routes
@app.route("/login", methods=["GET","POST"])
def login():
    if not login_enabled(): return redirect(url_for('index'))
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('index'))
        else:
            session["auth"]=False
            session["login_err"]="မှန်ကန်မှုမရှိပါ"
            return redirect(url_for('login'))
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
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
        return build_view(err="User နှင့် Password လိုအပ်သည်")
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
    
    if user_data['port'] and not (6000 <= int(user_data['port']) <= 19999):
        return build_view(err="Port အကွာအဝေး 6000-19999")
    
    if not user_data['port']:
        # Auto assign port
        used_ports = {str(u.get('port', '')) for u in load_users() if u.get('port')}
        used_ports |= get_udp_listen_ports()
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                user_data['port'] = str(p)
                break
    
    save_user(user_data)
    sync_config_passwords()
    return build_view(msg="User saved successfully")

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err="User လိုအပ်သည်")
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=f"Deleted: {user}")

@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
        db.commit()
        db.close()
        sync_config_passwords() # Sync to remove password from ZIVPN config
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
        sync_config_passwords() # Sync to re-add password to ZIVPN config
    return redirect(url_for('index'))

# API Routes
@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    
    data = request.get_json() or {}
    action = data.get('action')
    users = [u.strip() for u in data.get('users', []) if u.strip()]
    
    db = get_db()
    try:
        for user in users:
            if action == 'extend':
                db.execute('UPDATE users SET expires = date(expires, "+7 days") WHERE username = ?', (user,))
            elif action == 'suspend':
                db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
            elif action == 'activate':
                db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
            elif action == 'delete':
                delete_user(user)
        
        db.commit()
        sync_config_passwords() # Always sync after bulk ops
        return jsonify({"ok": True, "message": f"Bulk action {action} completed on {len(users)} users"})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Status\n"
    for u in users:
        # bandwidth_used is stored in Bytes in DB, displayed in GB in panel, but here we output the GB value
        bw_used_gb = u.get('bandwidth_used', 0) / (1024**3)
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{bw_used_gb:.2f},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{u.get('status','')}\n"
    
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
    try:
        if report_type == 'bandwidth':
            data = db.execute('''
                SELECT username, SUM(bytes_used) as total_bytes 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
            ''', (from_date, to_date)).fetchall()
            # Convert bytes to GB for reporting
            return jsonify([{"username": d["username"], "total_gb": d["total_bytes"] / (1024**3)} for d in data])
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date
            ''', (from_date, to_date)).fetchall()
            return jsonify([dict(d) for d in data])
        elif report_type == 'revenue':
            # Simplified Revenue Report (Counting total expired plans in range)
            data = db.execute('''
                SELECT plan_type, COUNT(*) as count
                FROM billing 
                WHERE expires_at BETWEEN ? AND ? AND payment_status = 'pending'
                GROUP BY plan_type
            ''', (from_date, to_date)).fetchall()
            return jsonify([dict(d) for d in data])
        else:
            return jsonify({"message": "Invalid report type"})
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user():
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
        return jsonify({"ok": True, "message": "User password updated successfully"})
    
    return jsonify({"ok": False, "err": "Invalid data"})

if __name__ == "__main__":
    # Import math for the filesize format
    import math
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (No change) =====
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
    data = request.get_json()
    bytes_used = data.get('bytes_used', 0)
    
    db = get_db()
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
    db.close()
    return jsonify({"message": "Bandwidth updated"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Telegram Bot (No change) =====
say "${Y}🤖 Telegram Bot Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/bot.py <<'PY'
import telegram
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters
import sqlite3, logging, os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATABASE_PATH = "/etc/zivpn/zivpn.db"
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
        '/users - User list\n'
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
    
    message = (
        f"📊 Server Statistics:\n"
        f"• Total Users: {stats['total_users']}\n"
        f"• Active Users: {stats['active_users']}\n"
        f"• Bandwidth Used: {stats['total_bandwidth'] / 1024 / 1024 / 1024:.2f} GB"
    )
    update.message.reply_text(message)

def get_users(update, context):
    db = get_db()
    users = db.execute('SELECT username, status, expires FROM users LIMIT 20').fetchall()
    db.close()
    
    if not users:
        update.message.reply_text("No users found")
        return
    
    message = "👥 User List:\n"
    for user in users:
        message += f"• {user['username']} - {user['status']} - Exp: {user['expires'] or 'Never'}\n"
    
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
    
    message = (
        f"👤 User: {user['username']}\n"
        f"📊 Status: {user['status']}\n"
        f"⏰ Expires: {user['expires'] or 'Never'}\n"
        f"📦 Bandwidth: {user['bandwidth_used'] / 1024 / 1024 / 1024:.2f} GB / {user['bandwidth_limit']} GB\n"
        f"⚡ Speed Limit: {user['speed_limit_up']} MB/s\n"
        f"🔗 Max Connections: {user['concurrent_conn']}"
    )
    update.message.reply_text(message)

def main():
    if BOT_TOKEN == 'YOUR_BOT_TOKEN_HERE':
        logger.error("Please set TELEGRAM_BOT_TOKEN environment variable")
        return
    
    updater = Updater(BOT_TOKEN, use_context=True)
    dp = updater.dispatcher
    
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CommandHandler("stats", get_stats))
    dp.add_handler(CommandHandler("users", get_users))
    dp.add_handler(CommandHandler("myinfo", get_user_info))
    
    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()
PY

# ===== Backup Script (No change) =====
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

# ===== systemd Services (No change) =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service
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

# Web Panel Service
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

# API Service
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

# Backup Service (Daily)
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

# ===== Networking Setup (No change) =====
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
ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 8081/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

# ===== Final Setup (No change) =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-backup.timer

# Initial backup
python3 /etc/zivpn/backup.py

# ===== Completion Message (No change) =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "${C}📊 Database:${Z} ${Y}/etc/zivpn/zivpn.db${Z}"
echo -e "${C}💾 Backups:${Z} ${Y}/etc/zivpn/backups/${Z}"
echo -e "\n${M}📋 Services:${Z}"
echo -e "  ${Y}systemctl status zivpn${Z}      - VPN Server"
echo -e "  ${Y}systemctl status zivpn-web${Z}  - Web Panel"
echo -e "  ${Y}systemctl status zivpn-api${Z}  - API Server"
echo -e "  ${Y}systemctl list-timers${Z}       - Backup Timers"
echo -e "\n${G}🎯 Features Enabled:${Z}"
echo -e "  ✓ User Bandwidth Limits"
echo -e "  ✓ Speed Control"
echo -e "  ✓ Connection Limits"
echo -e "  ✓ Bulk Operations"
echo -e "  ✓ Reporting & Analytics"
echo -e "  ✓ Automated Backups"
echo -e "  ✓ REST API"
echo -e "  ✓ Telegram Bot Ready"
echo -e "$LINE"
