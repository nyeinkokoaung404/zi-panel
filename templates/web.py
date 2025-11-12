#!/usr/bin/env python3
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response, g
import json, re, subprocess, os, tempfile, hmac, sqlite3, datetime
from datetime import datetime, timedelta
import statistics

# Configuration
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
        'report_users': 'User Activity', 'report_revenue': 'Revenue'
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
        'report_users': 'အသုံးပြုသူ လှုပ်ရှားမှု', 'report_revenue': 'ဝင်ငွေ'
    }
}
# --- End Localization Data ---

HTML = """<!doctype html>
<html lang="{{lang}}"><head><meta charset="utf-8">
<title>{{t.title}} - Channel 404</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
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
}
[data-theme='dark']{
    --bg: var(--bg-dark); --fg: var(--fg-dark); --card: var(--card-dark);
    --bd: var(--bd-dark); --primary-btn: var(--primary-dark); --input-text: var(--fg-dark);
}
[data-theme='light']{
    --bg: var(--bg-light); --fg: var(--fg-light); --card: var(--card-light);
    --bd: var(--bd-light); --primary-btn: var(--primary-light); --input-text: var(--fg-light);
}
html,body{background:var(--bg);color:var(--fg);font-family:'Padauk',sans-serif;line-height:1.6;margin:0;padding:0;transition:background 0.3s, color 0.3s;}
.container{max-width:1400px;margin:auto;padding:15px}
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

.btn{padding:10px 18px;border-radius:var(--radius);border:none;color:white;text-decoration:none;white-space:nowrap;cursor:pointer;transition:all 0.3s ease;font-weight:700;box-shadow:0 4px 6px rgba(0,0,0,0.3);display:inline-flex;align-items:center;gap:8px;}
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

.tab-container{margin:20px 0;}
.tabs{display:flex;gap:5px;margin-bottom:20px;border-bottom:2px solid var(--bd);}
.tab-btn{padding:12px 24px;background:var(--card);border:1px solid var(--bd);border-bottom:none;color:var(--fg);cursor:pointer;border-radius:var(--radius) var(--radius) 0 0;transition:all 0.3s ease;}
.tab-btn.active{background:var(--primary-btn);color:white;border-color:var(--primary-btn);}
.tab-content{display:none;padding-top:10px;}
.tab-content.active{display:block;}

.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:20px 0;}
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

@media (max-width: 768px) {
    body{padding:10px}.container{padding:0}
    header{flex-direction:column;align-items:flex-start;padding:10px;}
    .header-left{width:100%;justify-content:space-between;margin-bottom:10px;}
    .btn-group{flex-wrap:wrap;width:100%}
    .row>div,.stats-grid{grid-template-columns:1fr;}
    .btn{width:100%;margin-bottom:5px;justify-content:center}
    table,thead,tbody,th,td,tr{display:block;}
    thead tr{position:absolute;top:-9999px;left:-9999px;}
    tr{border:1px solid var(--bd);margin-bottom:10px;border-radius:var(--radius);overflow:hidden;background:var(--card);}
    td{border:none;border-bottom:1px dotted var(--bd);position:relative;padding-left:50%;text-align:right;}
    td:before{position:absolute;top:12px;left:10px;width:45%;padding-right:10px;white-space:nowrap;text-align:left;font-weight:700;color:var(--primary-btn);}
    td:nth-of-type(1):before{content:"{{t.user}}";}td:nth-of-type(2):before{content:"{{t.password}}";}
    td:nth-of-type(3):before{content:"{{t.expires}}";}td:nth-of-type(4):before{content:"{{t.port}}";}
    td:nth-of-type(5):before{content:"{{t.bandwidth}}";}td:nth-of-type(6):before{content:"{{t.speed}}";}
    td:nth-of-type(7):before{content:"{{t.max_conn}}";}td:nth-of-type(8):before{content:"{{t.status}}";}
    td:nth-of-type(9):before{content:"{{t.actions}}";}
    .delform{display:block;margin-top:5px;}
    td:nth-of-type(9){display:flex;flex-wrap:wrap;gap:5px;justify-content:flex-end;align-items:center;padding-top:10px;}
    tr.expired td{background:var(--expired);}
}
</style>
</head>
<body data-theme="{{theme}}">
<div class="container">

{% if not authed %}
    <div class="login-card">
        <div class="center" style="margin-bottom:20px"><img class="logo" src="{{ logo }}" alt="မောင်သုည"></div>
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

<div class="tab-container">
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
            <div class="row">
                <div><label><i class="fas fa-user icon"></i> {{t.user}}</label><input name="user" placeholder="{{t.user}}" required></div>
                <div><label><i class="fas fa-lock icon"></i> {{t.password}}</label><input name="password" placeholder="{{t.password}}" required></div>
                <div><label><i class="fas fa-clock icon"></i> {{t.expires}}</label><input name="expires" placeholder="2026-01-01 or 30 (days)"></div>
                <div><label><i class="fas fa-server icon"></i> {{t.port}}</label><input name="port" placeholder="auto" type="number" min="6000" max="19999"></div>
            </div>
            <div class="row">
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
            <div class="row">
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

        <table id="userTable">
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
                <td style="color:var(--ok);"><strong>{{u.user}}</strong></td>
                <td>{{u.password}}</td>
                <td>{% if u.expires %}<span class="pill-purple">{{u.expires}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                <td>{% if u.port %}<span class="pill-blue">{{u.port}}</span>{% else %}<span class="muted">—</span>{% endif %}</td>
                <td><span class="pill-green">{{u.bandwidth_used}}/{{u.bandwidth_limit}} GB</span></td>
                <td><span class="pill-yellow">{{u.speed_limit}} MB/s</span></td>
                <td><span class="pill-blue">{{u.concurrent_conn}}</span></td>
                <td>
                    {% if u.status == "Online" %}<span class="pill status-ok">{{t.online}}</span>
                    {% elif u.status == "Offline" %}<span class="pill status-bad">{{t.offline}}</span>
                    {% elif u.status == "Expired" %}<span class="pill status-expired">{{t.expired}}</span>
                    {% elif u.status == "suspended" %}<span class="pill status-bad">{{t.suspended}}</span>
                    {% else %}<span class="pill status-unk">{{t.unknown}}</span>
                    {% endif %}
                </td>
                <td>
                    <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{t.delete_confirm|replace("{user}", u.user)}}')">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button type="submit" class="btn delete" title="Delete" style="padding:6px 12px;"><i class="fas fa-trash-alt"></i></button>
                    </form>
                    <button class="btn secondary" title="Edit Password" style="padding:6px 12px;" onclick="editUser('{{u.user}}')"><i class="fas fa-edit"></i></button>
                    {% if u.status == "suspended" or u.status == "Expired" %}
                    <form class="delform" method="post" action="/activate">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button type="submit" class="btn save" title="Activate" style="padding:6px 12px;"><i class="fas fa-play"></i></button>
                    </form>
                    {% else %}
                    <form class="delform" method="post" action="/suspend">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button type="submit" class="btn delete" title="Suspend" style="padding:6px 12px;"><i class="fas fa-pause"></i></button>
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
            <h3 style="color:var(--success);"><i class="fas fa-chart-bar"></i> {{t.reports}}</h3>
            <div class="row">
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

{% endif %}
</div>

<script>
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
});

// --- Tabs ---
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

// --- User Filter ---
function filterUsers() {
    const search = document.getElementById('searchUser').value.toLowerCase();
    document.querySelectorAll('#userTable tbody tr').forEach(row => {
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
</script>
</body></html>"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")

# --- Utility Functions ---

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
        
        # Add to billing if plan type specified
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
        db.execute('DELETE FROM bandwidth_logs WHERE username = ?', (username,))
        db.commit()
    finally:
        db.close()

def get_server_stats():
    db = get_db()
    try:
        total_users = db.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        active_users_db = db.execute('SELECT COUNT(*) FROM users WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)').fetchone()[0]
        total_bandwidth = db.execute('SELECT SUM(bandwidth_used) FROM users').fetchone()[0] or 0
        
        server_load = min(100, (active_users_db * 5) + 10)
        
        return {
            'total_users': total_users,
            'active_users': active_users_db,
            'total_bandwidth': f"{total_bandwidth / 1024 / 1024 / 1024:.2f} GB",
            'server_load': server_load
        }
    finally:
        db.close()

def get_listen_port_from_config():
    cfg=read_json(CONFIG_FILE,{})
    listen=str(cfg.get("listen","")).strip()
    m=re.search(r":(\d+)$", listen) if listen else None
    return (m.group(1) if m else LISTEN_FALLBACK)

def has_recent_udp_activity(port):
    if not port: return False
    try:
        out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                           shell=True, capture_output=True, text=True).stdout
        return bool(out)
    except Exception:
        return False

def status_for_user(u, listen_port):
    port=str(u.get("port",""))
    check_port=port if port else listen_port

    if u.get('status') == 'suspended': return "suspended"

    expires_str = u.get("expires", "")
    is_expired = False
    if expires_str:
        try:
            expires_dt = datetime.strptime(expires_str, "%Y-%m-%d").date()
            if expires_dt < datetime.now().date():
                is_expired = True
        except ValueError:
            pass

    if is_expired: return "Expired"

    if has_recent_udp_activity(check_port): return "Online"
    
    return "Offline"

def sync_config_passwords(mode="mirror"):
    db = get_db()
    active_users = db.execute('''
        SELECT password FROM users 
        WHERE status = "active" AND password IS NOT NULL AND password != "" 
              AND (expires IS NULL OR expires >= CURRENT_DATE)
    ''').fetchall()
    db.close()
    
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
            return redirect(url_for('login'))
    
    theme = session.get('theme', 'dark')
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
                                  t=t, lang=g.lang, theme=theme)

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

def build_view(msg="", err=""):
    t = g.t
    if not require_login():
        return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
                                      t=t, lang=g.lang, theme=session.get('theme', 'dark'))
    
    users=load_users()
    listen_port=get_listen_port_from_config()
    stats = get_server_stats()
    
    view=[]
    today_date=datetime.now().date()
    
    for u in users:
        status = status_for_user(u, listen_port)
        expires_str=u.get("expires","")
        
        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":expires_str,
            "port":u.get("port",""),
            "status":status,
            "bandwidth_limit": u.get('bandwidth_limit', 0),
            "bandwidth_used": f"{u.get('bandwidth_used', 0) / 1024 / 1024 / 1024:.2f}",
            "speed_limit": u.get('speed_limit', 0),
            "concurrent_conn": u.get('concurrent_conn', 1)
        }))
    
    view.sort(key=lambda x:(x.user or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    theme = session.get('theme', 'dark')
    return render_template_string(HTML, authed=True, logo=LOGO_URL, 
                                 users=view, msg=msg, err=err, today=today, stats=stats, 
                                 t=t, lang=g.lang, theme=theme)

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
        'plan_type': (request.form.get("plan_type") or "").strip()
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

    save_user(user_data)
    sync_config_passwords()
    return build_view(msg=t['success_save'])

@app.route("/delete", methods=["POST"])
def delete_user_html():
    t = g.t
    if not require_login(): return redirect(url_for('login'))
    user = (request.form.get("user") or "").strip()
    if not user: return build_view(err=t['required_fields'])
    
    delete_user(user)
    sync_config_passwords(mode="mirror")
    return build_view(msg=t['deleted'].format(user=user))

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

# --- API Routes ---

@app.route("/api/bulk", methods=["POST"])
def bulk_operations():
    t = g.t
    if not require_login(): return jsonify({"ok": False, "err": t['login_err']}), 401
    
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
                delete_user(user)
        
        db.commit()
        sync_config_passwords()
        return jsonify({"ok": True, "message": t['bulk_success'].format(action=action)})
    finally:
        db.close()

@app.route("/api/export/users")
def export_users():
    if not require_login(): return "Unauthorized", 401
    
    users = load_users()
    csv_data = "User,Password,Expires,Port,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Max Connections,Status\n"
    for u in users:
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{u.get('bandwidth_used',0):.2f},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{u.get('concurrent_conn',1)},{u.get('status','')}\n"
    
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
            ''', (from_date or '2000-01-01', to_date or '2030-12-31')).fetchall()
        
        else:
            return jsonify({"message": "Invalid report type"}), 400

        return jsonify([dict(d) for d in data])
    finally:
        db.close()

@app.route("/api/user/update", methods=["POST"])
def update_user():
    t = g.t
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
        return jsonify({"ok": True, "message": "User password updated"})
    
    return jsonify({"ok": False, "err": "Invalid data"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
