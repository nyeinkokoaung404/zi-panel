#!/usr/bin/env python3

from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response, g
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import requests

# Configuration
# Constants are typically loaded from the environment or a separate config file
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# GitHub Template URL
HTML_TEMPLATE_URL = "https://raw.githubusercontent.com/nyeinkokoaung404/zi-panel/main/templates/index.html"

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
        'user_search': 'Search users (User/HWID)...', 'search': 'Search',
        'export_csv': 'Export Users CSV', 'import_users': 'Import Users',
        'bulk_success': 'Bulk action {action} completed',
        'report_range': 'Date Range Required', 'report_bw': 'Bandwidth Usage',
        'report_users': 'User Activity', 'report_revenue': 'Revenue',
        'home': 'Home', 'manage': 'Manage Users', 'settings': 'Settings',
        'dashboard': 'Dashboard', 'system_status': 'System Status',
        'quick_actions': 'Quick Actions', 'recent_activity': 'Recent Activity',
        'server_info': 'Server Information', 'vpn_status': 'VPN Status',
        'active_connections': 'Active Connections',
        'save_login': 'Save Login (14 Days)',
        'hwid': 'HWID (Hardware ID)',
        'cpu': 'CPU Load', 'ram': 'RAM Usage', 'swap': 'Swap Usage', 'disk': 'Disk Used',
        'vps_ip': 'VPS IP/Server IP', 'day_left': 'Days Left', 'expire_date': 'Expire Date',
        'alert_title': 'Notice', 'confirm_title': 'Confirmation', 'report_generating': 'Generating Report...'
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
        'user_search': 'အသုံးပြုသူ / HWID ရှာဖွေပါ...', 'search': 'ရှာဖွေပါ',
        'export_csv': 'အသုံးပြုသူများ CSV ထုတ်ယူမည်', 'import_users': 'အသုံးပြုသူများ ထည့်သွင်းမည်',
        'bulk_success': 'အစုလိုက် လုပ်ဆောင်ချက် {action} ပြီးမြောက်ပါပြီ',
        'report_range': 'ရက်စွဲ အပိုင်းအခြား လိုအပ်သည်', 'report_bw': 'Bandwidth အသုံးပြုမှု',
        'report_users': 'အသုံးပြုသူ လှုပ်ရှားမှု', 'report_revenue': 'ဝင်ငွေ',
        'home': 'ပင်မစာမျက်နှာ', 'manage': 'အသုံးပြုသူများ စီမံခန့်ခွဲမှု',
        'settings': 'ချိန်ညှိချက်များ', 'dashboard': 'ပင်မစာမျက်နှာ',
        'system_status': 'စနစ်အခြေအနေ', 'quick_actions': 'အမြန်လုပ်ဆောင်ချက်များ',
        'recent_activity': 'လတ်တလောလုပ်ဆောင်မှုများ', 'server_info': 'ဆာဗာအချက်အလက်',
        'vpn_status': 'VPN အခြေအနေ', 'active_connections': 'တက်ကြွလင့်ချိတ်ဆက်မှုများ',
        'save_login': 'လော့ဂ်အင် အချက်အလက် သိမ်းမည် (၁၄ ရက်)',
        'hwid': 'HWID (ဟာ့ဒ်ဝဲလ် အမှတ်အသား)',
        'cpu': 'CPU ဝန်ပမာဏ', 'ram': 'RAM အသုံးပြုမှု', 'swap': 'Swap အသုံးပြုမှု', 'disk': 'Disk အသုံးပြုမှု',
        'vps_ip': 'VPS IP/ဆာဗာ IP', 'day_left': 'ကျန်ရှိရက်', 'expire_date': 'သက်တမ်းကုန်ဆုံးရက်',
        'alert_title': 'သတိပေးချက်', 'confirm_title': 'အတည်ပြုချက်', 'report_generating': 'အစီရင်ခံစာ ထုတ်လုပ်နေသည်...'
    }
}


def load_html_template():
    """HTML Template ကို GitHub မှ ဒေါင်းလုပ်ဆွဲသည်။ ချိတ်ဆက်မှု မရပါက အမှားပြမည်။"""
    try:
        response = requests.get(f"{HTML_TEMPLATE_URL}?t={datetime.now().timestamp()}", timeout=10)
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
        return response.text
    except requests.exceptions.RequestException as e:
        print(f"ERROR: HTML template ကို GitHub မှ fetch လုပ်မရပါ: {e}")
        # Server ကို crash ခိုင်းလိုက်ပါသည်၊ အဘယ်ကြောင့်ဆိုသော် template သည် မဖြစ်မနေလိုအပ်ပါသည်။
        raise RuntimeError(f"Could not fetch HTML template from {HTML_TEMPLATE_URL}: {e}")

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")

# Permanent sessions (14 days)
app.permanent_session_lifetime = timedelta(days=14)

# --- Database Migration Function ---

def check_and_migrate_db(conn):
    """'users' table တွင် လိုအပ်သည့် 'hwid' column ရှိမရှိ စစ်ဆေးပြီး မရှိပါက ထည့်သွင်းသည်။"""
    cursor = conn.cursor()
    
    # Check for 'hwid' column
    cursor.execute("PRAGMA table_info(users)")
    columns = [row[1] for row in cursor.fetchall()]
    
    if 'hwid' not in columns:
        print("MIGRATION: 'hwid' column မတွေ့ပါ။ ယခု ထည့်သွင်းပါမည်။")
        try:
            # Add 'hwid' column with default empty string
            cursor.execute("ALTER TABLE users ADD COLUMN hwid TEXT DEFAULT ''")
            conn.commit()
            print("MIGRATION: 'hwid' column အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။")
        except sqlite3.OperationalError as e:
            print(f"MIGRATION ERROR: hwid column ထည့်သွင်းရာတွင် အမှား: {e}")

# --- Utility Functions (Refactored for g context) ---

def get_db():
    # Flask ရဲ့ 'g' context ကို သုံးပြီး request တစ်ခုအတွက် connection တစ်ခုသာ ဖွင့်သည်။
    if 'db' not in g:
        g.db = sqlite3.connect(DATABASE_PATH)
        g.db.row_factory = sqlite3.Row
        # DB Migration ကို Connection ဖွင့်တိုင်း စစ်ဆေးပေးသည်။
        check_and_migrate_db(g.db) 
    return g.db

@app.teardown_appcontext
def close_db(e=None):
    # Request ပြီးဆုံးတိုင်း Connection ကို ပိတ်သည်။ (Error ဖြစ်သည်ဖြစ်စေ၊ မဖြစ်သည်ဖြစ်စေ)
    db = g.pop('db', None)
    if db is not None:
        db.close()

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
               concurrent_conn, hwid
        FROM users
    ''').fetchall()
    return [dict(u) for u in users]

def save_user(user_data):
    db = get_db()
    try:
        db.execute('''
            INSERT OR REPLACE INTO users 
            (username, password, expires, port, status, bandwidth_limit, speed_limit_up, concurrent_conn, hwid)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            user_data['user'], user_data['password'], user_data.get('expires'),
            user_data.get('port'), 'active', user_data.get('bandwidth_limit', 0),
            user_data.get('speed_limit', 0), user_data.get('concurrent_conn', 1),
            user_data.get('hwid', '')
        ))
        
        if user_data.get('plan_type'):
            expires = user_data.get('expires') or (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
            # created_at column ကို ထည့်သွင်းရန် ယူဆထားသည်။
            db.execute('''
                INSERT INTO billing (username, plan_type, expires_at, created_at)
                VALUES (?, ?, ?, ?)
            ''', (user_data['user'], user_data['plan_type'], expires, datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
            
        db.commit()
    except Exception as e:
        print(f"Database error during save_user: {e}")
        raise e

def delete_user(username):
    db = get_db()
    try:
        db.execute('DELETE FROM users WHERE username = ?', (username,))
        db.execute('DELETE FROM billing WHERE username = ?', (username,))
        db.execute('DELETE FROM bandwidth_logs WHERE username = ?', (username,))
        db.commit()
    except Exception as e:
        print(f"Database error during delete_user: {e}")
        raise e

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        # Active users: status is 'active' AND (expires is NULL OR expires >= today)
        active_users_db = db.execute('SELECT COUNT(*) FROM users WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        # Server Load သည် Active Users ပေါ် မူတည်၍ ခန့်မှန်းထားသည်။
        server_load = min(100, (active_users_db * 5) + 10)
        
        return {
            'total_users': total_users,
            'active_users': active_users_db,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': server_load
        }
    except Exception as e:
        print(f"Database error in get_server_stats: {e}")
        return {
            'total_users': 0, 'active_users': 0, 'total_bandwidth': "N/A", 'server_load': 0
        }


def get_system_stats():
    """VPS ၏ CPU, RAM, Swap, Disk အချက်အလက်များကို ရယူသည်။"""
    stats = {}
    
    # 1. CPU Load (1-minute average from /proc/loadavg)
    try:
        # shell=False ဖြင့် ပိုမို လုံခြုံသည်။
        load_avg = subprocess.run(["cat", "/proc/loadavg"], capture_output=True, text=True, timeout=1).stdout.split()[0]
        stats['cpu_load'] = f"{float(load_avg):.2f}"
        # Dummy value for progress bar if actual CPU % is hard to get
        stats['cpu_percent'] = min(100.0, float(load_avg) * 10) 
    except Exception:
        stats['cpu_load'] = "N/A"
        stats['cpu_percent'] = 0

    # 2. RAM Usage
    try:
        # shell=True ကို အသုံးပြုပြီး piping ကို ခွင့်ပြုသည်။ (VPS 環境တွင် မလွဲမရှောင်သာပါ)
        mem_info = subprocess.run("free -m | awk 'NR==2{print $2,$3}'", shell=True, capture_output=True, text=True, timeout=1).stdout.split()
        total_m = int(mem_info[0])
        used_m = int(mem_info[1])
        ram_percent = round((used_m / total_m) * 100, 1) if total_m > 0 else 0
        stats['ram_used'] = f"{used_m}M / {total_m}M"
        stats['ram_percent'] = ram_percent
    except Exception:
        stats['ram_used'] = "N/A"
        stats['ram_percent'] = 0

    # 3. Swap Usage
    try:
        swap_info = subprocess.run("free -m | awk 'NR==3{print $2,$3}'", shell=True, capture_output=True, text=True, timeout=1).stdout.split()
        total_m = int(swap_info[0])
        used_m = int(swap_info[1])
        swap_percent = round((used_m / total_m) * 100, 1) if total_m > 0 else 0
        stats['swap_used'] = f"{used_m}M / {total_m}M" if total_m > 0 else "0M / 0M"
        stats['swap_percent'] = swap_percent
    except Exception:
        stats['swap_used'] = "N/A"
        stats['swap_percent'] = 0

    # 4. Disk Usage (Root partition /)
    try:
        # percent ကို ရယူရန် awk ကို သုံးသည်။
        disk_info = subprocess.run("df -h / | awk 'NR==2{print $2,$3,$5}'", shell=True, capture_output=True, text=True, timeout=1).stdout.split()
        total_g = disk_info[0]
        used_g = disk_info[1]
        percent_str = disk_info[2].replace('%', '')
        disk_percent = float(percent_str)
        stats['disk_used'] = f"{used_g} / {total_g}"
        stats['disk_percent'] = disk_percent
    except Exception:
        stats['disk_used'] = "N/A"
        stats['disk_percent'] = 0
        
    return stats


def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

def has_recent_udp_activity(port):
    """ပိုမိုတိကျသော UDP activity စစ်ဆေးခြင်း"""
    if not port:  
        return False
        
    try:
        # More accurate conntrack check with timeout
        command = [
            'timeout', '5', 
            'conntrack', '-L', '-p', 'udp', 
            '--dport', str(port),
            '--state', 'ESTABLISHED'
        ]
        
        result = subprocess.run(
            command, 
            capture_output=True, 
            text=True,
            timeout=10
        )
        
        # Count established connections for this port
        lines = [line for line in result.stdout.split('\n') if 'ESTABLISHED' in line and f'dport={port}' in line]
        return len(lines) > 0

    except subprocess.TimeoutExpired:
        print(f"Timeout checking port {port}")
        return False
    except Exception as e:
        print(f"Error checking conntrack for port {port}: {e}")
        return False

def status_for_user(u, listen_port):
    """အသုံးပြုသူ၏ အခြေအနေ ကို ပိုမိုတိကျစွာ တွက်ချက်သည်"""
    port = str(u.get("port", ""))
    check_port = port if port else listen_port

    # First check if user is suspended
    if u.get('status') == 'suspended': 
        return "Suspended"

    # Check expiry
    expires_str = u.get("expires", "")
    is_expired = False
    if expires_str:
        try:
            expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < datetime.now().date():
                is_expired = True
        except ValueError:
            pass

    if is_expired: 
        return "Expired"

    # Check online status with improved accuracy
    is_online = has_recent_udp_activity(check_port)
    
    return "Online" if is_online else "Offline"

def sync_config_passwords(mode="mirror"):
    """Active User များ၏ Password များကို ZIVPN config file ထဲသို့ ထည့်သွင်းပြီး service ကို restart လုပ်သည်။"""
    db = get_db()
    active_users = db.execute('''
        SELECT password FROM users 
        WHERE status = "active" AND password IS NOT NULL AND password != "" 
             AND (expires IS NULL OR expires >= CURRENT_DATE)
    ''').fetchall()
    
    users_pw = sorted({str(u["password"]) for u in active_users})
    
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

# --- Request Hooks ---
@app.before_request
def set_language_and_translations():
    lang = session.get('lang', os.environ.get('DEFAULT_LANGUAGE', 'my'))
    g.lang = lang
    g.t = TRANSLATIONS.get(lang, TRANSLATIONS['my'])

# --- Routes ---

@app.route("/set_lang", methods=["GET"])
def set_lang():
    lang = request.args.get('lang')
    if lang in TRANSLATIONS:
        session['lang'] = lang
    return redirect(request.referrer or url_for('index'))

@app.route("/login", methods=["GET","POST"])
def login():
    t = g.t
    # Template ကို အပြင်မှ တစ်ခါတည်း fetch လုပ်သည်။
    html_template = load_html_template() 
    if not login_enabled(): return redirect(url_for('index'))
    
    # NEW: Serialize translations dictionary to a JSON string for safe embedding in JS
    translations_json = json.dumps(t, ensure_ascii=False)
    
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        
        # 'Save Login' checkbox ကို စစ်ဆေးပြီး session သက်တမ်းကို သတ်မှတ်သည်။
        remember_me = request.form.get("remember_me") == "on"
        session.permanent = remember_me
        
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('index'))
        else:
            session["auth"]=False
            session["login_err"]=t['login_err']
            return redirect(url_for('login'))
    
    theme = session.get('theme', 'dark')
    return render_template_string(html_template, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
                                 t=t, lang=g.lang, theme=theme,
                                 translations_json_str=translations_json) # Pass to login view too

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

def build_view(msg="", err=""):
    t = g.t
    # Template ကို အပြင်မှ load လုပ်သည်။
    try:
        html_template = load_html_template() 
    except RuntimeError as e:
        # Template load မရပါက အမှား message ပြသသည်။
        return f"<h1>Error: Cannot load Web Panel Template</h1><p>{e}</p>", 500
    
    # NEW: Serialize translations dictionary to a JSON string for safe embedding in JS
    translations_json = json.dumps(t, ensure_ascii=False)
    
    if not require_login():
        return render_template_string(html_template, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
                                     t=t, lang=g.lang, theme=session.get('theme', 'dark'),
                                     translations_json_str=translations_json)
    
    # ဤနေရာမှ စတင်၍ Database မှ data များ ဆွဲယူသည်။
    try:
        users=load_users()
        listen_port=get_listen_port_from_config()
        stats = get_server_stats()
        system_stats = get_system_stats() # System Stats အသစ်ကို ခေါ်သည်။
    except Exception as e:
        # Database/System Error ဖြစ်ပါက Internal Server Error အစား message ပြသနိုင်သည်။
        return f"<h1>Error: Database or System Access Failed</h1><p>Please check if the ZIVPN services are running and if system commands are accessible. Detail: {e}</p>", 500

    view=[]
    today_date=datetime.now().date()
    
    for u in users:
        status = status_for_user(u, listen_port)
        expires_str=u.get("expires","")
        days_left_class = "value-status-unknown"
        days_left_text = "N/A"
        
        if expires_str:
            try:
                expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
                delta = expires_dt - today_date
                days_left = delta.days
                days_left_text = f"{days_left} {t['day_left']}"
                
                if days_left < 0:
                    days_left_class = "value-status-bad" # Expired (Red)
                    days_left_text = t['expired']
                elif days_left <= 7:
                    days_left_class = "value-status-expired" # Warning (Purple/Red tone)
                elif days_left <= 30:
                    days_left_class = "value-status-unknown" # Warning (Yellow tone)
                else:
                    days_left_class = "value-status-ok" # OK (Green)
            except ValueError:
                days_left_class = "value-status-unknown"
                days_left_text = "Invalid Date"


        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":expires_str,
            "port":u.get("port",""),
            "status":status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": f"{u.get('bandwidth_used', 0) / 1024 / 1024 / 1024:.2f} GB",
            "speed_limit": u.get('speed_limit', 0),
            "concurrent_conn": u.get('concurrent_conn', 1),
            "hwid": u.get('hwid', ''),
            "server_ip": request.host.split(':')[0], # Host IP ကို ရယူပါသည်။
            "days_left": days_left_text,
            "days_left_class": days_left_class
        }))
    
    view.sort(key=lambda x:(x.user or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    # System Stats အတွက် percentage value များကို သေချာအောင် စစ်ဆေးသည်။
    system_stats_final = {
        'cpu_load': system_stats.get('cpu_load', 'N/A'),
        'cpu_percent': system_stats.get('cpu_percent', 0),
        'ram_used': system_stats.get('ram_used', 'N/A'),
        'ram_percent': system_stats.get('ram_percent', 0),
        'swap_used': system_stats.get('swap_used', 'N/A'),
        'swap_percent': system_stats.get('swap_percent', 0),
        'disk_used': system_stats.get('disk_used', 'N/A'),
        'disk_percent': system_stats.get('disk_percent', 0),
    }

    theme = session.get('theme', 'dark')
    return render_template_string(html_template, authed=True, logo=LOGO_URL, 
                                 users=view, msg=msg, err=err, today=today, stats=stats, 
                                 system_stats=system_stats_final, 
                                 t=t, lang=g.lang, theme=theme,
                                 translations_json_str=translations_json) # Pass to main view

@app.route("/", methods=["GET"])
def index(): 
    return build_view()

@app.route("/add", methods=["POST"])
def add_user():
    t = g.t
    if not require_login(): return redirect(url_for('login'))
    
    user_data = {
        'user': (request.form.get("user") or "").strip(),
        'password': (request.form.get("password") or "").strip(),
        'expires': (request.form.get("expires") or "").strip(),
        'port': (request.form.get("port") or "").strip(),
        'bandwidth_limit': int(request.form.get("bandwidth_limit") or 0),
        'speed_limit': int(request.form.get("speed_limit") or 0),
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1),
        'plan_type': (request.form.get("plan_type") or "").strip(),
        'hwid': (request.form.get("hwid") or "").strip()
    }
    
    if not user_data['user'] or not user_data['password']:
        return build_view(err=t['required_fields'])
    
    if user_data['expires'] and user_data['expires'].isdigit():
        try:
            days = int(user_data['expires'])
            user_data['expires'] = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
        except ValueError:
            return build_view(err=t['invalid_exp'])
    
    if user_data['expires']:
        try: datetime.strptime(user_data['expires'],"%Y-%m-%d")
        except ValueError:
            return build_view(err=t['invalid_exp'])
    
    if user_data['port']:
        try:
            port_num = int(user_data['port'])
            if not (6000 <= port_num <= 19999):
                     return build_view(err=t['invalid_port'])
        except ValueError:
             return build_view(err=t['invalid_port'])

    
    if not user_data['port']:
        used_ports = {str(u.get('port', '')) for u in load_users() if u.get('port')}
        found_port = None
        for p in range(6000, 20000):
            if str(p) not in used_ports:
                found_port = str(p)
                break
        user_data['port'] = found_port or ""

    try:
        save_user(user_data)
        sync_config_passwords()
        return build_view(msg=t['success_save'])
    except Exception as e:
        return build_view(err=f"Error saving user: {e}")

@app.route("/delete", methods=["POST"])
def delete_user_html():
    t = g.t
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=t['required_fields'])
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=t['deleted'].format(user=user))

# /suspend, /activate ကိုလည်း API သို့ ပြောင်းလဲခြင်း မပြုပါ။
@app.route("/suspend", methods=["POST"])
def suspend_user():
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        db = get_db()
        db.execute('UPDATE users SET status = "suspended" WHERE username = ?', (user,))
        db.commit()
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
        sync_config_passwords()
    return redirect(url_for('index'))

# --- API Routes ---

@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    t = g.t
    if not require_login(): return jsonify({"ok": False, "message": t['login_err']}), 401
    
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
                # bulk delete သည် delete_user() ကို အသုံးမပြုနိုင်ပါ။ ဤနေရာတွင် db object ကိုသာ သုံးမည်။
                db.execute('DELETE FROM users WHERE username = ?', (user,))
                db.execute('DELETE FROM billing WHERE username = ?', (user,))
                db.execute('DELETE FROM bandwidth_logs WHERE username = ?', (user,))
        
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": t['bulk_success'].format(action=action)})
    except Exception as e:
        return jsonify({"ok": False, "message": f"Database update failed for action {action}: {e}"}), 500


@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,HWID,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Max Connections,Status\n"
    for u in users:
        # u.get('bandwidth_used',0) သည် string ဖြစ်နေသဖြင့် ပြန်ပြောင်းရန် လိုအပ်သည်။
        bw_used_str = u.get('bandwidth_used', "0.00 GB").replace(" GB", "")
        bw_used = float(bw_used_str) if bw_used_str.replace('.', '', 1).isdigit() else 0.00
        
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{u.get('hwid','')},{bw_used:.2f},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{u.get('concurrent_conn',1)},{u.get('status','')}\n"
    
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
        # ... (reporting queries are simplified and kept as is, as they look plausible) ...
        if report_type == 'bandwidth':
            data = db.execute('''
                SELECT username, SUM(bytes_used) / 1024 / 1024 / 1024 as total_gb_used 
                FROM bandwidth_logs 
                WHERE log_date BETWEEN ? AND ?
                GROUP BY username
                ORDER BY total_gb_used DESC
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        
        elif report_type == 'users':
            data = db.execute('''
                SELECT strftime('%Y-%m-%d', created_at) as date, COUNT(*) as new_users
                FROM users 
                WHERE created_at BETWEEN ? AND datetime(?, '+1 day')
                GROUP BY date
                ORDER BY date ASC
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()

        elif report_type == 'revenue':
            data = db.execute('''
                SELECT plan_type, currency, SUM(amount) as total_revenue
                FROM billing
                WHERE created_at BETWEEN ? AND datetime(?, '+1 day')
                GROUP BY plan_type, currency
                ORDER BY created_at ASC
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        
        else:
            return jsonify({"message": "Invalid report type"}), 400

        return jsonify([dict(d) for d in data])
    except Exception as e:
        return jsonify({"error": f"Report generation failed: {e}"}), 500

@app.route("/api/user/update", methods=["POST"])
def update_user():
    t = g.t
    if not require_login(): return jsonify({"ok": False, "message": t['login_err']}), 401
    
    data = request.get_json() or {}
    user = data.get('user')
    password = data.get('password')
    hwid = data.get('hwid')

    if user:
        db = get_db()
        try:
            # အသုံးပြုသူ ရှိ/မရှိ စစ်ဆေးခြင်း
            exists = db.execute('SELECT 1 FROM users WHERE username = ?', (user,)).fetchone()
            if not exists:
                 return jsonify({"ok": False, "message": f"User '{user}' not found."}), 404

            update_fields = []
            params = []
            
            if password is not None:
                update_fields.append("password = ?")
                params.append(password)
            
            if hwid is not None:
                # HWID သည် မပါရှိပါက Empty String အဖြစ် သိမ်းမည်။
                update_fields.append("hwid = ?")
                params.append(hwid or '') 
                
            if not update_fields:
                return jsonify({"ok": False, "message": "No fields to update"}), 400

            query = f'UPDATE users SET {", ".join(update_fields)} WHERE username = ?'
            params.append(user)
            
            db.execute(query, tuple(params))
            db.commit()
            sync_config_passwords()
            return jsonify({"ok": True, "message": "User credentials updated successfully."})
        except Exception as e:
            print(f"Database error during user update: {e}")
            return jsonify({"ok": False, "message": "Database update failed. See server logs."}), 500
    
    return jsonify({"ok": False, "message": "Invalid data received."}), 400

@app.route("/api/user/delete", methods=["POST"])
def api_delete_user():
    t = g.t
    if not require_login(): return jsonify({"ok": False, "message": t['login_err']}), 401
    
    data = request.get_json() or {}
    user = data.get('user')
    
    if not user:
        return jsonify({"ok": False, "message": "Username is required."}), 400
        
    try:
        delete_user(user) # Refactored delete_user function ကို သုံးပါသည်။
        sync_config_passwords()
        return jsonify({"ok": True, "message": t['deleted'].format(user=user)})
    except Exception as e:
        return jsonify({"ok": False, "message": f"Error deleting user: {e}"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
