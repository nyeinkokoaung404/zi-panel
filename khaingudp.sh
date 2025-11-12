#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION V2.0 (Complete)
# Author: မောင်သုည
# Features: Complete Enterprise Management System with Enhanced UI/UX, Dark/Light Mode, Multi-Language, Auto Cleanup, Session Control.

set -euo pipefail

# ===== Pretty Colors & Functions =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI - ENTERPRISE EDITION V2.0 ${Z}\n$LINE"

# ===== Root check & apt guards (UNCHANGED) =====
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
apt_pkgs="curl ufw jq python3 python3-flask python3-pip python3-venv iproute2 conntrack ca-certificates sqlite3"
if ! apt-get install -y $apt_pkgs >/dev/null; then
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y $apt_pkgs >/dev/null
fi
# Additional Python packages
pip3 install requests python-dateutil >/dev/null 2>&1 || true
apt_guard_end

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true
systemctl stop zivpn-api.service 2>/dev/null || true
systemctl stop zivpn-bot.service 2>/dev/null || true
systemctl stop zivpn-cleanup.timer 2>/dev/null || true

# ===== Paths & Setup =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
DB="/etc/zivpn/zivpn.db"
ENVF="/etc/zivpn/web.env"
BACKUP_DIR="/etc/zivpn/backups"
mkdir -p /etc/zivpn "$BACKUP_DIR"

# ===== Download ZIVPN binary (UNCHANGED) =====
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

# ===== Enhanced Database Setup (WITH NEW COLUMNS) =====
say "${Y}🗃️ Enhanced Database ဖန်တီးနေပါတယ်...${Z}"
sqlite3 "$DB" <<'EOF'
-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expires DATE,
    port INTEGER,
    status TEXT DEFAULT 'active',
    bandwidth_limit INTEGER DEFAULT 0, -- GB (convert to bytes in app logic)
    bandwidth_used INTEGER DEFAULT 0, -- Bytes
    speed_limit_up INTEGER DEFAULT 0, -- KB/s
    speed_limit_down INTEGER DEFAULT 0, -- KB/s
    concurrent_conn INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Billing Table
CREATE TABLE IF NOT EXISTS billing (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    plan_type TEXT DEFAULT 'monthly',
    amount REAL DEFAULT 0,
    currency TEXT DEFAULT 'MMK',
    payment_status TEXT DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATE NOT NULL
);

-- Bandwidth Logs
CREATE TABLE IF NOT EXISTS bandwidth_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    bytes_used INTEGER DEFAULT 0,
    log_date DATE DEFAULT CURRENT_DATE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Server Stats
CREATE TABLE IF NOT EXISTS server_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total_users INTEGER DEFAULT 0,
    active_users INTEGER DEFAULT 0,
    total_bandwidth INTEGER DEFAULT 0,
    server_load REAL DEFAULT 0,
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_user TEXT NOT NULL,
    action TEXT NOT NULL,
    target_user TEXT,
    details TEXT,
    ip_address TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Admin Settings for Global Config/Language
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_language', 'my');
INSERT OR IGNORE INTO settings (key, value) VALUES ('logo_url', 'https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png');

EOF

# ===== Base config & Certs (UNCHANGED) =====
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

# ===== Web Admin Setup (UNCHANGED LOGIN LOGIC) =====
say "${Y}🔒 Web Admin Login UI ${Z}"
read -r -p "Web Admin Username (Enter=admin): " WEB_USER
WEB_USER="${WEB_USER:-admin}"
read -r -s -p "Web Admin Password: " WEB_PASS; echo

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

# ===== VPN Password List (UNCHANGED) =====
say "${G}🔏 VPN Password List (eg: khaing,alice,pass1)${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then
  PW_LIST='["zi"]'
else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "${SERVER_IP:-}" ]; then
  SERVER_IP=$(curl -s icanhazip.com || echo "127.0.0.1")
fi

# ===== Update config.json (UNCHANGED) =====
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

# ===== Enhanced Web Panel (web.py) - MAJOR CHANGES HERE =====
say "${Y}🖥️ Enhanced Web Panel ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics
import csv
from io import StringIO

DATABASE_PATH = "/etc/zivpn/zivpn.db"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
CONTRACK_TIMEOUT_SECONDS = 120 # Conntrack timeout for UDP session status

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# --- Translations ---
T = {
    'my': {
        'panel_title': "မောင်သုည ZIVPN Enterprise Panel",
        'login_title': "မောင်သုည Enterprise Panel Login",
        'user': "👤 အသုံးပြုသူ", 'password': "🔑 လျှို့ဝှက်နံပါတ်", 'expires': "⏰ သက်တမ်းကုန်ဆုံး",
        'port': "🔌 Port", 'bandwidth': "📊 Bandwidth", 'speed': "⚡ Speed",
        'status': "🔎 အခြေအနေ", 'actions': "⚙️ လုပ်ဆောင်ချက်များ", 'delete_confirm': " ကို ဖျက်မလား?",
        'total_users': "စုစုပေါင်း Users", 'active_users': "လိုင်းရှိ Users", 'bandwidth_used': "သုံးစွဲထားသော Bandwidth",
        'server_load': "Server ဝန်", 'online': "လိုင်းပေါ်", 'offline': "လိုင်းပေါ်မရှိ", 'expired': "သက်တမ်းကုန်",
        'suspended': "ပိတ်ထားသည်", 'unknown': "မသိရှိ", 'save_user': "User သိမ်းမည်",
        'add_user_title': "အသုံးပြုသူ အသစ်ထည့်ပါ", 'speed_limit': "Speed Limit (KB/s)", 'max_conn': "အများဆုံး ချိတ်ဆက်မှု",
        'bulk_title': "Bulk လုပ်ငန်းများ", 'select_action': "လုပ်ဆောင်ချက် ရွေးပါ", 'execute': "လုပ်ဆောင်",
        'export_csv': "Users CSV ထုတ်ယူ", 'search_users': "Users ရှာဖွေပါ...", 'reports_title': "Reports & Analytics",
        'force_disconnect': "ချိတ်ဆက်မှု ဖြုတ်", 'user_pass_required': "User နှင့် Password လိုအပ်သည်",
        'expires_format_err': "Expires Format မမှန်ပါ", 'port_range_err': "Port အကွာအဝေး 6000-19999",
        'user_saved': "User ကို အောင်မြင်စွာ သိမ်းဆည်းပြီးပါပြီ", 'user_deleted': "ကို ဖျက်ပစ်လိုက်ပါပြီ",
        'not_found': "မတွေ့ပါ", 'invalid_data': "ဒေတာ မမှန်ကန်ပါ"
    },
    'en': {
        'panel_title': "Maung Thonnya ZIVPN Enterprise Panel",
        'login_title': "Maung Thonnya Enterprise Panel Login",
        'user': "👤 User", 'password': "🔑 Password", 'expires': "⏰ Expires",
        'port': "🔌 Port", 'bandwidth': "📊 Bandwidth", 'speed': "⚡ Speed",
        'status': "🔎 Status", 'actions': "⚙️ Actions", 'delete_confirm': " Delete this user?",
        'total_users': "Total Users", 'active_users': "Active Users", 'bandwidth_used': "Bandwidth Used",
        'server_load': "Server Load", 'online': "ONLINE", 'offline': "OFFLINE", 'expired': "EXPIRED",
        'suspended': "SUSPENDED", 'unknown': "UNKNOWN", 'save_user': "Save User",
        'add_user_title': "Add New User", 'speed_limit': "Speed Limit (KB/s)", 'max_conn': "Max Connections",
        'bulk_title': "Bulk Operations", 'select_action': "Select Action", 'execute': "Execute",
        'export_csv': "Export Users CSV", 'search_users': "Search users...", 'reports_title': "Reports & Analytics",
        'force_disconnect': "Disconnect", 'user_pass_required': "User and Password are required",
        'expires_format_err': "Expires format is invalid", 'port_range_err': "Port range 6000-19999",
        'user_saved': "User saved successfully", 'user_deleted': "Deleted:",
        'not_found': "Not Found", 'invalid_data': "Invalid Data"
    }
}

def translate(key):
    lang = session.get('language', 'my')
    return T.get(lang, T['my']).get(key, key) # Fallback to key itself

# --- Database / Data Access Layer ---
def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, bandwidth_used, speed_limit_up, concurrent_conn
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        # Convert GB limit to Bytes for storage consistency (1 GB = 1073741824 bytes)
        bw_limit_bytes = int(user_data.get('bandwidth_limit', 0)) * 1073741824
        
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), 'active', bw_limit_bytes,
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
        ))
        # Add/Update billing record (Simplified)
        if user_data.get('expires'):
            db.execute('''
                INSERT OR REPLACE INTO billing (username, expires_at) VALUES (?, ?)
                ON CONFLICT(username) DO UPDATE SET expires_at=excluded.expires_at
            ''', (user_data['user'], user_data['expires']))
            
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
        # Active users logic: not suspended AND not expired
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status = "active" AND (expires IS NULL OR expires > date("now"))').fetchone()[0]
        total_bandwidth_bytes = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        total_bandwidth_gb = total_bandwidth_bytes / 1073741824 # Convert Bytes to GB
        
        # Simple server load simulation
        server_load = min(100, (os.cpu_count() or 1) * 10 + (active_users * 5))
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth_gb:.2f} GB",
            'server_load': server_load
        }
    finally:
        db.close()

# --- Network & Status Check ---
def read_json(path, default):
    try:
        with open(path,"r") as f: return json.load(f)
    except Exception:
        return default

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
    # Only check main ZIVPN port and user-assigned ports (6000-19999)
    out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
    ports = set(re.findall(r":(\d+)\s", out))
    return {p for p in ports if (p == get_listen_port_from_config() or (6000 <= int(p) <= 19999) if p.isdigit() else False)}

def get_active_conntrack_sessions(listen_port):
    """Returns a set of active UDP ports from conntrack that route to listen_port."""
    try:
        # Search conntrack for UDP sessions destined for the ZIVPN listen port
        # and extract the source port (which is the user's assigned port via DNAT)
        command = "conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b' | grep -v 'UNREPLIED'" % listen_port
        out = subprocess.run(command, shell=True, capture_output=True, text=True).stdout
        
        active_ports = set()
        for line in out.splitlines():
            # Example conntrack line: udp 17 119 src=... dst=... sport=... dport=5667 [UNASSURED] src=... dst=... sport=... dport=6001 [ASSURED] mark=0 use=1
            # We are interested in the DNAT destination port, which is the user's port.
            # Look for the source port of the original traffic before DNAT.
            match = re.search(r'src=\S+\s+dst=\S+\s+sport=(\d+)\s+dport=%s' % listen_port, line)
            if match:
                active_ports.add(match.group(1))
        return active_ports
    except Exception as e:
        print(f"Error checking conntrack: {e}")
        return set()

def status_for_user(u, active_ports, conntrack_ports, listen_port):
    port = str(u.get("port", ""))
    today_date=datetime.now().date()
    expires_str=u.get("expires","")
    is_expired=False
    
    if expires_str:
        try:
            expires_dt=datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < today_date:
                is_expired=True
        except ValueError: pass

    if u.get('status') == 'suspended': return translate('suspended')
    if is_expired: return translate('expired')

    # Check for actual connection via conntrack (most reliable)
    # The active conntrack port is the user's mapped/assigned port (6000-19999)
    if port and port in conntrack_ports: 
        return translate('online')
    
    # Fallback to check if the port is even listening/opened (Less reliable for 'Online')
    if port and port in active_ports:
        return translate('offline') # Listening but no traffic seen recently

    return translate('unknown')

def sync_config_passwords():
    users=load_users()
    # Filter only active users for the main config (suspended/expired users are blocked via UI/logic)
    users_pw=sorted({str(u["password"]) for u in users if u.get("password") and u.get("status")=='active'})
    
    # Update ZIVPN config file
    cfg=read_json(CONFIG_FILE,{})
    if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
    cfg["auth"]["mode"]="passwords"
    cfg["auth"]["config"]=users_pw
    
    write_json_atomic(CONFIG_FILE,cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True)

def write_json_atomic(path, data):
    d=json.dumps(data, ensure_ascii=False, indent=2)
    dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
    try:
        with os.fdopen(fd,"w") as f: f.write(d)
        os.replace(tmp,path)
    finally:
        try: os.remove(tmp)
        except: pass

# --- UI Helper ---
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

# --- Main View Renderer ---
def build_view(msg="", err="", active_tab="users"):
    lang = session.get('language', 'my')
    if not require_login():
        return render_template_string(HTML_LOGIN, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T[lang])
    
    users=load_users()
    active_listen_ports = get_udp_listen_ports()
    listen_port = get_listen_port_from_config()
    conntrack_sessions = get_active_conntrack_sessions(listen_port)
    stats = get_server_stats()
    
    view=[]
    today_date=datetime.now().date()
    
    for u in users:
        u['status'] = status_for_user(u, active_listen_ports, conntrack_sessions, listen_port)
        u['bandwidth_used_gb'] = f"{u.get('bandwidth_used', 0) / 1073741824:.2f}"
        u['bandwidth_limit_gb'] = u.get('bandwidth_limit', 0) / 1073741824
        
        view.append(u)
    
    view.sort(key=lambda x:(x.get('user') or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    return render_template_string(HTML_MAIN, authed=True, logo=LOGO_URL, 
                                 users=view, msg=msg, err=err, today=today, 
                                 stats=stats, T=T[lang], lang=lang, 
                                 active_tab=active_tab, 
                                 is_dark_mode=session.get('dark_mode', True))

# --- Login HTML ---
HTML_LOGIN = """<!doctype html>
<html lang="{{ T['panel_title'] }}">
<head>
<meta charset="utf-8"><title>{{ T['panel_title'] }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>:root{--bg:#f0f2f5;--fg:#1c1e21;--card:#fff;--bd:#ddd;--header-bg:#fff;--ok:#27ae60;--bad:#e74c3c;--input-text:#1c1e21;--primary-btn:#3498db;--shadow:0 1px 12px rgba(0,0,0,0.1);--radius:8px;}
.dark-mode{--bg:#1e1e1e;--fg:#f0f0f0;--card:#2d2d2d;--bd:#444;--header-bg:#2d2d2d;--ok:#2ecc71;--bad:#c0392b;--input-text:#fff;--primary-btn:#3498db;--shadow:0 4px 15px rgba(0,0,0,0.5);}.login-card{max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;background:var(--card);box-shadow:var(--shadow);}
html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px}.center{display:flex;align-items:center;justify-content:center}.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}.login-card h3{margin:5px 0 25px;font-size:1.8em;text-shadow:0 1px 3px rgba(0,0,0,0.2);}.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--bad);color:white;font-weight:700;}
label{display:block;margin:6px 0 4px;font-size:.95em;font-weight:700;}input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);box-sizing:border-box;background:var(--bg);color:var(--input-text);}input:focus{outline:none;border-color:var(--primary-btn);}.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.3);display:flex;align-items:center;gap:8px;}.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:#2980b9}
.toggle-lang{position:absolute;top:20px;right:20px;display:flex;gap:5px;}.toggle-lang a{font-size:.9em;text-decoration:none;padding:5px 10px;border-radius:5px;background:var(--card);color:var(--fg);border:1px solid var(--bd);}
.toggle-lang .active{background:var(--primary-btn);color:white;}
</style>
<script>document.documentElement.className = localStorage.getItem('theme') || 'dark-mode';</script>
</head>
<body class="{{ 'dark-mode' if is_dark_mode else '' }}">
<div class="toggle-lang">
    <a href="/set_lang?lang=my" class="{{ 'active' if T['user'] == '👤 အသုံးပြုသူ' }}">မြန်မာ</a>
    <a href="/set_lang?lang=en" class="{{ 'active' if T['user'] == '👤 User' }}">English</a>
</div>
<div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
    <h3 class="center">{{ T['login_title'] }}</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
        <label><i class="fas fa-user"></i> {{ T['user'] }}</label>
        <input name="u" autofocus required>
        <label style="margin-top:15px"><i class="fas fa-lock"></i> {{ T['password'] }}</label>
        <input name="p" type="password" required>
        <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
            <i class="fas fa-sign-in-alt"></i> Login
        </button>
    </form>
</div>
</body></html>"""

# --- Main Panel HTML ---
HTML_MAIN = """<!doctype html>
<html lang="{{ lang }}">
<head><meta charset="utf-8">
<title>{{ T['panel_title'] }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{
  --bg: #f0f2f5; --fg: #1c1e21; --card: #fff; --bd: #ddd; --header-bg: #fff;
  --ok: #27ae60; --bad: #e74c3c; --unknown: #f39c12; --expired: #8e44ad;
  --info: #3498db; --success: #1abc9c; --delete-btn: #e74c3c; --primary-btn: #3498db;
  --logout-btn: #e67e22; --telegram-btn: #0088cc; --input-text: #1c1e21;
  --shadow: 0 1px 12px rgba(0,0,0,0.1); --radius: 8px;
}
.dark-mode{
  --bg: #1e1e1e; --fg: #f0f0f0; --card: #2d2d2d; --bd: #444;
  --header-bg: #2d2d2d; --ok: #2ecc71; --bad: #c0392b; --unknown: #f1c40f;
  --expired: #8e44ad; --info: #3498db; --success: #1abc9c; --delete-btn: #e74c3c;
  --primary-btn: #3498db; --logout-btn: #d35400; --telegram-btn: #0088cc;
  --input-text: #fff; --shadow: 0 4px 15px rgba(0,0,0,0.5);
}

/* Global Styles */
html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:10px}
.container{max-width:1400px;margin:auto;padding:10px}
@keyframes colorful-shift { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }

/* Header */
header{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:15px;margin-bottom:25px;background:var(--header-bg);border-radius:var(--radius);box-shadow:var(--shadow);}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}
.colorful-title{font-size:1.8em;font-weight:900;background:linear-gradient(90deg,#FF0000,#FF8000,#FFFF00,#00FF00,#00FFFF,#0000FF,#8A2BE2,#FF0000);background-size:300% auto;-webkit-background-clip:text;-webkit-text-fill-color:transparent;animation:colorful-shift 8s linear infinite;text-shadow:0 0 5px rgba(255,255,255,0.4);}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--info)}

/* Buttons & Forms */
.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 2px 4px rgba(0,0,0,0.3);display:inline-flex;align-items:center;gap:8px;}
.btn.primary{background:var(--primary-btn)}.btn.primary:hover{background:#2980b9}
.btn.save{background:var(--success)}.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}.btn.contact:hover{background:#006799}
.btn.secondary{background:#95a5a6}.btn.secondary:hover{background:#7f8c8d}
form.box{margin:25px 0;padding:25px;border-radius:var(--radius);background:var(--card);box-shadow:var(--shadow);}
label{display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;}
input,select{width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);box-sizing:border-box;background:var(--bg);color:var(--input-text);}
input:focus,select:focus{outline:none;border-color:var(--primary-btn);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}

/* Tabs */
.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);overflow-x:auto;}
.tab-btn{padding:12px 20px;background:var(--card);border:none;color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;font-weight:700;border:1px solid var(--bd);border-bottom:none;}
.tab-btn.active{background:var(--primary-btn);color:white;border-color:var(--primary-btn);}
.tab-content{display:none;padding-top:10px}
.tab-content.active{display:block;}

/* Stats */
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
.stat-card{padding:20px;background:var(--card);border-radius:var(--radius);text-align:center;box-shadow:var(--shadow);}
.stat-number{font-size:2em;font-weight:700;margin:10px 0;color:var(--primary-btn);}
.stat-label{font-size:.9em;color:var(--fg);opacity:0.7;}

/* Table */
table{border-collapse:separate;width:100%;background:var(--card);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);vertical-align:middle;}
th:last-child,td:last-child{border-right:none;}
th{background:var(--bg);font-weight:700;color:var(--fg);text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover{background:rgba(0,0,0,0.1)}
.dark-mode tr:hover{background:rgba(255,255,255,0.1)}

/* Pills */
.pill{display:inline-block;padding:5px 12px;border-radius:20px;font-size:.85em;font-weight:700;text-shadow:1px 1px 2px rgba(0,0,0,0.5);box-shadow:0 1px 3px rgba(0,0,0,0.2);}
.status-online{color:white;background:var(--ok)}.status-offline{color:white;background:var(--info)}
.status-expired{color:white;background:var(--expired)}.status-suspended{color:white;background:var(--bad)}
.status-unknown{color:white;background:var(--unknown)}
.pill-yellow{background:#f1c40f}.pill-red{background:#e74c3c}.pill-green{background:#2ecc71}
.pill-lightgreen{background:#1abc9c}.pill-pink{background:#f78da7}.pill-orange{background:#e67e22}
.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:rgba(142, 68, 173, 0.1);color:var(--fg);}

/* Custom Header Controls */
.header-controls{display:flex;align-items:center;gap:15px;}
.toggle-mode,.toggle-lang{display:flex;gap:5px;align-items:center;}
.toggle-mode button{background:var(--card);color:var(--fg);border:1px solid var(--bd);padding:8px 12px;border-radius:var(--radius);cursor:pointer;}
.toggle-mode button:hover{background:var(--bg);}
.toggle-lang a{font-size:.9em;text-decoration:none;padding:5px 10px;border-radius:5px;background:var(--card);color:var(--fg);border:1px solid var(--bd);}
.toggle-lang .active{background:var(--primary-btn);color:white;border-color:var(--primary-btn);}

/* Responsive */
@media (max-width: 768px) {
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .header-controls{width:100%;justify-content:space-between;}
  .row>div,.stats-grid{grid-template-columns:1fr;}
  .btn{width:auto;margin-bottom:5px;justify-content:center}
  table,thead,tbody,th,td,tr{display:block;}
  thead tr{position:absolute;top:-9999px;left:-9999px;}
  tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
  td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
  td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--info);}
  td:nth-of-type(1):before{content:"{{ T['user'] | safe }}";}td:nth-of-type(2):before{content:"{{ T['password'] | safe }}";}
  td:nth-of-type(3):before{content:"{{ T['expires'] | safe }}";}td:nth-of-type(4):before{content:"{{ T['port'] | safe }}";}
  td:nth-of-type(5):before{content:"{{ T['bandwidth'] | safe }}";}td:nth-of-type(6):before{content:"{{ T['speed'] | safe }}";}
  td:nth-of-type(7):before{content:"{{ T['status'] | safe }}";}td:nth-of-type(8):before{content:"{{ T['actions'] | safe }}";}
  .delform{width:auto;}
}
</style>
<script>
// Apply saved theme on load
document.documentElement.className = localStorage.getItem('theme') || 'dark-mode';
</script>
</head>
<body>
<div class="container">

<header>
  <div class="header-left">
    <img src="{{ logo }}" alt="မောင်သုည" class="logo">
    <div>
      <h1><span class="colorful-title">မောင်သုည ZIVPN Enterprise</span></h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ Enterprise Management System ⊱✫⊰</span></div>
    </div>
  </div>
  <div class="header-controls">
    <div class="toggle-mode">
        <button onclick="toggleTheme()" title="Dark/Light Mode">
            <i class="fas fa-moon" id="theme-icon"></i>
        </button>
    </div>
    <div class="toggle-lang">
        <a href="/set_lang?lang=my" class="{{ 'active' if lang == 'my' }}">မြန်မာ</a>
        <a href="/set_lang?lang=en" class="{{ 'active' if lang == 'en' }}">EN</a>
    </div>
    <a class="btn contact" href="https://t.me/Zero_Free_Vpn" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>Contact
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>Logout
    </a>
  </div>
</header>

<div class="stats-grid">
  <div class="stat-card">
    <i class="fas fa-users" style="font-size:2em;color:#3498db;"></i>
    <div class="stat-number">{{ stats.total_users }}</div>
    <div class="stat-label">{{ T['total_users'] }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-signal" style="font-size:2em;color:var(--ok);"></i>
    <div class="stat-number">{{ stats.active_users }}</div>
    <div class="stat-label">{{ T['active_users'] }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-database" style="font-size:2em;color:#e74c3c;"></i>
    <div class="stat-number">{{ stats.total_bandwidth }}</div>
    <div class="stat-label">{{ T['bandwidth_used'] }}</div>
  </div>
  <div class="stat-card">
    <i class="fas fa-server" style="font-size:2em;color:#f39c12;"></i>
    <div class="stat-number">{{ stats.server_load }}%</div>
    <div class="stat-label">{{ T['server_load'] }}</div>
  </div>
</div>

<div class="tab-container">
  <div class="tabs">
    <button class="tab-btn {% if active_tab == 'users' %}active{% endif %}" onclick="openTab('users')">User Management</button>
    <button class="tab-btn {% if active_tab == 'adduser' %}active{% endif %}" onclick="openTab('adduser')">{{ T['add_user_title'] }}</button>
    <button class="tab-btn {% if active_tab == 'bulk' %}active{% endif %}" onclick="openTab('bulk')">{{ T['bulk_title'] }}</button>
    <button class="tab-btn {% if active_tab == 'reports' %}active{% endif %}" onclick="openTab('reports')">{{ T['reports_title'] }}</button>
  </div>

  <div id="adduser" class="tab-content {% if active_tab == 'adduser' %}active{% endif %}">
    <form method="post" action="/add" class="box">
      <h3><i class="fas fa-users-cog"></i> {{ T['add_user_title'] }}</h3>
      {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <div class="row">
        <div><label><i class="fas fa-user"></i> {{ T['user'] }}</label><input name="user" placeholder="User Name" required></div>
        <div><label><i class="fas fa-lock"></i> {{ T['password'] }}</label><input name="password" placeholder="Password" required></div>
        <div><label><i class="fas fa-clock"></i> {{ T['expires'] }}</label><input name="expires" placeholder="YYYY-MM-DD or 30 days"></div>
        <div><label><i class="fas fa-server"></i> {{ T['port'] }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
      </div>
      <div class="row">
        <div><label><i class="fas fa-tachometer-alt"></i> {{ T['speed_limit'] }}</label><input name="speed_limit_up" placeholder="0 = unlimited (KB/s)" type="number"></div>
        <div><label><i class="fas fa-database"></i> {{ T['bandwidth'] }} Limit (GB)</label><input name="bandwidth_limit_gb" placeholder="0 = unlimited (GB)" type="number"></div>
        <div><label><i class="fas fa-plug"></i> {{ T['max_conn'] }}</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
        <div><label><i class="fas fa-money-bill"></i> Plan Type</label>
          <select name="plan_type">
            <option value="monthly" selected>Monthly</option>
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="free">Free</option>
          </select>
        </div>
      </div>
      <button class="btn save" type="submit" style="margin-top:20px">
        <i class="fas fa-save"></i> {{ T['save_user'] }}
      </button>
    </form>
  </div>

  <div id="bulk" class="tab-content {% if active_tab == 'bulk' %}active{% endif %}">
    <div class="box">
      <h3><i class="fas fa-cogs"></i> {{ T['bulk_title'] }}</h3>
      <div class="row" style="align-items:flex-end;">
        <div style="flex:1;"><label>{{ T['select_action'] }}</label>
          <select id="bulkAction">
            <option value="">{{ T['select_action'] }}</option>
            <option value="extend">+7 Days Extend</option>
            <option value="suspend">Suspend Users</option>
            <option value="activate">Activate Users</option>
            <option value="delete">Delete Users</option>
            <option value="reset_bw">Reset Bandwidth Used</option>
          </select>
        </div>
        <div style="flex:2;"><label>Usernames (comma separated)</label>
          <input type="text" id="bulkUsers" placeholder="user1,user2">
        </div>
        <div style="flex:0 0 auto;">
          <button class="btn secondary" onclick="executeBulkAction()">
            <i class="fas fa-play"></i> {{ T['execute'] }}
          </button>
        </div>
      </div>
      <div style="margin-top:15px">
        <button class="btn primary" onclick="exportUsers()">
          <i class="fas fa-download"></i> {{ T['export_csv'] }}
        </button>
      </div>
    </div>
  </div>

  <div id="users" class="tab-content {% if active_tab == 'users' %}active{% endif %}">
    <div class="box">
      <h3><i class="fas fa-users"></i> User Management</h3>
      <div style="margin:15px 0;display:flex;gap:10px;">
        <input type="text" id="searchUser" placeholder="{{ T['search_users'] }}" style="flex:1;">
        <button class="btn secondary" onclick="filterUsers()">
          <i class="fas fa-search"></i> Search
        </button>
      </div>
    </div>

    <table>
      <thead>
        <tr>
          <th><i class="fas fa-user"></i> {{ T['user'] }}</th>
          <th><i class="fas fa-lock"></i> {{ T['password'] }}</th>
          <th><i class="fas fa-clock"></i> {{ T['expires'] }}</th>
          <th><i class="fas fa-server"></i> {{ T['port'] }}</th>
          <th><i class="fas fa-database"></i> {{ T['bandwidth'] }}</th>
          <th><i class="fas fa-tachometer-alt"></i> {{ T['speed'] }} (KB/s)</th>
          <th><i class="fas fa-chart-line"></i> {{ T['status'] }}</th>
          <th><i class="fas fa-cog"></i> {{ T['actions'] }}</th>
        </tr>
      </thead>
      <tbody>
      {% for u in users %}
      <tr class="{% if u.status == T['expired'] %}expired{% endif %}">
        <td><strong>{{u.user}}</strong></td>
        <td>{{u.password}}</td>
        <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
        <td><span class="pill-lightgreen">{{u.bandwidth_used_gb}} / {% if u.bandwidth_limit_gb > 0 %}{{u.bandwidth_limit_gb}} GB{% else %}Unlimited{% endif %}</span></td>
        <td><span class="pill-yellow">{{u.speed_limit_up}}</span></td>
        <td>
          {% if u.status == T['online'] %}<span class="pill status-online">{{ T['online'] }}</span>
          {% elif u.status == T['offline'] %}<span class="pill status-offline">{{ T['offline'] }}</span>
          {% elif u.status == T['expired'] %}<span class="pill status-expired">{{ T['expired'] }}</span>
          {% elif u.status == T['suspended'] %}<span class="pill status-suspended">{{ T['suspended'] }}</span>
          {% else %}<span class="pill status-unknown">{{ T['unknown'] }}</span>
          {% endif %}
        </td>
        <td style="display:flex;gap:5px;">
          <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} {{ T['delete_confirm'] }}')">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="Delete" style="padding:6px 12px;">
              <i class="fas fa-trash-alt"></i>
            </button>
          </form>
          <button class="btn primary" title="Edit" style="padding:6px 12px;" onclick="editUser('{{u.user}}', '{{u.password}}', '{{u.expires or ''}}', '{{u.port or ''}}', '{{u.bandwidth_limit_gb}}', '{{u.speed_limit_up or ''}}', '{{u.concurrent_conn or '1'}}')">
            <i class="fas fa-edit"></i>
          </button>
          {% if u.status == T['online'] %}
          <form class="delform" method="post" action="/force_disconnect">
            <input type="hidden" name="user_port" value="{{u.port}}">
            <button type="submit" class="btn delete" title="{{ T['force_disconnect'] }}" style="padding:6px 12px;">
              <i class="fas fa-unlink"></i>
            </button>
          </form>
          {% elif u.status == T['suspended'] or u.status == T['expired'] %}
          <form class="delform" method="post" action="/activate">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn save" title="Activate" style="padding:6px 12px;">
              <i class="fas fa-play"></i>
            </button>
          </form>
          {% else %}
          <form class="delform" method="post" action="/suspend">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn delete" title="Suspend" style="padding:6px 12px;">
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

  <div id="reports" class="tab-content {% if active_tab == 'reports' %}active{% endif %}">
    <div class="box">
      <h3><i class="fas fa-chart-bar"></i> {{ T['reports_title'] }}</h3>
      <div class="row">
        <div><label>From Date</label><input type="date" id="fromDate"></div>
        <div><label>To Date</label><input type="date" id="toDate"></div>
        <div><label>Report Type</label>
          <select id="reportType">
            <option value="bandwidth">Bandwidth Usage</option>
            <option value="users">New User Activity</option>
          </select>
        </div>
        <div><button class="btn primary" onclick="generateReport()" style="margin-top:25px;">Generate Report</button></div>
      </div>
    </div>
    <div id="reportResults" class="box" style="display:none; overflow-x:auto;"><pre></pre></div>
  </div>
</div>

<div id="editModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.7); z-index:100;">
    <form id="editForm" class="box" style="max-width:500px; margin:50px auto;">
        <h3>Edit User: <span id="editUserTitle"></span></h3>
        <input type="hidden" id="editUsername" name="user">
        <label><i class="fas fa-lock"></i> New Password</label><input id="editPassword" name="password" required>
        <label><i class="fas fa-clock"></i> Expires (YYYY-MM-DD)</label><input id="editExpires" name="expires">
        <label><i class="fas fa-database"></i> Bandwidth Limit (GB)</label><input id="editBwLimit" name="bandwidth_limit_gb" type="number">
        <label><i class="fas fa-tachometer-alt"></i> Speed Limit (KB/s)</label><input id="editSpeedLimit" name="speed_limit_up" type="number">
        <label><i class="fas fa-plug"></i> Max Connections</label><input id="editConn" name="concurrent_conn" type="number">
        <div style="display:flex; gap:10px; margin-top:20px;">
            <button type="button" class="btn save" style="flex:1;" onclick="saveEditUser()">Save Changes</button>
            <button type="button" class="btn secondary" style="flex:1;" onclick="closeModal()">Cancel</button>
        </div>
    </form>
</div>

{% endif %}
</div>

<script>
function openTab(tabName) {
  document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
  document.getElementById(tabName).classList.add('active');
  document.querySelector(`.tabs button[onclick="openTab('${tabName}')"]`).classList.add('active');
  // Update URL hash for persistence
  history.pushState(null, null, '#' + tabName);
}

// Function to handle Dark/Light Mode toggle
function toggleTheme() {
    const html = document.documentElement;
    const isDarkMode = html.classList.contains('dark-mode');
    
    if (isDarkMode) {
        html.classList.remove('dark-mode');
        localStorage.setItem('theme', 'light-mode');
    } else {
        html.classList.add('dark-mode');
        localStorage.setItem('theme', 'dark-mode');
    }
}

function executeBulkAction() {
  const action = document.getElementById('bulkAction').value;
  const users = document.getElementById('bulkUsers').value;
  if (!action || !users) { alert('{{ T["select_action"] }} and enter users'); return; }
  if (action === 'delete' && !confirm('Are you sure you want to delete these users?')) { return; }
  
  fetch('/api/bulk', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
  }).then(r => r.json()).then(data => {
    alert(data.message); location.reload();
  }).catch(err => {
    alert('Error executing bulk action: ' + err);
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

function editUser(username, password, expires, port, bw_limit_gb, speed_limit_up, concurrent_conn) {
    document.getElementById('editUsername').value = username;
    document.getElementById('editUserTitle').textContent = username;
    document.getElementById('editPassword').value = password;
    document.getElementById('editExpires').value = expires;
    document.getElementById('editBwLimit').value = bw_limit_gb;
    document.getElementById('editSpeedLimit').value = speed_limit_up;
    document.getElementById('editConn').value = concurrent_conn;
    document.getElementById('editModal').style.display = 'block';
}

function closeModal() {
    document.getElementById('editModal').style.display = 'none';
}

function saveEditUser() {
  const user = document.getElementById('editUsername').value;
  const password = document.getElementById('editPassword').value;
  const expires = document.getElementById('editExpires').value;
  const bw_limit_gb = document.getElementById('editBwLimit').value;
  const speed_limit_up = document.getElementById('editSpeedLimit').value;
  const concurrent_conn = document.getElementById('editConn').value;

  fetch('/api/user/update', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({user, password, expires, bandwidth_limit_gb: bw_limit_gb, speed_limit_up, concurrent_conn})
  }).then(r => r.json()).then(data => {
    alert(data.message); closeModal(); location.reload();
  }).catch(err => {
    alert('Error saving user: ' + err);
  });
}

function generateReport() {
  const from = document.getElementById('fromDate').value;
  const to = document.getElementById('toDate').value;
  const type = document.getElementById('reportType').value;
  
  const resultsDiv = document.getElementById('reportResults');
  resultsDiv.querySelector('pre').textContent = 'Generating...';
  resultsDiv.style.display = 'block';
  
  fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
    .then(r => r.json()).then(data => {
      resultsDiv.querySelector('pre').textContent = JSON.stringify(data, null, 2);
    }).catch(err => {
        resultsDiv.querySelector('pre').textContent = 'Error: ' + err;
    });
}

// Check URL hash on load to set active tab
document.addEventListener('DOMContentLoaded', () => {
    const hash = window.location.hash.substring(1);
    if (hash && document.getElementById(hash)) {
        openTab(hash);
    } else {
        openTab('users');
    }
});
</script>
</body></html>"""


# --- Flask Routes ---

@app.route("/set_mode", methods=["GET"])
def set_mode():
    mode = request.args.get('mode')
    if mode == 'dark':
        session['dark_mode'] = True
    elif mode == 'light':
        session['dark_mode'] = False
    return redirect(request.referrer or url_for('index'))

@app.route("/set_lang", methods=["GET"])
def set_lang():
    lang = request.args.get('lang')
    if lang in T:
        session['language'] = lang
    return redirect(request.referrer or url_for('index'))

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
            session["login_err"]=translate('not_found')
            return redirect(url_for('login'))
    return render_template_string(HTML_LOGIN, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), T=T[session.get('language', 'my')], is_dark_mode=session.get('dark_mode', True))

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): 
    active_tab = request.args.get('tab', 'users')
    return build_view(active_tab=active_tab)

@app.route("/add", methods=["POST"])
def add_user():
    if not require_login(): return redirect(url_for('login'))
    
    user_data = {
        'user': (request.form.get("user") or "").strip(),
        'password': (request.form.get("password") or "").strip(),
        'expires': (request.form.get("expires") or "").strip(),
        'port': (request.form.get("port") or "").strip(),
        'bandwidth_limit': int(request.form.get("bandwidth_limit_gb") or 0), # GB from form
        'speed_limit': int(request.form.get("speed_limit_up") or 0), # KB/s from form
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1),
        'plan_type': (request.form.get("plan_type") or "").strip()
    }
    
    if not user_data['user'] or not user_data['password']:
        return build_view(err=translate('user_pass_required'), active_tab="adduser")
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=translate('expires_format_err'), active_tab="adduser")
    
    if user_data['port'] and not (6000 <= int(user_data['port']) <= 19999):
        return build_view(err=translate('port_range_err'), active_tab="adduser")
    
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
    return build_view(msg=translate('user_saved'), active_tab="users")

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=translate('user_pass_required'))
    
    delete_user(user)
    sync_config_passwords()
    return build_view(msg=f"{translate('user_deleted')} {user}")

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

@app.route("/force_disconnect", methods=["POST"])
def force_disconnect():
    if not require_login(): return redirect(url_for('login'))
    user_port = (request.form.get("user_port") or "").strip()
    if user_port:
        # Use conntrack -D to delete the session, forcing a reconnect/disconnect
        # The traffic flows from [client_ip]:[client_port] to [server_ip]:[user_port] (before DNAT)
        # And from [server_ip]:[listen_port] to [client_ip]:[client_port] (after DNAT/SNAT)
        # Deleting all entries with the user's assigned port should work.
        subprocess.run("conntrack -D -p udp --dport %s 2>/dev/null" % user_port, shell=True)
        subprocess.run("conntrack -D -p udp --sport %s 2>/dev/null" % user_port, shell=True)
        return build_view(msg=f"Port {user_port} forcefully disconnected.")
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
        if action == 'extend':
            for user in users:
                db.execute('UPDATE users SET expires = date(expires, "+7 days") WHERE username = ?', (user,))
        elif action == 'suspend':
            for user in users:
                db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
        elif action == 'activate':
            for user in users:
                db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
        elif action == 'delete':
            for user in users:
                db.execute('DELETE FROM users WHERE username = ?', (user,))
        elif action == 'reset_bw':
            for user in users:
                db.execute('UPDATE users SET bandwidth_used = 0 WHERE username = ?', (user,))
        else:
            return jsonify({"ok": False, "message": "Unknown action"}), 400
            
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": f"Bulk action {action} completed for {len(users)} users"})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    si = StringIO()
    cw = csv.writer(si)
    
    # CSV Header
    cw.writerow(['User', 'Password', 'Expires', 'Port', 'BW Used (Bytes)', 'BW Limit (Bytes)', 'Speed Limit (KB/s)', 'Status', 'Max Conn'])
    
    for u in users:
        cw.writerow([
            u['user'], u['password'], u.get('expires',''), u.get('port',''), 
            u.get('bandwidth_used',0), u.get('bandwidth_limit',0), u.get('speed_limit_up',0), 
            u.get('status',''), u.get('concurrent_conn',1)
        ])
    
    output = make_response(si.getvalue())
    output.headers["Content-Disposition"] = "attachment; filename=users_export.csv"
    output.headers["Content-type"] = "text/csv"
    return output

@app.route("/api/user/update", methods=["POST"])
def update_user():
    if not require_login(): return jsonify({"ok": False, "err": "login required"}), 401
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    expires = data.get('expires')
    bw_limit_gb = data.get('bandwidth_limit_gb')
    speed_limit_up = data.get('speed_limit_up')
    concurrent_conn = data.get('concurrent_conn')
    
    if user and password:
        db = get_db()
        try:
            # Convert GB to Bytes
            bw_limit_bytes = int(bw_limit_gb) * 1073741824 if bw_limit_gb is not None else None
            
            update_fields = []
            params = []
            
            if password: update_fields.append("password = ?"); params.append(password)
            if expires is not None: update_fields.append("expires = ?"); params.append(expires if expires else None)
            if bw_limit_bytes is not None: update_fields.append("bandwidth_limit = ?"); params.append(bw_limit_bytes)
            if speed_limit_up is not None: update_fields.append("speed_limit_up = ?"); params.append(speed_limit_up)
            if concurrent_conn is not None: update_fields.append("concurrent_conn = ?"); params.append(concurrent_conn)
            
            params.append(user)
            
            db.execute(f'UPDATE users SET {", ".join(update_fields)} WHERE username = ?', tuple(params))
            db.commit()
            sync_config_passwords()
            return jsonify({"ok": True, "message": "User updated"})
        finally:
            db.close()
    
    return jsonify({"ok": False, "err": translate('invalid_data')})

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
                SELECT username, SUM(bytes_used) as total_bytes_used, 
                SUM(bytes_used) / 1073741824.0 as total_gb_used
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
                ORDER BY total_bytes_used DESC
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            return jsonify([dict(d) for d in data])
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND ?
                GROUP BY date
                ORDER BY date
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
            return jsonify([dict(d) for d in data])
    finally:
        db.close()
        
    return jsonify({"message": "Report generated"})

if __name__ == "__main__":
    # Ensure initial theme is set if not present
    with app.app_context():
        if 'dark_mode' not in session:
            session['dark_mode'] = True # Default to Dark Mode
        if 'language' not in session:
            session['language'] = 'my' # Default to Myanmar
    app.run(host="0.0.0.0", port=8080)
PY

# ===== API Service (api.py) - MODIFIED FOR KB/s and GB/Bytes Consistency =====
say "${Y}🔌 API Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/api.py <<'PY'
from flask import Flask, jsonify, request
import sqlite3, datetime
from datetime import timedelta
import os

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
    
    stats_dict = dict(stats)
    # Convert total_bandwidth to GB
    stats_dict['total_bandwidth_gb'] = stats_dict['total_bandwidth_bytes'] / 1073741824.0
    return jsonify(stats_dict)

@app.route('/api/v1/user/<username>', methods=['GET'])
def get_user(username):
    db = get_db()
    user = db.execute('SELECT * FROM users WHERE username = ?', (username,)).fetchone()
    db.close()
    if user:
        user_dict = dict(user)
        # Convert Bandwidth Limit to GB for external use
        user_dict['bandwidth_limit_gb'] = user_dict['bandwidth_limit'] / 1073741824.0
        return jsonify(user_dict)
    return jsonify({"error": "User not found"}), 404

@app.route('/api/v1/bandwidth/<username>', methods=['POST'])
def update_bandwidth(username):
    # This route assumes ZIVPN Server will post raw usage in bytes.
    data = request.get_json()
    bytes_used = int(data.get('bytes_used', 0))
    
    db = get_db()
    try:
        # 1. Update total used bandwidth in users table
        db.execute('''
            UPDATE users 
            SET bandwidth_used = bandwidth_used + ?, updated_at = CURRENT_TIMESTAMP 
            WHERE username = ?
        ''', (bytes_used, username))
        
        # 2. Log bandwidth usage
        db.execute('''
            INSERT INTO bandwidth_logs (username, bytes_used) 
            VALUES (?, ?)
        ''', (username, bytes_used))
        
        db.commit()
    except Exception as e:
        db.close()
        return jsonify({"message": f"Error updating bandwidth: {e}"}), 500
    finally:
        db.close()
    return jsonify({"message": "Bandwidth updated"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8081)
PY

# ===== Telegram Bot (bot.py) - UNCHANGED LOGIC, BUT USING GB CONVERSION =====
say "${Y}🤖 Telegram Bot Service ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/bot.py <<'PY'
import telegram
from telegram.ext import Updater, CommandHandler
import sqlite3, logging, os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DATABASE_PATH = "/etc/zivpn/zivpn.db"
BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN_HERE')
BYTES_TO_GB = 1073741824.0

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
            SUM(bandwidth_used) as total_bandwidth_bytes
        FROM users
    ''').fetchone()
    db.close()
    
    total_gb = stats['total_bandwidth_bytes'] / BYTES_TO_GB
    
    message = (
        f"📊 Server Statistics:\n"
        f"• Total Users: {stats['total_users']}\n"
        f"• Active Users: {stats['active_users']}\n"
        f"• Bandwidth Used: {total_gb:.2f} GB"
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
    
    bw_used_gb = user['bandwidth_used'] / BYTES_TO_GB
    bw_limit_gb = user['bandwidth_limit'] / BYTES_TO_GB
    
    message = (
        f"👤 User: {user['username']}\n"
        f"📊 Status: {user['status']}\n"
        f"⏰ Expires: {user['expires'] or 'Never'}\n"
        f"📦 Bandwidth: {bw_used_gb:.2f} GB / {bw_limit_gb:.0f} GB\n"
        f"⚡ Speed Limit: {user['speed_limit_up']} KB/s\n"
        f"🔗 Max Connections: {user['concurrent_conn']}"
    )
    update.message.reply_text(message)

def main():
    if BOT_TOKEN == 'YOUR_BOT_TOKEN_HERE':
        logger.error("Please set TELEGRAM_BOT_TOKEN environment variable (or change 'YOUR_BOT_TOKEN_HERE')")
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


# ===== Backup Script (backup.py) - UNCHANGED =====
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
                date_str = file.split('_')[2] 
                file_time = datetime.datetime.strptime(date_str, "%Y%m%d")
                if (datetime.datetime.now() - file_time).days > 7:
                    os.remove(file_path)
            except:
                pass # Ignore files with wrong naming convention
    
    print(f"Backup created: {backup_file}")

if __name__ == '__main__':
    backup_database()
PY

# ===== Auto Cleanup Script (cleanup.py) - NEW =====
say "${Y}🧹 Auto Cleanup Script ထည့်သွင်းနေပါတယ်...${Z}"
cat >/etc/zivpn/cleanup.py <<'PY'
import sqlite3, datetime
from datetime import datetime, timedelta

DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def auto_cleanup():
    db = get_db()
    today = datetime.now().strftime("%Y-%m-%d")
    
    print(f"Running auto cleanup for expired/over-limit users as of {today}...")

    # 1. Suspend expired users
    db.execute('''
        UPDATE users
        SET status = 'suspended'
        WHERE expires IS NOT NULL AND expires <= ? AND status = 'active'
    ''', (today,))
    
    # 2. Suspend over-limit users (Bandwidth Limit enforced)
    # The limit is stored in Bytes (1 GB = 1073741824 bytes)
    db.execute('''
        UPDATE users
        SET status = 'suspended'
        WHERE bandwidth_limit > 0 AND bandwidth_used >= bandwidth_limit AND status = 'active'
    ''')
    
    # 3. Cleanup old/unnecessary data (Example: old billing logs)
    # ... Add more cleanup logic here ...
    
    db.commit()
    db.close()
    print("Auto cleanup completed.")
    
if __name__ == '__main__':
    auto_cleanup()
    # After cleanup, restart VPN service to apply new suspended/active lists
    import subprocess
    subprocess.run("systemctl restart zivpn.service", shell=True)
PY

# ===== systemd Services (UPDATED) =====
say "${Y}🧰 systemd services များ ထည့်သွင်းနေပါတယ်...${Z}"

# ZIVPN Service (UNCHANGED)
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

# Web Panel Service (UNCHANGED)
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

# API Service (UNCHANGED)
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

# Backup Timer (UNCHANGED)
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

# Auto Cleanup Timer (NEW)
cat >/etc/systemd/system/zivpn-cleanup.service <<'EOF'
[Unit]
Description=ZIVPN Auto Cleanup and Suspend Service
After=zivpn-api.service zivpn-web.service

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

# ===== Networking Setup (UNCHANGED) =====
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

# ===== Final Setup =====
say "${Y}🔧 Final Configuration ပြုလုပ်နေပါတယ်...${Z}"
# Clean Windows line endings
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-api.service
systemctl enable --now zivpn-backup.timer
systemctl enable --now zivpn-cleanup.timer

# Initial cleanup and backup
python3 /etc/zivpn/cleanup.py
python3 /etc/zivpn/backup.py

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition V2.0 Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}🔌 API Server:${Z} ${Y}http://$IP:8081${Z}"
echo -e "\n${G}🎯 Enhanced Features Enabled:${Z}"
echo -e "  ✓ Enhanced UI/UX (Dark/Light Mode)"
echo -e "  ✓ Multi-Language (မြန်မာ/EN)"
echo -e "  ✓ Real-time User Status (Online/Offline) via Conntrack"
echo -e "  ✓ Force Disconnect Session"
echo -e "  ✓ Auto Suspend Expired/Over-Limit Users (Hourly Check)"
echo -e "  ✓ Comprehensive Reporting & Bulk Operations"
echo -e "$LINE"
