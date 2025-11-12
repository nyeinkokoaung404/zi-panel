#!/usr/bin/env python3
"""
ZIVPN Enterprise Web Panel - GitHub Version
Downloaded from: https://github.com/nyeinkokoaung404/zi-panel/main/templates/web.py
"""

from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response, g
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics
import requests

# Configuration
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://raw.githubusercontent.com/BaeGyee9/khaing/main/logo.png"

# Localization
TRANSLATIONS = {
    'en': {
        'title': 'ZIVPN Enterprise Panel', 'login_title': 'ZIVPN Panel Login',
        'login_err': 'Invalid Username or Password', 'username': 'Username',
        'password': 'Password', 'login': 'Login', 'logout': 'Logout',
        'total_users': 'Total Users', 'active_users': 'Online Users',
        'bandwidth_used': 'Bandwidth Used', 'server_load': 'Server Load',
        'user_management': 'User Management', 'add_user': 'Add New User',
        'user': 'User', 'expires': 'Expires', 'port': 'Port',
        'status': 'Status', 'actions': 'Actions', 'online': 'ONLINE',
        'offline': 'OFFLINE', 'expired': 'EXPIRED', 'save_user': 'Save User',
        'max_conn': 'Max Connections', 'speed_limit': 'Speed Limit (MB/s)',
        'bw_limit': 'Bandwidth Limit (GB)', 'dashboard': 'Dashboard'
    },
    'my': {
        'title': 'ZIVPN စီမံခန့်ခွဲမှု Panel', 'login_title': 'ZIVPN Panel ဝင်ရန်',
        'login_err': 'အသုံးပြုသူအမည် (သို့) စကားဝှက် မမှန်ပါ', 'username': 'အသုံးပြုသူအမည်',
        'password': 'စကားဝှက်', 'login': 'ဝင်မည်', 'logout': 'ထွက်မည်',
        'total_users': 'စုစုပေါင်းအသုံးပြုသူ', 'active_users': 'အွန်လိုင်းအသုံးပြုသူ',
        'bandwidth_used': 'အသုံးပြုပြီး Bandwidth', 'server_load': 'ဆာဗာ ဝန်ပမာဏ',
        'user_management': 'အသုံးပြုသူ စီမံခန့်ခွဲမှု', 'add_user': 'အသုံးပြုသူ အသစ်ထည့်ရန်',
        'user': 'အသုံးပြုသူ', 'expires': 'သက်တမ်းကုန်ဆုံးမည်', 'port': 'ပေါက်',
        'status': 'အခြေအနေ', 'actions': 'လုပ်ဆောင်ချက်များ', 'online': 'အွန်လိုင်း',
        'offline': 'အော့ဖ်လိုင်း', 'expired': 'သက်တမ်းကုန်ဆုံး', 'save_user': 'အသုံးပြုသူ သိမ်းမည်',
        'max_conn': 'အများဆုံးချိတ်ဆက်မှု', 'speed_limit': 'မြန်နှုန်း ကန့်သတ်ချက် (MB/s)',
        'bw_limit': 'Bandwidth ကန့်သတ်ချက် (GB)', 'dashboard': 'ပင်မစာမျက်နှာ'
    }
}

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER", "").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD", "").strip()

def get_db():
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

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
    finally:
        db.close()

def delete_user(username):
    db = get_db()
    try:
        db.execute('DELETE FROM users WHERE username = ?', (username,))
        db.commit()
    finally:
        db.close()

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        active_users = db.execute('SELECT COUNT(*) FROM users WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        server_load = min(100, (active_users * 5) + 10)
        
        return {
            'total_users': total_users,
            'active_users': active_users,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': server_load
        }
    finally:
        db.close()

def sync_config_passwords():
    db = get_db()
    active_users = db.execute('''
        SELECT password FROM users 
        WHERE status = "active" AND password IS NOT NULL AND password != "" 
              AND (expires IS NULL OR expires >= CURRENT_DATE)
    ''').fetchall()
    db.close()
    
    users_pw = sorted({str(u["password"]) for u in active_users})
    
    cfg = read_json(CONFIG_FILE, {})
    if not isinstance(cfg.get("auth"), dict): cfg["auth"] = {}
    cfg["auth"]["mode"] = "passwords"
    cfg["auth"]["config"] = users_pw
    cfg["listen"] = cfg.get("listen") or ":5667"
    cfg["cert"] = cfg.get("cert") or "/etc/zivpn/zivpn.crt"
    cfg["key"] = cfg.get("key") or "/etc/zivpn/zivpn.key"
    cfg["obfs"] = cfg.get("obfs") or "zivpn"
    
    write_json_atomic(CONFIG_FILE, cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True)

def read_json(path, default):
    try:
        with open(path, "r") as f: return json.load(f)
    except Exception:
        return default

def write_json_atomic(path, data):
    d = json.dumps(data, ensure_ascii=False, indent=2)
    dirn = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=dirn)
    try:
        with os.fdopen(fd, "w") as f: f.write(d)
        os.replace(tmp, path)
    finally:
        try: os.remove(tmp)
        except: pass

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True

@app.before_request
def set_language_and_translations():
    lang = session.get('lang', os.environ.get('DEFAULT_LANGUAGE', 'my'))
    g.lang = lang
    g.t = TRANSLATIONS.get(lang, TRANSLATIONS['my'])

@app.route("/set_lang", methods=["GET"])
def set_lang():
    lang = request.args.get('lang')
    if lang in TRANSLATIONS:
        session['lang'] = lang
    return redirect(request.referrer or url_for('index'))

@app.route("/login", methods=["GET", "POST"])
def login():
    t = g.t
    if not login_enabled(): return redirect(url_for('index'))
    if request.method == "POST":
        u = (request.form.get("u") or "").strip()
        p = (request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"] = True
            return redirect(url_for('index'))
        else:
            session["auth"] = False
            session["login_err"] = t['login_err']
            return redirect(url_for('login'))
    
    return render_template_string(HTML, authed=False, logo=LOGO_URL, 
                                 err=session.pop("login_err", None), 
                                 t=t, lang=g.lang, theme='dark')

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index():
    if not is_authed() and login_enabled():
        return redirect(url_for('login'))
    
    users = load_users()
    stats = get_server_stats()
    today = datetime.now().date().strftime("%Y-%m-%d")
    
    return render_template_string(HTML, authed=True, logo=LOGO_URL,
                                 users=users, stats=stats, today=today,
                                 t=g.t, lang=g.lang, theme='dark')

@app.route("/add", methods=["POST"])
def add_user():
    t = g.t
    if not is_authed() and login_enabled(): return redirect(url_for('login'))
    
    user_data = {
        'user': (request.form.get("user") or "").strip(),
        'password': (request.form.get("password") or "").strip(),
        'expires': (request.form.get("expires") or "").strip(),
        'port': (request.form.get("port") or "").strip(),
        'bandwidth_limit': int(request.form.get("bandwidth_limit") or 0),
        'speed_limit': int(request.form.get("speed_limit") or 0),
        'concurrent_conn': int(request.form.get("concurrent_conn") or 1)
    }
    
    if not user_data['user'] or not user_data['password']:
        return redirect(url_for('index'))
    
    if user_data['expires'] and user_data['expires'].isdigit():
        try:
            days = int(user_data['expires'])
            user_data['expires'] = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
        except ValueError:
            pass
    
    save_user(user_data)
    sync_config_passwords()
    return redirect(url_for('index'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not is_authed() and login_enabled(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if user:
        delete_user(user)
        sync_config_passwords()
    return redirect(url_for('index'))

# HTML Template would be here in the actual file
HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>{{t.title}}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 20px 0; }
        .stat-card { background: #ecf0f1; padding: 15px; border-radius: 5px; text-align: center; }
    </style>
</head>
<body>
    {% if not authed %}
    <div class="login-form">
        <h2>{{t.login_title}}</h2>
        {% if err %}<div style="color: red;">{{err}}</div>{% endif %}
        <form method="post">
            <input type="text" name="u" placeholder="{{t.username}}" required>
            <input type="password" name="p" placeholder="{{t.password}}" required>
            <button type="submit">{{t.login}}</button>
        </form>
    </div>
    {% else %}
    <div class="header">
        <h1>{{t.title}}</h1>
        <a href="/logout">{{t.logout}}</a>
    </div>
    
    <div class="stats">
        <div class="stat-card">
            <h3>{{t.total_users}}</h3>
            <div class="stat-number">{{ stats.total_users }}</div>
        </div>
        <div class="stat-card">
            <h3>{{t.active_users}}</h3>
            <div class="stat-number">{{ stats.active_users }}</div>
        </div>
    </div>
    
    <div class="user-management">
        <h2>{{t.user_management}}</h2>
        <table border="1" style="width: 100%;">
            <tr>
                <th>{{t.user}}</th>
                <th>{{t.password}}</th>
                <th>{{t.expires}}</th>
                <th>{{t.port}}</th>
                <th>{{t.status}}</th>
                <th>{{t.actions}}</th>
            </tr>
            {% for u in users %}
            <tr>
                <td>{{ u.user }}</td>
                <td>{{ u.password }}</td>
                <td>{{ u.expires or '-' }}</td>
                <td>{{ u.port or '-' }}</td>
                <td>{{ u.status }}</td>
                <td>
                    <form method="post" action="/delete" style="display: inline;">
                        <input type="hidden" name="user" value="{{ u.user }}">
                        <button type="submit">Delete</button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </table>
    </div>
    
    <div class="add-user">
        <h2>{{t.add_user}}</h2>
        <form method="post" action="/add">
            <input type="text" name="user" placeholder="{{t.user}}" required>
            <input type="text" name="password" placeholder="{{t.password}}" required>
            <input type="text" name="expires" placeholder="2024-12-31">
            <input type="number" name="port" placeholder="Port" min="6000" max="19999">
            <button type="submit">{{t.save_user}}</button>
        </form>
    </div>
    {% endif %}
</body>
</html>
"""

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
