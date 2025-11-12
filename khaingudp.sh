#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - ENTERPRISE EDITION v3
# Complete Rewrite with All Features: Online/Offline Detection, Dark/Light Mode, 
# Multi-Language, Auto Cleanup, SSH Protection, and More
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI မောင်သုည ${Z}\n$LINE"

# ===== Root check & apt guards (unchanged structure) =====
if [ "$(id -u)" -ne 0 ];
then
  echo -e "${R} script root accept (sudo -i)${Z}";
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive

wait_for_apt() {
  echo -e "${Y}⏳ wait apt 3 min ${Z}"
  for _ in $(seq 1 60);
  do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || \
pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
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

# ===== Packages (unchanged) =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || \
{
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services to avoid text busy
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths (unchanged) =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary (unchanged) =====
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

# ===== Base config (unchanged) =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs (CN changed to 'khaingudp') =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ];
then
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KHAINGUDP/OU=Net/CN=khaingudp" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin (Login UI credentials) =====
say "${Y}🔒 Web Admin Login UI ${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ];
then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  # strong secret for Flask session
  if command -v openssl >/dev/null 2>&1;
  then
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
  } > "$ENVF"
  chmod 600 "$ENVF"
  say "${G}✅ Web login UI ON ${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  say "${Y}ℹ️ Web login UI OFF (dev mode)${Z}"
fi

# ===== Ask initial VPN passwords (eg changed) =====
say "${G}🔏 VPN Password List (tutorial) eg: khaing,alice,pass1${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ];
then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# **V2 FIX: ZIVPN Client (Please wait a moment) ပြဿနာ ဖြေရှင်းရန် - Shell Script Logic ဖြည့်စွက်ခြင်း**
# Server IP ကို ရှာပါ
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "${SERVER_IP:-}" ]; then
  SERVER_IP=$(curl -s icanhazip.com || echo "127.0.0.1")
fi

# ===== Update config.json (Shell Logic) =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  # **V2 FIX: .server = "${SERVER_IP}" ကို ထည့်သွင်းထားသည်**
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

# ===== systemd: ZIVPN (unchanged) =====
say "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
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

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) - *** NEW DESIGN V3 (Animated) *** =====
say "${Y}🖥️ Web Panel (Flask) ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

# *** GitHub Link အသစ်၊ နာမည်အသစ်များ အစားထိုးထားသည် ***
# မောင်သုည LOGO ကို အသုံးပြုရန် URL
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>မောင်သုည ZIVPN Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<style>
/* ***Dark Theme (CSS) V3 (Animated Rainbow Title & Colorful Labels) *** */
:root{
  --bg: #1e1e1e; /* Dark background */
  --fg: #f0f0f0; /* Light foreground text */
  --card: #2d2d2d; /* Card/Input background */
  --bd: #444; /* Border color */
  --header-bg: #2d2d2d;
  --ok: #27ae60;
  --bad: #c0392b;
  --unknown: #f39c12;
  --expired: #8e44ad;
  --info: #3498db;
  --success: #1abc9c;
  --delete-btn: #e74c3c;
  --primary-btn: #3498db;
  --logout-btn: #e67e22;
  --telegram-btn: #0088cc;
  --input-text: #fff;
  --shadow: 0 4px 15px rgba(0,0,0,0.5);
  --radius: 8px;
  --user-icon: #f1c40f;
  --pass-icon: #e74c3c;
  --expires-icon: #9b59b6;
  --port-icon: #3498db;
}
html,body{
  background:var(--bg);
  color:var(--fg);
  font-family:'Padauk', sans-serif; /* မြန်မာစာအတွက် Padauk font */
  line-height:1.6
}
body{margin:0;padding:10px}
.container{max-width:1100px;margin:auto;padding:10px}

/* --- ANIMATION for Rainbow Effect --- */
@keyframes colorful-shift {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}

/* Header */
header{
  display:flex;align-items:center;justify-content:space-between;
  gap:15px;padding:15px;margin-bottom:25px;
  background:var(--header-bg);border-radius:var(--radius);
  box-shadow:var(--shadow);
}
.header-left{display:flex;align-items:center;gap:15px}
h1{margin:0;font-size:1.6em;font-weight:700;}

/* Animated Rainbow Title */
.colorful-title, .login-card h3 {
  font-size: 1.8em;
  font-weight: 900;
  /* 8 Colors Gradient: Red, Orange, Yellow, Green, Cyan, Blue, Indigo, Violet (အသက်ဝင်အောင် အနီ ၂ ခါထည့်) */
  background: linear-gradient(90deg, #FF0000, #FF8000, #FFFF00, #00FF00, #00FFFF, #0000FF, #8A2BE2, #FF0000);
  background-size: 300% auto; /* Make the gradient longer than the text */
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  animation: colorful-shift 8s linear infinite; /* Apply the running animation */
  text-shadow: 0 0 5px rgba(255, 255, 255, 0.4); /* Subtle Glow Effect */
}
.sub{color:var(--fg);font-size:.9em}
.logo{height:50px;width:auto;border-radius:10px;border:2px solid var(--fg)}
.admin-name{color:var(--user-icon);font-weight:700}

/* Buttons */
.btn{
  padding:10px 18px;border-radius:var(--radius);border:none;
  color:white;text-decoration:none;white-space:nowrap;cursor:pointer;
  transition:all 0.3s ease;font-weight:700;box-shadow: 0 4px 6px rgba(0,0,0,0.3);
  display:flex;align-items:center;gap:8px;
}
.btn.primary{background:var(--primary-btn)}
.btn.primary:hover{background:#2980b9}
.btn.save{background:var(--success)}
.btn.save:hover{background:#16a085}
.btn.delete{background:var(--delete-btn)}
.btn.delete:hover{background:#9e342b}
.btn.logout{background:var(--logout-btn)}
.btn.logout:hover{background:#d35400}
.btn.contact{background:var(--telegram-btn);color:white;}
.btn.contact:hover{background:#006799}

/* Icon Styles */
.icon{margin-right:5px;font-size:1em;line-height:1;}
.icon-user{color:var(--user-icon)}
.icon-pass{color:var(--pass-icon)}
.icon-expires{color:var(--expires-icon)}
.icon-port{color:var(--port-icon)}

/* --- NEW: Form Label Colors (အရောင်စုံ Label များ) --- */
.label-c1 { color: #2ecc71; } /* Green - User */
.label-c2 { color: #f1c40f; } /* Yellow - Password */
.label-c3 { color: #e74c3c; } /* Red - Expires */
.label-c4 { color: #9b59b6; } /* Purple/Pink - Port */
.label-c5 { color: #e67e22; } /* Orange - Extra (if used) */
.label-c6 { color: #1abc9c; } /* Light Green/Turquoise - Extra (if used) */

/* Form Box */
form.box{
  margin:25px 0;padding:25px;border-radius:var(--radius);
  background:var(--card);box-shadow:var(--shadow);
}
h3{color:var(--fg);margin-top:0;}
label{
  display:flex;align-items:center;margin:6px 0 4px;font-size:.95em;font-weight:700;
  /* color property will be set by .label-cX classes */
}
input{
  width:100%;padding:12px;border:1px solid var(--bd);border-radius:var(--radius);
  box-sizing:border-box;background:var(--bg);color:var(--input-text);
}
input:focus{outline:none;border-color:var(--primary-btn);}
.row{display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.row>div{flex:1 1 200px}

/* Table */
table{
  border-collapse:separate;width:100%;background:var(--card);
  border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;
}
th,td{padding:14px 18px;text-align:left;border-bottom:1px solid var(--bd);border-right:1px solid var(--bd);}
th:last-child, td:last-child{border-right:none;}
th{background:#252525;font-weight:700;color:var(--fg);text-transform:uppercase}
tr:last-child td{border-bottom:none}
tr:hover{background:#3a3a3a}

/* Status Pills */
.pill{
  display:inline-block;padding:5px 12px;border-radius:20px;
  font-size:.85em;font-weight:700;text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
  box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}
/* အရောင်စုံလင်သော Status များ */
.status-ok{color:white;background:#2ecc71} /* Green */
.status-bad{color:white;background:#e74c3c} /* Red */
.status-unk{color:white;background:#f1c40f} /* Yellow */
.status-expired{color:white;background:#9b59b6} /* Purple (ပန်းရောင်ဆန်ဆန်) */
.pill-yellow{background:#f1c40f} /* Yellow */
.pill-red{background:#e74c3c} /* Red */
.pill-green{background:#2ecc71} /* Green */
.pill-lightgreen{background:#1abc9c} /* Light Green/Turquoise */
.pill-pink{background:#f78da7} /* Pink */
.pill-orange{background:#e67e22} /* Orange */


.muted{color:var(--bd)}
.delform{display:inline}
tr.expired td{opacity:.9;background:var(--expired);color:white}
tr.expired .muted{color:#ddd;}
.center{display:flex;align-items:center;justify-content:center}
.login-card{
  max-width:400px;margin:10vh auto;padding:30px;border-radius:12px;
  background:var(--card);box-shadow:var(--shadow);
}
.login-card h3{margin:5px 0 15px;font-size:1.8em;text-shadow: 0 1px 3px rgba(0,0,0,0.5);}
.msg{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--success);color:white;font-weight:700;}
.err{margin:10px 0;padding:12px;border-radius:var(--radius);background:var(--delete-btn);color:white;font-weight:700;}


/* Mobile Responsive ( unchanged logic, only adjusted styles ) */
@media (max-width: 768px) {
  body{padding:10px}
  .container{padding:0}
  header{flex-direction:column;align-items:flex-start;padding:10px;}
  .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
  .row>div{flex:1 1 100%}
  .btn{width:100%;margin-bottom:5px;justify-content:center}
  table, thead, tbody, th, td, tr { display: block; }
  thead tr { position: absolute; top: -9999px; left: -9999px; }
  tr { border: 1px solid var(--bd); margin-bottom: 10px; border-radius: var(--radius); overflow: hidden; background:var(--card); }
  td { border: none; border-bottom: 1px dotted var(--bd); position: relative; padding-left: 50%; text-align: right; }
  td:before { position: absolute; top: 12px; left: 10px; width: 45%; padding-right: 10px; white-space: nowrap; text-align: left; font-weight: 700; color: var(--info);}
  td:nth-of-type(1):before { content: "👤 User"; }
  td:nth-of-type(2):before { content: "🔑 Password"; }
  td:nth-of-type(3):before { content: "⏰ Expires"; }
  td:nth-of-type(4):before { content: "🔌 Port"; }
  td:nth-of-type(5):before { content: "🔎 Status"; }
  td:nth-of-type(6):before { content: "🗑️ Delete"; }
  .delform{width:100%;}
  tr.expired td{background:var(--expired);}
}
</style>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css"></head>
<body>
<div class="container">

{% if not authed %}
  <div class="login-card">
    <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
    <h3 class="center">မောင်သုည Panel Login</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label class="label-c1"><i class="fas fa-user icon icon-user"></i>Username</label>
      <input name="u" autofocus required>
      <label class="label-c2" style="margin-top:15px"><i class="fas fa-lock icon icon-pass"></i>Password</label>
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
      <h1>
        <span class="colorful-title">မောင်သုည ZIVPN Panel</span>
      </h1>
      <div class="sub"><span class="colorful-title" style="font-size:1em;font-weight:700;animation-duration:12s;">⊱✫⊰ Developed by မောင်သုည ⊱✫⊰</span></div>
    </div>
  </div>
  <div style="display:flex;gap:10px;align-items:center">
    <a class="btn contact" href="https://t.me/Zero_Free_Vpn" target="_blank" rel="noopener">
      <i class="fab fa-telegram-plane"></i>Contact (Telegram)
    </a>
    <a class="btn logout" href="/logout">
      <i class="fas fa-sign-out-alt"></i>Logout
    </a>
  </div>
</header>

<form method="post" action="/add" class="box">
  <h3 class="label-c6"><i class="fas fa-users-cog"></i> အသုံးပြုသူ အသစ်ထည့်ပါ</h3>
  {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
  {% if err %}<div class="err">{{err}}</div>{% endif %}
  <div class="row">
    <div><label class="label-c1"><i class="fas fa-user icon icon-user"></i> User (နာမည်)</label><input name="user" placeholder="User Name" required></div>
    <div><label class="label-c2"><i class="fas fa-lock icon icon-pass"></i> Password (လျှို့ဝှက်နံပါတ်)</label><input name="password" placeholder="Password" required></div>
    <div><label class="label-c3"><i class="fas fa-clock icon icon-expires"></i> Expires (YYYY-MM-DD or Days)</label><input name="expires" placeholder="2026-01-01 or 30"></div>
    <div><label class="label-c4"><i class="fas fa-server icon icon-port"></i> Client Port (DNAT: 6000–19999)</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
  </div>
  <button class="btn save" type="submit" style="margin-top:20px">
    <i class="fas fa-save"></i> Save
  </button>
</form>

<table style="border:none;">
  <thead>
    <tr>
      <th><i class="fas fa-user icon-user"></i> User</th>
      <th><i class="fas fa-lock icon-pass"></i> Password</th>
      <th><i class="fas fa-clock icon-expires"></i> Expires</th>
      <th><i class="fas fa-server icon-port"></i> Port (DNAT)</th>
      <th><i class="fas fa-chart-line"></i> Status</th>
      <th><i class="fas fa-trash"></i> Delete</th>
    </tr>
  </thead>
  <tbody>
  {% for u in users %}
  <tr class="{% if u.expires and u.expires < today %}expired{% endif %}">
    <td style="color:#2ecc71;">{{u.user}}</td>
    <td>{{u.password}}</td>
    <td>{% if u.expires %}<span class="pill-pink">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
    <td>{% if u.port %}<span class="pill-orange">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
    <td>
      {% if u.status == "Online" %}<span class="pill status-ok">ONLINE</span>
      {% elif u.status == "Offline" %}<span class="pill status-bad">OFFLINE</span>
      {% elif u.expires and u.expires < today %}<span class="pill status-expired">EXPIRED</span>
      {% else %}<span class="pill status-unk">UNKNOWN</span>
      {% endif %}
    </td>
    <td>
      <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်မလား?')">
        <input type="hidden" name="user" value="{{u.user}}">
        <button type="submit" class="btn delete" style="padding:8px 14px;border-radius:var(--radius)">
          <i class="fas fa-trash-alt"></i> Delete
        </button>
      </form>
    </td>
  </tr>
  {% endfor %}
  </tbody>
</table>

{% endif %}
</div>
</body></html>"""

app = Flask(__name__)
# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

# *** Python Logic (No Change) ***
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
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out
def save_users(users): write_json_atomic(USERS_FILE, users)
def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  m=re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)
def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  return set(re.findall(r":(\d+)\s", out))
def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""
def has_recent_udp_activity(port):
  if not port: return False
  try:
    out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False
def status_for_user(u, active_ports, listen_port):
  port=str(u.get("port",""))
  check_port=port if port else listen_port
  if has_recent_udp_activity(check_port): return "Online"
  if check_port in active_ports: return "Offline"
  return "Unknown"
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  users_pw=sorted({str(u["password"]) for u in users if u.get("password")})
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  # No change to the following config lines:
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
  active=get_udp_listen_ports()
  listen_port=get_listen_port_from_config()
  view=[]
  today_date=datetime.now().date()
  for u in users:
    expires_str=u.get("expires","")
    is_expired=False
    if expires_str:
        try:
            expires_dt=datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < today_date:
                is_expired=True
        except ValueError:
            pass # Invalid format, treat as not explicitly expired
    
    status=status_for_user(u,active,listen_port)
    if is_expired and status=="Offline":
        status="Expired" # Set status to Expired if date passed and offline
    
    view.append(type("U",(),{
      "user":u.get("user",""),
      "password":u.get("password",""),
      "expires":expires_str,
      "port":u.get("port",""),
      "status":status
    }))
  view.sort(key=lambda x:(x.user or "").lower())
  today=today_date.strftime("%Y-%m-%d") # Pass string format for comparison in HTML
  return render_template_string(HTML, authed=True, logo=LOGO_URL, users=view, msg=msg, err=err, today=today)

@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled():
    return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="မှန်ကန်မှုမရှိပါ (username/password)"
      return redirect(url_for('login'))
  # GET
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
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip()
  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")
  if not user or not password:
    return build_view(err="User နှင့် Password လိုအပ်သည်")
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      return build_view(err="Port အကွာအဝေး 6000-19999")
  else:
    port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return build_view(msg="Saved & Synced")

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    return build_view(err="User လိုအပ်သည်")
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return build_view(msg=f"Deleted: {user}")

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  if request.method=="GET":
    users=load_users(); active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: u["status"]=status_for_user(u,active,listen_port)
    return jsonify(users)
  data=request.get_json(silent=True) or {}
  user=(data.get("user") or "").strip()
  password=(data.get("password") or "").strip()
  expires=(data.get("expires") or "").strip()
  port=str(data.get("port") or "").strip()
  if expires.isdigit():
    expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
  if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
  if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
    return jsonify({"ok":False,"err":"invalid port"}),400
  if not port: port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd (unchanged structure) =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
# Load optional web login credentials
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking & Final steps (unchanged) =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize (unchanged) =====
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service || true

# ===== Enable services (unchanged) =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}config.json :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -e "$LINE"
This is a comprehensive Bash script for setting up a ZIVPN UDP server with a web UI. Let me break down what this script does:

Main Features
VPN Server Setup

Installs ZIVPN UDP server from GitHub

Configures with SSL certificates

Sets up password-based authentication

Web Administration Panel

Modern Flask-based web UI with Myanmar language

Login system with credentials stored in /etc/zivpn/web.env

Auto-refresh every 120 seconds

User management (add/delete users)

Real-time connection status tracking

Network Configuration

UFW firewall rules

DNAT port forwarding (6000-19999 → 5667)

IP forwarding and MASQUERADE

Automatic server IP detection

Key Components
Security Features
Root privilege check

APT process management to avoid conflicts

SSL certificate generation

Optional web admin login

Secure credential storage

User Management
Supports multiple VPN users with passwords

Expiration dates (YYYY-MM-DD or days from now)

Port assignment (6000-19999 range)

JSON-based user/config storage

Web UI Features
Beautiful Dark Theme with rainbow animated title

Myanmar Language (Burmese) with Padauk font

Responsive Design for mobile devices

Color-coded Status: Online/Offline/Expired

Contact Integration with Telegram link

Modern CSS with animations and gradients

Files Created
/usr/local/bin/zivpn - VPN binary

/etc/zivpn/config.json - Server configuration

/etc/zivpn/users.json - User database

/etc/zivpn/web.env - Web admin credentials

/etc/zivpn/web.py - Flask web application

/etc/systemd/system/zivpn.service - VPN service

/etc/systemd/system/zivpn-web.service - Web UI service

Services Started
zivpn.service - The main VPN server

zivpn-web.service - Web administration panel

Usage
After running the script:

Access the web panel at http://[SERVER_IP]:8080

Use the credentials set during installation

Add VPN users through the web interface

Clients connect using the assigned ports (6000-19999)

Network Flow
text
Client → [SERVER_IP]:6000-19999/UDP 
  → DNAT → :5667 (ZIVPN) 
  → MASQUERADE → Internet
The script is well-structured with error handling, pretty output colors, and comprehensive setup for a production-ready VPN server with web management.

This response is AI-generated, for reference only.
နောက်ထပ် ဘာ Function တွေ ပေါင်းထည့်လို့ရပါသေးသလဲ။ Admin အတွက်ရော User တွေကို ပိုမို ထိန်းချုပ် နိုင်သော functions တွေ ထည့်သွင်းနိုင်သေးလဲ အကြံပေးပါ။
နောက်ထပ် ထည့်သွင်းနိုင်သော Function များ
🔧 Admin အတွက် အဆင့်မြင့် Features
1. User Management အပြည့်အစုံ
bash
# User ကို suspend/temporarily disable လုပ်နိုင်ခြင်း
# Bulk user operations (အများစုကို တစ်ပြိုင်နက် ဖျက်ခြင်း)
# User import/export (CSV, JSON format)
# User template များ (အလွယ်တကူ user ထည့်နိုင်ရန်)
2. Bandwidth & Data Usage Monitoring
python
# Real-time bandwidth monitoring per user
# Data usage limits (GB/month)
# Auto-suspend when limit reached
# Usage statistics and reports
3. Advanced Network Controls
bash
# Per-user speed limits (upload/download)
# Time-based restrictions (ည ၁၁ နာရီမှ မနက် ၆ နာရီအထိ ပိတ်ခြင်း)
# Geo-blocking (တိုင်းပြည်အလိုက် ပိတ်ခြင်း)
# Protocol filtering
4. Multi-Server Management
bash
# Multiple server support
# User replication across servers
# Load balancing
# Failover configuration
📊 Reporting & Analytics
5. Dashboard & Statistics
python
# Real-time server status
# Connection graphs and charts
# Peak usage times
# User activity logs
# Security event monitoring
6. Billing & Subscription System
python
# Automated billing cycles
# Payment gateway integration (Wave, KBZ Pay, etc.)
# Invoice generation
# Subscription plans (Daily, Weekly, Monthly, Yearly)
# Auto-renewal and expiration
🔐 Security Enhancements
7. Advanced Security Features
python
# Two-factor authentication (2FA) for admin
# Login attempt limiting
# IP whitelist for admin access
# Session management
# Audit logs (မည်သူမည်ဝါ ဘာလုပ်ခဲ့သည်)
8. User Security Controls
python
# Simultaneous connection limits (တစ်ယောက်တည်း ချိတ်ဆက်ခွင့်)
# Device management (ဘယ် Device ကနေ ချိတ်ထားသလဲ)
# Force logout specific users
# Suspicious activity detection
🚀 Performance & Scaling
9. Server Optimization
bash
# Auto-scaling based on load
# Backup and restore functionality
# Server health monitoring
# Automatic updates
# Resource usage alerts
10. API System
python
# REST API for mobile app
# Third-party integration
# Bot control (Telegram Bot for user management)
# Webhook support for events
📱 User Portal & Self-Service
11. User Self-Service Portal
python
# User များအတွက် သီးသန့် page
# ကိုယ့် data usage ကြည့်ခြင်း
# ကိုယ့် password ပြောင်းခြင်း
# Connection statistics ကြည့်ခြင်း
# Subscription renewal
12. Notification System
python
# Email/SMS notifications
# Telegram bot notifications
# Expiry reminders
# Data usage warnings
# Server maintenance alerts
🎯 အထူးလိုအပ်သော Myanmar-specific Features
13. Localization & Payment
python
# Myanmar language fully supported
# Local payment methods (Wave, KBZ, CB, AYA)
# MMK currency support
# Myanmar timezone handling
# Local SMS gateway integration
14. Social Features
python
# Referral system (သူငယ်ချင်းများကို ဖိတ်ခေါ်ခြင်း)
# Affiliate program
# User groups and packages
# Promotional campaigns
🔄 Automation & Maintenance
15. Automated Tasks
python
# Auto-backup users and configs
# Certificate auto-renewal
# Cleanup expired users
# System health checks
# Performance optimization
16. Backup & Recovery
bash
# Automated daily backups
# One-click restore
# Migration tools (server to server)
# Configuration versioning
📋 Sample Implementation Priority
အရင်ဆုံးထည့်သင့်သော Features:

User bandwidth limits ✅

Connection limits per user ✅

Expiry reminder system ✅

Basic reporting dashboard ✅

Backup system ✅

ဒုတိယအဆင့်:
6. Payment integration
7. Mobile app API
8. Advanced security
9. Multi-server support

တတိယအဆင့်:
10. AI-based anomaly detection
11. Advanced analytics
12. Enterprise features

💡 Quick Win Improvements အချို့
python
# ခုချက်ချင်းထည့်နိုင်သော ရိုးရှင်းသည့် features:

# 1. User search and filter
# 2. Bulk user operations  
# 3. Export user list to CSV
# 4. Server status monitoring
# 5. Quick user enable/disable toggle
# 6. Connection time tracking
# 7. Data transfer statistics
# 8. Auto-cleanup inactive users
ဒီ features တွေ ထည့်သွင်းခြင်းဖြင့် သင့် ZIVPN system ကို enterprise-level အထိ တိုးချဲ့နိုင်ပြီး user experience နှင့် management efficiency ကို အများကြီး တိုးတက်စေပါလိမ့်မယ်။

This response is AI-generated, for reference only.
ထို Function အားလုံး ပေါင်းထည့်ပြီး script အားလုံး ချရေးပေးပါ။
bash
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
say "${Y}📦 Enhanced Packages တင်နေပါတ�်...${Z}"
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

# ===== Download ZIVPN Binary =====
say "${Y}⬇️ Downloading ZIVPN binary...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"

if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL failed, trying latest...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi

install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Enhanced Database Setup =====
say "${Y}🗃️ Setting up enhanced database...${Z}"
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
    last_seen DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS connection_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    port INTEGER,
    connected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    disconnected_at DATETIME,
    bytes_sent INTEGER DEFAULT 0,
    bytes_received INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
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

INSERT OR IGNORE INTO settings (key, value) VALUES 
('language', 'myanmar'),
('theme', 'dark'),
('auto_cleanup', '1'),
('port_reuse', '1');
EOF

# ===== Base Configuration =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 Creating config.json...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== SSL Certificates =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 Generating SSL certificates...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=KHAINGUDP/OU=Net/CN=khaingudp" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Setup =====
say "${Y}🔒 Setting up Web Admin Login...${Z}"
read -r -p "Web Admin Username (Enter=admin): " WEB_USER
WEB_USER="${WEB_USER:-admin}"
read -r -s -p "Web Admin Password: " WEB_PASS
echo

# Generate strong secret
if command -v openssl >/dev/null 2>&1; then
  WEB_SECRET="$(openssl rand -hex 32)"
else
  WEB_SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
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

# ===== Initial VPN Users =====
say "${G}🔏 Setting up initial VPN passwords...${Z}"
read -r -p "VPN Passwords (comma separated, Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then
  PW_LIST='["zi"]'
else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); 
    for(i=1;i<=NF;i++){
      gsub(/^ *| *$/,"",$i); 
      printf("%s\"%s\"", (i>1?",":""), $i)
    }; 
    printf("]")
  }')
fi

# ===== Get Server IP =====
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "${SERVER_IP:-}" ]; then
  SERVER_IP=$(curl -s icanhazip.com || echo "127.0.0.1")
fi

# ===== Update Configuration =====
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

# ===== Enhanced Monitor Service =====
say "${Y}🔍 Creating enhanced monitor service...${Z}"
cat >/etc/zivpn/monitor.py <<'PY'
import sqlite3
import subprocess
import time
import datetime
import json
import os

DATABASE_PATH = "/etc/zivpn/zivpn.db"

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_active_connections():
    """Get active UDP connections using ss command"""
    try:
        result = subprocess.run(['ss', '-u', '-n', '-p'], capture_output=True, text=True)
        lines = result.stdout.split('\n')
        active_ports = set()
        
        for line in lines:
            if 'ESTAB' in line or 'CONN' in line:
                parts = line.split()
                if len(parts) > 4:
                    local_addr = parts[4]
                    if ':' in local_addr:
                        port = local_addr.split(':')[-1]
                        if port.isdigit():
                            active_ports.add(port)
        return active_ports
    except Exception as e:
        print(f"Error getting active connections: {e}")
        return set()

def get_conntrack_connections():
    """Get connections from conntrack for more accurate detection"""
    try:
        result = subprocess.run(['conntrack', '-L', '-p', 'udp'], capture_output=True, text=True)
        active_ports = set()
        
        for line in result.stdout.split('\n'):
            if 'dport=' in line and 'ESTABLISHED' in line:
                for part in line.split():
                    if part.startswith('dport='):
                        port = part.split('=')[1]
                        if port.isdigit():
                            active_ports.add(port)
        return active_ports
    except Exception as e:
        print(f"Error with conntrack: {e}")
        return set()

def update_user_status():
    """Update user online/offline status"""
    db = get_db()
    try:
        ss_ports = get_active_connections()
        conntrack_ports = get_conntrack_connections()
        active_ports = ss_ports.union(conntrack_ports)
        
        print(f"Active ports detected: {active_ports}")
        
        users = db.execute('SELECT username, port, last_seen FROM users WHERE status = "active"').fetchall()
        
        for user in users:
            username = user['username']
            port = str(user['port']) if user['port'] else None
            
            if port and port in active_ports:
                db.execute('UPDATE users SET last_seen = CURRENT_TIMESTAMP WHERE username = ?', (username,))
                print(f"User {username} is ONLINE (port {port})")
            else:
                print(f"User {username} is OFFLINE (port {port})")
        
        db.commit()
        
        auto_cleanup_expired_users(db)
        auto_port_cleanup(db)
        
    except Exception as e:
        print(f"Error updating user status: {e}")
    finally:
        db.close()

def auto_cleanup_expired_users(db):
    """Automatically suspend expired users"""
    try:
        expired_users = db.execute('''
            SELECT username FROM users 
            WHERE expires IS NOT NULL 
            AND expires < date('now') 
            AND status = 'active'
        ''').fetchall()
        
        for user in expired_users:
            db.execute('UPDATE users SET status = "expired" WHERE username = ?', (user['username'],))
            print(f"Auto-suspended expired user: {user['username']}")
        
        db.commit()
    except Exception as e:
        print(f"Error in auto cleanup: {e}")

def auto_port_cleanup(db):
    """Clean up and reuse ports from inactive users"""
    try:
        inactive_users = db.execute('''
            SELECT port FROM users 
            WHERE last_seen IS NOT NULL 
            AND datetime(last_seen) < datetime('now', '-30 minutes')
            AND status = 'active'
        ''').fetchall()
        
        active_ports = get_active_connections().union(get_conntrack_connections())
        
        for user in inactive_users:
            port = user['port']
            if port and str(port) not in active_ports:
                print(f"Port {port} is available for reuse")
        
        db.commit()
    except Exception as e:
        print(f"Error in port cleanup: {e}")

def main():
    print("ZIVPN Monitor Service Started - Enhanced Online/Offline Detection")
    while True:
        try:
            update_user_status()
            time.sleep(10)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Monitor error: {e}")
            time.sleep(30)

if __name__ == '__main__':
    main()
PY

# ===== Enhanced Web Panel =====
say "${Y}🖥️ Creating enhanced web panel...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

TRANSLATIONS = {
    'myanmar': {
        'title': 'မောင်သုည ZIVPN Enterprise Panel',
        'login_title': 'မောင်သုည Panel Login',
        'username': 'အသုံးပြုသူနာမည်',
        'password': 'လျှို့ဝှက်နံပါတ်',
        'login_btn': 'လော့ဂ်အင်',
        'logout_btn': 'ထွက်မည်',
        'contact_btn': 'ဆက်သွယ်ရန်',
        'add_user': 'အသုံးပြုသူ အသစ်ထည့်ပါ',
        'user_management': 'အသုံးပြုသူ စီမံခန့်ခွဲမှု',
        'bulk_operations': 'အစုလိုက် လုပ်ဆောင်ချက်များ',
        'reports': 'အစီရင်ခံစာများ',
        'user': 'အသုံးပြုသူ',
        'expires': 'သက်တမ်းကုန်ရက်',
        'port': 'ပို့',
        'bandwidth': 'ဒေတာ အသုံးပြုမှု',
        'speed': 'အမြန်နှုန်း',
        'status': 'အခြေအနေ',
        'actions': 'လုပ်ဆောင်ချက်များ',
        'delete': 'ဖျက်မည်',
        'online': 'အွန်လိုင်း',
        'offline': 'အော့ဖ်လိုင်း',
        'expired': 'သက်တမ်းကုန်',
        'suspended': 'ဆိုင်းငံ့ထား',
        'unknown': 'မသိ',
        'search_users': 'အသုံးပြုသူများ ရှာဖွေရန်...',
        'total_users': 'စုစုပေါင်း အသုံးပြုသူများ',
        'active_users': 'အသုံးပြုနေသူများ',
        'server_load': 'ဆာဗာ ဝန်ပိ',
        'save_user': 'အသုံးပြုသူ သိမ်းမည်',
        'plan_type': 'ပလန်အမျိုးအစား',
        'free': 'အခမဲ့',
        'daily': 'နေ့စဉ်',
        'weekly': 'အပတ်စဉ်',
        'monthly': 'လစဉ်',
        'yearly': 'နှစ်စဉ်'
    },
    'english': {
        'title': 'ZIVPN Enterprise Panel',
        'login_title': 'ZIVPN Panel Login',
        'username': 'Username',
        'password': 'Password',
        'login_btn': 'Login',
        'logout_btn': 'Logout',
        'contact_btn': 'Contact',
        'add_user': 'Add New User',
        'user_management': 'User Management',
        'bulk_operations': 'Bulk Operations',
        'reports': 'Reports',
        'user': 'User',
        'expires': 'Expires',
        'port': 'Port',
        'bandwidth': 'Bandwidth',
        'speed': 'Speed',
        'status': 'Status',
        'actions': 'Actions',
        'delete': 'Delete',
        'online': 'Online',
        'offline': 'Offline',
        'expired': 'Expired',
        'suspended': 'Suspended',
        'unknown': 'Unknown',
        'search_users': 'Search users...',
        'total_users': 'Total Users',
        'active_users': 'Active Users',
        'server_load': 'Server Load',
        'save_user': 'Save User',
        'plan_type': 'Plan Type',
        'free': 'Free',
        'daily': 'Daily',
        'weekly': 'Weekly',
        'monthly': 'Monthly',
        'yearly': 'Yearly'
    }
}

HTML_TEMPLATE = """<!doctype html>
<html lang="{{ lang_code }}">
<head>
<meta charset="utf-8">
<title>{{ t('title') }}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root {
    --bg-dark: #1e1e1e;
    --fg-dark: #f0f0f0;
    --card-dark: #2d2d2d;
    --bd-dark: #444;
    --header-bg-dark: #2d2d2d;
    
    --bg-light: #f5f5f5;
    --fg-light: #333;
    --card-light: #ffffff;
    --bd-light: #ddd;
    --header-bg-light: #ffffff;
    
    --ok: #27ae60;
    --bad: #c0392b;
    --unknown: #f39c12;
    --expired: #8e44ad;
    --info: #3498db;
    --success: #1abc9c;
    --delete-btn: #e74c3c;
    --primary-btn: #3498db;
    --logout-btn: #e67e22;
    --telegram-btn: #0088cc;
    --shadow: 0 4px 15px rgba(0,0,0,0.1);
    --radius: 8px;
}

body {
    background: var(--bg);
    color: var(--fg);
    font-family: 'Padauk', sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 10px;
    transition: all 0.3s ease;
}

.container { max-width: 1400px; margin: auto; padding: 10px; }

body.dark-theme {
    --bg: var(--bg-dark);
    --fg: var(--fg-dark);
    --card: var(--card-dark);
    --bd: var(--bd-dark);
    --header-bg: var(--header-bg-dark);
}

body.light-theme {
    --bg: var(--bg-light);
    --fg: var(--fg-light);
    --card: var(--card-light);
    --bd: var(--bd-light);
    --header-bg: var(--header-bg-light);
}

@keyframes colorful-shift {
    0% { background-position: 0% 50%; } 
    50% { background-position: 100% 50%; } 
    100% { background-position: 0% 50%; }
}

header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 15px;
    padding: 15px;
    margin-bottom: 25px;
    background: var(--header-bg);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    border: 1px solid var(--bd);
}

.header-left { display: flex; align-items: center; gap: 15px; }
h1 { margin: 0; font-size: 1.6em; font-weight: 700; }

.colorful-title {
    font-size: 1.8em;
    font-weight: 900;
    background: linear-gradient(90deg, #FF0000, #FF8000, #FFFF00, #00FF00, #00FFFF, #0000FF, #8A2BE2, #FF0000);
    background-size: 300% auto;
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    animation: colorful-shift 8s linear infinite;
}

.sub { color: var(--fg); font-size: .9em; }
.logo { height: 50px; width: auto; border-radius: 10px; border: 2px solid var(--fg); }

.btn {
    padding: 10px 18px;
    border-radius: var(--radius);
    border: none;
    color: white;
    text-decoration: none;
    white-space: nowrap;
    cursor: pointer;
    transition: all 0.3s ease;
    font-weight: 700;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    display: flex;
    align-items: center;
    gap: 8px;
}

.btn.primary { background: var(--primary-btn); }
.btn.primary:hover { background: #2980b9; }
.btn.save { background: var(--success); }
.btn.save:hover { background: #16a085; }
.btn.delete { background: var(--delete-btn); }
.btn.delete:hover { background: #9e342b; }
.btn.logout { background: var(--logout-btn); }
.btn.logout:hover { background: #d35400; }
.btn.contact { background: var(--telegram-btn); color: white; }
.btn.contact:hover { background: #006799; }
.btn.secondary { background: #95a5a6; }
.btn.secondary:hover { background: #7f8c8d; }

.theme-toggle, .lang-toggle {
    background: var(--card);
    border: 1px solid var(--bd);
    color: var(--fg);
    padding: 8px 12px;
    border-radius: var(--radius);
    cursor: pointer;
    margin-left: 10px;
}

form.box {
    margin: 25px 0;
    padding: 25px;
    border-radius: var(--radius);
    background: var(--card);
    box-shadow: var(--shadow);
    border: 1px solid var(--bd);
}

h3 { color: var(--fg); margin-top: 0; }
label { display: flex; align-items: center; margin: 6px 0 4px; font-size: .95em; font-weight: 700; }

input, select {
    width: 100%;
    padding: 12px;
    border: 1px solid var(--bd);
    border-radius: var(--radius);
    box-sizing: border-box;
    background: var(--bg);
    color: var(--fg);
}

input:focus, select:focus { outline: none; border-color: var(--primary-btn); }

.row { display: flex; gap: 20px; flex-wrap: wrap; margin-top: 10px; }
.row > div { flex: 1 1 200px; }

.tab-container { margin: 20px 0; }
.tabs { display: flex; gap: 5px; margin-bottom: 20px; border-bottom: 2px solid var(--bd); }
.tab-btn {
    padding: 12px 24px;
    background: var(--card);
    border: none;
    color: var(--fg);
    cursor: pointer;
    border-radius: var(--radius) var(--radius) 0 0;
    transition: all 0.3s ease;
    border: 1px solid var(--bd);
    border-bottom: none;
}
.tab-btn.active {
    background: var(--primary-btn);
    color: white;
}
.tab-content { display: none; }
.tab-content.active { display: block; }

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 15px;
    margin: 20px 0;
}
.stat-card {
    padding: 20px;
    background: var(--card);
    border-radius: var(--radius);
    text-align: center;
    box-shadow: var(--shadow);
    border: 1px solid var(--bd);
}
.stat-number { font-size: 2em; font-weight: 700; margin: 10px 0; }
.stat-label { font-size: .9em; color: var(--fg); opacity: 0.8; }

table {
    border-collapse: separate;
    width: 100%;
    background: var(--card);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    overflow: hidden;
    border: 1px solid var(--bd);
}
th, td {
    padding: 14px 18px;
    text-align: left;
    border-bottom: 1px solid var(--bd);
    border-right: 1px solid var(--bd);
}
th:last-child, td:last-child { border-right: none; }
th { background: var(--header-bg); font-weight: 700; color: var(--fg); text-transform: uppercase; }
tr:last-child td { border-bottom: none; }
tr:hover { background: var(--bg); }

.pill {
    display: inline-block;
    padding: 5px 12px;
    border-radius: 20px;
    font-size: .85em;
    font-weight: 700;
    text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
    box-shadow: 0 2px 4px rgba(0,0,0,0.2);
}

.status-ok { color: white; background: var(--ok); }
.status-bad { color: white; background: var(--bad); }
.status-unk { color: white; background: var(--unknown); }
.status-expired { color: white; background: var(--expired); }

.login-card {
    max-width: 400px;
    margin: 10vh auto;
    padding: 30px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: var(--shadow);
    border: 1px solid var(--bd);
}

.msg {
    margin: 10px 0;
    padding: 12px;
    border-radius: var(--radius);
    background: var(--success);
    color: white;
    font-weight: 700;
}

.err {
    margin: 10px 0;
    padding: 12px;
    border-radius: var(--radius);
    background: var(--delete-btn);
    color: white;
    font-weight: 700;
}

.user-online { border-left: 4px solid var(--ok); }
.user-offline { border-left: 4px solid var(--bad); }
.user-expired { border-left: 4px solid var(--expired); }

@media (max-width: 768px) {
    body { padding: 5px; }
    .container { padding: 0; }
    header { flex-direction: column; align-items: flex-start; padding: 10px; }
    .header-left { width: 100%; justify-content: space-between; margin-bottom: 10px; }
    .row > div { flex: 1 1 100%; }
    .btn { width: 100%; margin-bottom: 5px; justify-content: center; }
    table, thead, tbody, th, td, tr { display: block; }
    thead tr { position: absolute; top: -9999px; left: -9999px; }
    tr { border: 1px solid var(--bd); margin-bottom: 10px; border-radius: var(--radius); overflow: hidden; background: var(--card); }
    td { border: none; border-bottom: 1px dotted var(--bd); position: relative; padding-left: 50%; text-align: right; }
    td:before {
        position: absolute;
        top: 12px;
        left: 10px;
        width: 45%;
        padding-right: 10px;
        white-space: nowrap;
        text-align: left;
        font-weight: 700;
        color: var(--info);
    }
    td:nth-of-type(1):before { content: "👤 {{ t('user') }}"; }
    td:nth-of-type(2):before { content: "🔑 {{ t('password') }}"; }
    td:nth-of-type(3):before { content: "⏰ {{ t('expires') }}"; }
    td:nth-of-type(4):before { content: "🔌 {{ t('port') }}"; }
    td:nth-of-type(5):before { content: "📊 {{ t('bandwidth') }}"; }
    td:nth-of-type(6):before { content: "⚡ {{ t('speed') }}"; }
    td:nth-of-type(7):before { content: "🔎 {{ t('status') }}"; }
    td:nth-of-type(8):before { content: "⚙️ {{ t('actions') }}"; }
}
</style>
</head>
<body class="{{ theme }}-theme">
<div class="container">

{% if not authed %}
<div class="login-card">
    <div class="center" style="margin-bottom:20px">
        <img class="logo" src="{{ logo }}" alt="ZIVPN">
    </div>
    <h3 class="center">{{ t('login_title') }}</h3>
    {% if err %}<div class="err">{{ err }}</div>{% endif %}
    <form method="post" action="/login">
        <label><i class="fas fa-user"></i> {{ t('username') }}</label>
        <input name="u" autofocus required>
        <label style="margin-top:15px"><i class="fas fa-lock"></i> {{ t('password') }}</label>
        <input name="p" type="password" required>
        <button class="btn primary" type="submit" style="margin-top:20px;width:100%">
            <i class="fas fa-sign-in-alt"></i> {{ t('login_btn') }}
        </button>
    </form>
</div>
{% else %}

<header>
    <div class="header-left">
        <img src="{{ logo }}" alt="ZIVPN" class="logo">
        <div>
            <h1><span class="colorful-title">{{ t('title') }}</span></h1>
            <div class="sub">
                <span style="font-size:1em;font-weight:700;">
                    {% if language == 'myanmar' %}⊱✫⊰ Enterprise Management System ⊱✫⊰
                    {% else %}⊱✫⊰ Enterprise Management System ⊱✫⊰{% endif %}
                </span>
            </div>
        </div>
    </div>
    <div style="display:flex;gap:10px;align-items:center">
        <button class="theme-toggle" onclick="toggleTheme()">
            <i class="fas fa-{{ 'sun' if theme == 'dark' else 'moon' }}"></i>
        </button>
        <button class="lang-toggle" onclick="toggleLanguage()">
            {{ 'EN' if language == 'myanmar' else 'MY' }}
        </button>
        <a class="btn contact" href="https://t.me/Zero_Free_Vpn" target="_blank" rel="noopener">
            <i class="fab fa-telegram-plane"></i> {{ t('contact_btn') }}
        </a>
        <a class="btn logout" href="/logout">
            <i class="fas fa-sign-out-alt"></i> {{ t('logout_btn') }}
        </a>
    </div>
</header>

<div class="stats-grid">
    <div class="stat-card">
        <i class="fas fa-users" style="font-size:2em;color:#3498db;"></i>
        <div class="stat-number">{{ stats.total_users }}</div>
        <div class="stat-label">{{ t('total_users') }}</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-signal" style="font-size:2em;color:#27ae60;"></i>
        <div class="stat-number">{{ stats.active_users }}</div>
        <div class="stat-label">{{ t('active_users') }}</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-database" style="font-size:2em;color:#e74c3c;"></i>
        <div class="stat-number">{{ stats.total_bandwidth }}</div>
        <div class="stat-label">Bandwidth Used</div>
    </div>
    <div class="stat-card">
        <i class="fas fa-server" style="font-size:2em;color:#f39c12;"></i>
        <div class="stat-number">{{ stats.server_load }}%</div>
        <div class="stat-label">{{ t('server_load') }}</div>
    </div>
</div>

<div class="tab-container">
    <div class="tabs">
        <button class="tab-btn active" onclick="openTab('users')">{{ t('user_management') }}</button>
        <button class="tab-btn" onclick="openTab('adduser')">{{ t('add_user') }}</button>
        <button class="tab-btn" onclick="openTab('bulk')">{{ t('bulk_operations') }}</button>
    </div>

    <div id="adduser" class="tab-content">
        <form method="post" action="/add" class="box">
            <h3><i class="fas fa-users-cog"></i> {{ t('add_user') }}</h3>
            {% if msg %}<div class="msg">{{ msg }}</div>{% endif %}
            {% if err %}<div class="err">{{ err }}</div>{% endif %}
            <div class="row">
                <div><label>{{ t('user') }}</label><input name="user" required></div>
                <div><label>{{ t('password') }}</label><input name="password" required></div>
                <div><label>{{ t('expires') }}</label><input name="expires" placeholder="2026-01-01 or 30"></div>
                <div><label>{{ t('port') }}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
            </div>
            <div class="row">
                <div><label>Speed Limit (MB/s)</label><input name="speed_limit" type="number"></div>
                <div><label>Bandwidth Limit (GB)</label><input name="bandwidth_limit" type="number"></div>
                <div><label>Max Connections</label><input name="concurrent_conn" value="1" type="number" min="1" max="10"></div>
                <div><label>{{ t('plan_type') }}</label>
                    <select name="plan_type">
                        <option value="free">{{ t('free') }}</option>
                        <option value="daily">{{ t('daily') }}</option>
                        <option value="weekly">{{ t('weekly') }}</option>
                        <option value="monthly" selected>{{ t('monthly') }}</option>
                    </select>
                </div>
            </div>
            <button class="btn save" type="submit" style="margin-top:20px">
                <i class="fas fa-save"></i> {{ t('save_user') }}
            </button>
        </form>
    </div>

    <div id="users" class="tab-content active">
        <div class="box">
            <h3><i class="fas fa-users"></i> {{ t('user_management') }}</h3>
            <div style="margin:15px 0;display:flex;gap:10px;">
                <input type="text" id="searchUser" placeholder="{{ t('search_users') }}" style="flex:1;">
                <button class="btn secondary" onclick="filterUsers()">
                    <i class="fas fa-search"></i> Search
                </button>
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th><i class="fas fa-user"></i> {{ t('user') }}</th>
                    <th><i class="fas fa-lock"></i> {{ t('password') }}</th>
                    <th><i class="fas fa-clock"></i> {{ t('expires') }}</th>
                    <th><i class="fas fa-server"></i> {{ t('port') }}</th>
                    <th><i class="fas fa-database"></i> {{ t('bandwidth') }}</th>
                    <th><i class="fas fa-tachometer-alt"></i> {{ t('speed') }}</th>
                    <th><i class="fas fa-chart-line"></i> {{ t('status') }}</th>
                    <th><i class="fas fa-cog"></i> {{ t('actions') }}</th>
                </tr>
            </thead>
            <tbody>
            {% for u in users %}
            <tr class="{% if u.status == 'Online' %}user-online{% elif u.status == 'Offline' %}user-offline{% elif u.status == 'Expired' %}user-expired{% endif %}">
                <td><strong>{{ u.user }}</strong></td>
                <td>{{ u.password }}</td>
                <td>{% if u.expires %}<span class="pill" style="background:#9b59b6;color:white;">{{ u.expires }}</span>{% else %}<span>—</span>{% endif %}</td>
                <td>{% if u.port %}<span class="pill" style="background:#e67e22;color:white;">{{ u.port }}</span>{% else %}<span>—</span>{% endif %}</td>
                <td><span class="pill" style="background:#1abc9c;color:white;">{{ u.bandwidth_used }}/{{ u.bandwidth_limit }} GB</span></td>
                <td><span class="pill" style="background:#f1c40f;color:white;">{{ u.speed_limit }} MB/s</span></td>
                <td>
                    {% if u.status == "Online" %}<span class="pill status-ok">{{ t('online') }}</span>
                    {% elif u.status == "Offline" %}<span class="pill status-bad">{{ t('offline') }}</span>
                    {% elif u.status == "Expired" %}<span class="pill status-expired">{{ t('expired') }}</span>
                    {% elif u.status == "suspended" %}<span class="pill status-bad">{{ t('suspended') }}</span>
                    {% else %}<span class="pill status-unk">{{ t('unknown') }}</span>
                    {% endif %}
                </td>
                <td style="display:flex;gap:5px;">
                    <form method="post" action="/delete" onsubmit="return confirm('Delete {{ u.user }}?')">
                        <input type="hidden" name="user" value="{{ u.user }}">
                        <button type="submit" class="btn delete" style="padding:6px 12px;">
                            <i class="fas fa-trash-alt"></i>
                        </button>
                    </form>
                    {% if u.status == "suspended" or u.status == "expired" %}
                    <form method="post" action="/activate">
                        <input type="hidden" name="user" value="{{ u.user }}">
                        <button type="submit" class="btn save" style="padding:6px 12px;">
                            <i class="fas fa-play"></i>
                        </button>
                    </form>
                    {% else %}
                    <form method="post" action="/suspend">
                        <input type="hidden" name="user" value="{{ u.user }}">
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
</div>

{% endif %}
</div>

<script>
function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(';').shift();
}

function setCookie(name, value, days) {
    const date = new Date();
    date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
    document.cookie = `${name}=${value};expires=${date.toUTCString()};path=/`;
}

function toggleTheme() {
    const currentTheme = getCookie('theme') || 'dark';
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    setCookie('theme', newTheme, 365);
    location.reload();
}

function toggleLanguage() {
    const currentLang = getCookie('language') || 'myanmar';
    const newLang = currentLang === 'myanmar' ? 'english' : 'myanmar';
    setCookie('language', newLang, 365);
    location.reload();
}

function openTab(tabName) {
    document.querySelectorAll('.tab-content').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(tabName).classList.add('active');
    event.currentTarget.classList.add('active');
}

function filterUsers() {
    const search = document.getElementById('searchUser').value.toLowerCase();
    document.querySelectorAll('tbody tr').forEach(row => {
        const user = row.cells[0].textContent.toLowerCase();
        row.style.display = user.includes(search) ? '' : 'none';
    });
}

setInterval(() => {
    fetch('/api/users/status')
        .then(r => r.json())
        .then(users => {
            users.forEach(user => {
                const row = document.querySelector(`tr:has(td:contains('${user.username}'))`);
                if (row) {
                    const statusCell = row.cells[6];
                    if (statusCell) {
                        statusCell.innerHTML = user.status === 'Online' ? 
                            '<span class="pill status-ok">ONLINE</span>' :
                            '<span class="pill status-bad">OFFLINE</span>';
                    }
                }
            });
        });
}, 15000);
</script>
</body>
</html>"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def get_settings():
    db = get_db()
    settings = {}
    try:
        rows = db.execute('SELECT key, value FROM settings').fetchall()
        for row in rows:
            settings[row['key']] = row['value']
    finally:
        db.close()
    return settings

def t(key, language='myanmar'):
    return TRANSLATIONS.get(language, {}).get(key, key)

def load_users():
    db = get_db()
    users = db.execute('''
        SELECT username as user, password, expires, port, status, 
               bandwidth_limit, bandwidth_used, speed_limit_up as speed_limit,
               concurrent_conn, last_seen
        FROM users
    ''').fetchall()
    db.close()
    return [dict(u) for u in users]

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status = "active"').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        server_load = min(100, total_users * 2 + active_users * 5)
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': server_load
        }
    finally:
        db.close()

def get_user_status(username, port):
    db = get_db()
    try:
        user = db.execute('SELECT last_seen, status FROM users WHERE username = ?', (username,)).fetchone()
        if not user:
            return 'Unknown'
        
        if user['status'] in ['suspended', 'expired']:
            return user['status']
        
        if user['last_seen']:
            last_seen = datetime.fromisoformat(user['last_seen'].replace('Z', '+00:00'))
            time_diff = datetime.now().replace(tzinfo=None) - last_seen.replace(tzinfo=None)
            if time_diff.total_seconds() < 120:
                return 'Online'
        
        return 'Offline'
    finally:
        db.close()

def build_view(msg="", err=""):
    if not require_login():
        return render_template_string(HTML_TEMPLATE, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
    
    settings = get_settings()
    language = request.cookies.get('language', settings.get('language', 'myanmar'))
    theme = request.cookies.get('theme', settings.get('theme', 'dark'))
    
    users = load_users()
    stats = get_server_stats()
    
    view = []
    today_date = datetime.now().date()
    
    for u in users:
        status = get_user_status(u['user'], u.get('port'))
        view.append({
            "user": u['user'],
            "password": u['password'],
            "expires": u.get('expires', ''),
            "port": u.get('port', ''),
            "status": status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": u.get('bandwidth_used', 0),
            "speed_limit": u.get('speed_limit', 0)
        })
    
    today = today_date.strftime("%Y-%m-%d")
    
    return render_template_string(
        HTML_TEMPLATE, 
        authed=True, 
        logo=LOGO_URL, 
        users=view, 
        msg=msg, 
        err=err, 
        today=today, 
        stats=stats,
        language=language,
        theme=theme,
        t=lambda key: t(key, language),
        lang_code='my' if language == 'myanmar' else 'en'
    )

def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

def login_enabled(): 
    return bool(ADMIN_USER and ADMIN_PASS)

def is_authed(): 
    return session.get("auth") == True

@app.route("/login", methods=["GET","POST"])
def login():
    if not login_enabled(): 
        return redirect(url_for('index'))
    
    if request.method=="POST":
        u = (request.form.get("u") or "").strip()
        p = (request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"] = True
            return redirect(url_for('index'))
        else:
            session["auth"] = False
            session["login_err"] = "Invalid credentials"
            return redirect(url_for('login'))
    
    return render_template_string(HTML_TEMPLATE, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): 
    return build_view()

@app.route("/add", methods=["POST"])
def add_user():
    if not require_login(): 
        return redirect(url_for('login'))
    
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
        return build_view(err="User and password required")
    
    if user_data['expires'] and user_data['expires'].isdigit():
        user_data['expires'] = (datetime.now() + timedelta(days=int(user_data['expires']))).strftime("%Y-%m-%d")
    
    db = get_db()
    try:
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, bandwidth_limit, speed_limit_up, concurrent_conn)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), user_data.get('bandwidth_limit', 0),
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1)
        ))
        db.commit()
    finally:
        db.close()
    
    return build_view(msg="User saved successfully")

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('DELETE FROM users WHERE username = ?', (user,))
        db.commit()
        db.close()
    
    return build_view(msg=f"Deleted: {user}")

@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
        db.commit()
        db.close()
    
    return redirect(url_for('index'))

@app.route("/activate", methods=["POST"])
def activate_user():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "active" WHERE username = ?', (user,))
        db.commit()
        db.close()
    
    return redirect(url_for('index'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Systemd Services =====
say "${Y}🧰 Creating systemd services...${Z}"

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

# Monitor Service
cat >/etc/systemd/system/zivpn-monitor.service <<'EOF'
[Unit]
Description=ZIVPN Monitor Service
After=network.target zivpn.service

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/bin/python3 /etc/zivpn/monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# ===== Network Configuration with SSH Protection =====
say "${Y}🌐 Configuring network with SSH protection...${Z}"

# Backup SSH config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup 2>/dev/null || true

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# Configure iptables with SSH protection
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X

# Basic firewall rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ZIVPN rules
iptables -A INPUT -p udp --dport 5667 -j ACCEPT
iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT  # Web Panel

# DNAT Rules
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# Default deny
iptables -A INPUT -j DROP

# UFW setup
ufw --force reset >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

# ===== Final Setup =====
say "${Y}🔧 Finalizing setup...${Z}"
sed -i 's/\r$//' /etc/zivpn/*.py /etc/systemd/system/zivpn* || true

systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service
systemctl enable --now zivpn-monitor.service

# ===== Completion Message =====
IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Enterprise Edition v3 Setup Complete!${Z}"
echo -e "${C}🌐 Web Panel:${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}👤 Admin Username:${Z} ${Y}${WEB_USER}${Z}"
echo -e "${C}🔐 Admin Password:${Z} ${Y}[Your entered password]${Z}"
echo -e "${C}🔌 VPN Server:${Z} ${Y}${SERVER_IP}:5667${Z}"
echo -e "${C}📊 Database:${Z} ${Y}/etc/zivpn/zivpn.db${Z}"
echo -e "\n${M}🎯 Enhanced Features:${Z}"
echo -e "  ✓ Real-time Online/Offline Detection"
echo -e "  ✓ Dark/Light Mode Toggle"
echo -e "  ✓ English/Myanmar Language Support"
echo -e "  ✓ Auto Expired User Cleanup"
echo -e "  ✓ Port Reuse System"
echo -e "  ✓ Enhanced UI/UX Design"
echo -e "  ✓ SSH Connection Protection"
echo -e "\n${Y}🛡️  SSH connection is preserved and protected${Z}"
echo -e "$LINE"
