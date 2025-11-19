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
        'hwid': 'HWID (Hardware ID)'
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
        'hwid': 'HWID (ဟာ့ဒ်ဝဲလ် အမှတ်အသား)'
    }
}

def load_html_template():
    """Load HTML template from GitHub or fallback to local template"""
    try:
        response = requests.get(HTML_TEMPLATE_URL, timeout=10)
        if response.status_code == 200:
            return response.text
        else:
            raise Exception(f"HTTP {response.status_code}")
    except Exception as e:
        print(f"Failed to load template from GitHub: {e}")
        # Fallback to local template
        return FALLBACK_HTML

# Fallback HTML template in case GitHub is unavailable
FALLBACK_HTML = """
<!DOCTYPE html>
<html lang="{{lang}}">
<head>
    <meta charset="utf-8">
    <title>{{t.title}} - Channel 404</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="refresh" content="120">
    <link href="https://fonts.googleapis.com/css2?family=Padauk:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
    <style>
:root{
    --bg-dark: #0f172a; --fg-dark: #f1f5f9; --card-dark: #1e293b; --bd-dark: #334155; --primary-dark: #3b82f6;
    --bg-light: #f8fafc; --fg-light: #1e293b; --card-light: #ffffff; --bd-light: #e2e8f0; --primary-light: #2563eb;
    --ok: #10b981; --bad: #ef4444; --unknown: #f59e0b; --expired: #8b5cf6;
    --success: #06d6a0; --delete-btn: #ef4444; --logout-btn: #f97316;
    --shadow: 0 10px 25px -5px rgba(0,0,0,0.3), 0 8px 10px -6px rgba(0,0,0,0.2);
    --radius: 16px; --gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
    line-height:1.6;margin:0;padding:0;transition:all 0.3s ease;
    min-height: 100vh;
}
.container{
    max-width:1400px;margin:auto;padding:20px;padding-bottom: 80px;
}

/* Modern Header */
.header {
    background: var(--gradient);
    padding: 20px;
    margin-bottom: 20px;
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    text-align: center;
    position: relative;
    overflow: hidden;
    display: flex; /* Added for alignment */
    justify-content: space-between; /* Added for alignment */
    align-items: center; /* Added for alignment */
}

.header::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: linear-gradient(45deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.05) 100%);
    pointer-events: none;
}

.header-content {
    position: relative;
    z-index: 2;
    flex-grow: 1; /* Allows content to take necessary space */
}

.logo-container {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 15px;
    margin-bottom: 10px;
}

.logo {
    height: 50px;
    width: 50px;
    border-radius: 50%;
    border: 2px solid rgba(255,255,255,0.9);
    background: white;
    padding: 3px;
}

.header h1 {
    margin: 0;
    font-size: 1.8em;
    font-weight: 900;
    color: white;
    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
}

.header .subtitle {
    color: rgba(255,255,255,0.9);
    font-size: 0.9em;
    margin-top: 5px;
}

/* NEW: Settings Button in Header */
.settings-btn-header {
    background: rgba(255, 255, 255, 0.2);
    color: white;
    border: none;
    border-radius: 50%;
    width: 40px;
    height: 40px;
    cursor: pointer;
    transition: background 0.3s ease, transform 0.3s ease;
    font-size: 1.1em;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    z-index: 5;
}

.settings-btn-header:hover {
    background: rgba(255, 255, 255, 0.4);
    transform: rotate(45deg);
}


/* Bottom Navigation Bar */
.bottom-nav {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: var(--card);
    border-top: 1px solid var(--bd);
    padding: 8px 0;
    z-index: 1000;
    backdrop-filter: blur(10px);
    box-shadow: 0 -4px 20px rgba(0,0,0,0.1);
}

.nav-items {
    display: flex;
    justify-content: space-around;
    align-items: center;
    max-width: 500px;
    margin: 0 auto;
}

.nav-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-decoration: none;
    color: var(--fg);
    padding: 8px 12px;
    border-radius: var(--radius);
    transition: all 0.3s ease;
    flex: 1;
    max-width: 80px;
}

.nav-item:hover {
    background: rgba(59, 130, 246, 0.1);
    color: var(--primary-btn);
}

.nav-item.active {
    color: var(--primary-btn);
    background: rgba(59, 130, 246, 0.15);
}

.nav-icon {
    font-size: 1.2em;
    margin-bottom: 4px;
    transition: transform 0.3s ease;
}

.nav-item.active .nav-icon {
    transform: scale(1.1);
}

.nav-label {
    font-size: 0.75em;
    font-weight: 600;
    text-align: center;
}

/* Content Sections */
.content-section {
    display: none;
    animation: fadeIn 0.3s ease;
}

.content-section.active {
    display: block;
}

@keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
}

/* Stats Grid */
.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
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
    transition: transform 0.3s ease;
}

.stat-card:hover {
    transform: translateY(-2px);
}

.stat-icon {
    font-size: 2em;
    margin-bottom: 10px;
    opacity: 0.9;
}

.stat-number {
    font-size: 1.8em;
    font-weight: 900;
    margin: 8px 0;
    background: var(--gradient);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}

.stat-label {
    font-size: 0.85em;
    color: var(--bd);
    font-weight: 600;
}

/* Quick Actions */
.quick-actions {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 12px;
    margin: 20px 0;
}

.quick-btn {
    padding: 15px 10px;
    background: var(--card);
    border: 1px solid var(--bd);
    border-radius: var(--radius);
    text-align: center;
    cursor: pointer;
    transition: all 0.3s ease;
    text-decoration: none;
    color: var(--fg);
}

.quick-btn:hover {
    background: var(--primary-btn);
    color: white;
    transform: translateY(-2px);
}

.quick-btn i {
    font-size: 1.3em;
    margin-bottom: 6px;
    display: block;
}

.quick-btn span {
    font-size: 0.8em;
    font-weight: 600;
}

/* Forms and Tables */
.form-card {
    background: var(--card);
    padding: 20px;
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    border: 1px solid var(--bd);
    margin-bottom: 20px;
}

.form-title {
    color: var(--primary-btn);
    margin: 0 0 15px 0;
    font-size: 1.3em;
    display: flex;
    align-items: center;
    gap: 10px;
}

.form-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 15px;
    margin-top: 15px;
}

.form-group {
    margin-bottom: 15px;
}

label {
    display: block;
    margin-bottom: 6px;
    font-weight: 600;
    color: var(--fg);
    font-size: 0.9em;
}

input, select {
    width: 100%;
    padding: 12px;
    border: 2px solid var(--bd);
    border-radius: var(--radius);
    background: var(--bg);
    color: var(--input-text);
    font-size: 0.9em;
    transition: all 0.3s ease;
}

input:focus, select:focus {
    outline: none;
    border-color: var(--primary-btn);
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

/* Buttons */
.btn {
    padding: 12px 20px;
    border: none;
    border-radius: var(--radius);
    color: white;
    text-decoration: none;
    cursor: pointer;
    transition: all 0.3s ease;
    font-weight: 600;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 0.9em;
}

.btn-primary { background: var(--primary-btn); }
.btn-primary:hover { background: #2563eb; transform: translateY(-1px); }

.btn-success { background: var(--success); }
.btn-success:hover { background: #05c189; transform: translateY(-1px); }

.btn-danger { background: var(--delete-btn); }
.btn-danger:hover { background: #dc2626; transform: translateY(-1px); }

.btn-block {
    width: 100%;
    justify-content: center;
}

/* Table */
.table-container {
    overflow-x: auto;
    border-radius: var(--radius);
    background: var(--card);
    border: 1px solid var(--bd);
    margin: 20px 0;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: var(--card);
}

th, td {
    padding: 12px 15px;
    text-align: left;
    border-bottom: 1px solid var(--bd);
    font-size: 0.85em;
}

th {
    background: var(--primary-btn);
    color: white;
    font-weight: 600;
    text-transform: uppercase;
}

tr:hover {
    background: rgba(59, 130, 246, 0.05);
}

/* Status Pills */
.pill {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 12px;
    font-size: 0.75em;
    font-weight: 700;
    color: white;
}

.pill-online { background: var(--ok); }
.pill-offline { background: var(--bad); }
.pill-expired { background: var(--expired); }
.pill-suspended { background: var(--unknown); }

/* Action Buttons */
.action-btns {
    display: flex;
    gap: 5px;
    flex-wrap: wrap;
}

.action-btn {
    padding: 6px 10px;
    border: none;
    border-radius: var(--radius);
    cursor: pointer;
    transition: all 0.3s ease;
    font-size: 0.8em;
}

.action-btn i {
    font-size: 0.9em;
}

/* Modal */
.custom-modal {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.5);
    z-index: 2000;
    backdrop-filter: blur(5px);
    align-items: center;
    justify-content: center;
}

.modal-content {
    background: var(--card);
    padding: 25px;
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    width: 90%;
    max-width: 450px;
    transform: scale(0.95);
    transition: transform 0.3s ease;
}
.custom-modal.active .modal-content {
    transform: scale(1);
}

.modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 15px;
    border-bottom: 1px solid var(--bd);
}

.modal-header h3 {
    margin: 0;
    color: var(--primary-btn);
    display: flex;
    align-items: center;
    gap: 10px;
}

.close-modal {
    background: none;
    border: none;
    font-size: 1.5em;
    color: var(--fg);
    cursor: pointer;
    padding: 5px;
}

/* Login Styles */
.login-container {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--gradient);
    padding: 20px;
}

.login-card {
    background: var(--card);
    padding: 30px;
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    width: 100%;
    max-width: 400px;
    text-align: center;
}

.login-logo {
    height: 80px;
    width: 80px;
    border-radius: 50%;
    border: 3px solid var(--primary-btn);
    margin: 0 auto 20px;
    padding: 5px;
    background: white;
}

.login-title {
    margin: 0 0 20px 0;
    color: var(--fg);
    font-size: 1.5em;
    font-weight: 700;
}

/* Login Checkbox (Save Login) */
.checkbox-container {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    margin: 15px 0 25px 0;
    cursor: pointer;
}

.checkbox-container input[type="checkbox"] {
    width: auto;
    padding: 0;
    margin: 0;
    height: 18px;
    width: 18px;
    accent-color: var(--primary-btn);
}


/* Messages */
.alert {
    padding: 12px 15px;
    border-radius: var(--radius);
    margin: 15px 0;
    font-weight: 600;
}

.alert-success {
    background: var(--success);
    color: white;
}

.alert-error {
    background: var(--delete-btn);
    color: white;
}

/* Responsive Design */
@media (max-width: 768px) {
    .container {
        padding: 15px;
        padding-bottom: 70px;
    }
    
    .header {
        padding: 15px;
        margin-bottom: 15px;
    }
    
    .header h1 {
        font-size: 1.5em;
    }
    
    .stats-grid {
        grid-template-columns: 1fr 1fr;
        gap: 12px;
    }
    
    .quick-actions {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .form-grid {
        grid-template-columns: 1fr;
    }
    
    th, td {
        padding: 10px 12px;
        font-size: 0.8em;
    }
    
    .nav-label {
        font-size: 0.7em;
    }
}

@media (max-width: 480px) {
    .stats-grid {
        grid-template-columns: 1fr;
    }
    
    .quick-actions {
        grid-template-columns: 1fr;
    }
    
    .nav-item {
        padding: 6px 8px;
    }
    
    .nav-label {
        font-size: 0.65em;
    }
}
    </style>
</head>
<body data-theme="{{theme}}">

{% if not authed %}
<div class="login-container">
    <div class="login-card">
        <img src="{{ logo }}" alt="ZIVPN" class="login-logo">
        <h2 class="login-title">{{t.login_title}}</h2>
        {% if err %}<div class="alert alert-error">{{err}}</div>{% endif %}
        <form method="post" action="/login">
            <div class="form-group">
                <label><i class="fas fa-user"></i> {{t.username}}</label>
                <input name="u" autofocus required>
            </div>
            <div class="form-group">
                <label><i class="fas fa-lock"></i> {{t.password}}</label>
                <input name="p" type="password" required>
            </div>
            
            <!-- NEW: Save Login Checkbox -->
            <label class="checkbox-container">
                <input type="checkbox" name="remember_me" checked>
                {{t.save_login}}
            </label>
            
            <button type="submit" class="btn btn-primary btn-block">
                <i class="fas fa-sign-in-alt"></i>{{t.login}}
            </button>
        </form>
    </div>
</div>
{% else %}

<div class="container">
    <!-- Modern Header -->
    <header class="header">
        <div class="header-content">
            <div class="logo-container">
                <img src="{{ logo }}" alt="ZIVPN" class="logo">
                <h1>ZIVPN Enterprise</h1>
            </div>
            <div class="subtitle">Management System</div>
        </div>
        <!-- NEW: Settings Button -->
        <button class="settings-btn-header" onclick="openSettings()" title="{{t.settings}}">
            <i class="fas fa-cog"></i>
        </button>
    </header>
    
    {% if msg %}<div class="alert alert-success">{{msg}}</div>{% endif %}
    {% if err %}<div class="alert alert-error">{{err}}</div>{% endif %}

    <!-- Home Section -->
    <div id="home" class="content-section active">
        <!-- Stats Overview -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--primary-btn);">
                    <i class="fas fa-users"></i>
                </div>
                <div class="stat-number">{{ stats.total_users }}</div>
                <div class="stat-label">{{t.total_users}}</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--ok);">
                    <i class="fas fa-signal"></i>
                </div>
                <div class="stat-number">{{ stats.active_users }}</div>
                <div class="stat-label">{{t.active_users}}</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--delete-btn);">
                    <i class="fas fa-database"></i>
                </div>
                <div class="stat-number">{{ stats.total_bandwidth }}</div>
                <div class="stat-label">{{t.bandwidth_used}}</div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--unknown);">
                    <i class="fas fa-server"></i>
                </div>
                <div class="stat-number">{{ stats.server_load }}%</div>
                <div class="stat-label">{{t.server_load}}</div>
            </div>
        </div>

        <!-- Quick Actions -->
        <div class="form-card">
            <h3 class="form-title"><i class="fas fa-bolt"></i> {{t.quick_actions}}</h3>
            <div class="quick-actions">
                <a href="javascript:void(0)" class="quick-btn" onclick="showSection('manage')">
                    <i class="fas fa-users"></i>
                    <span>{{t.manage}}</span>
                </a>
                <a href="javascript:void(0)" class="quick-btn" onclick="showSection('adduser')">
                    <i class="fas fa-user-plus"></i>
                    <span>{{t.add_user}}</span>
                </a>
                <a href="javascript:void(0)" class="quick-btn" onclick="showSection('bulk')">
                    <i class="fas fa-cogs"></i>
                    <span>{{t.bulk_ops}}</span>
                </a>
                <a href="javascript:void(0)" class="quick-btn" onclick="showSection('reports')">
                    <i class="fas fa-chart-bar"></i>
                    <span>{{t.reports}}</span>
                </a>
            </div>
        </div>

        <!-- Recent Activity -->
        <div class="form-card">
            <h3 class="form-title"><i class="fas fa-clock"></i> {{t.recent_activity}}</h3>
            <div style="max-height: 200px; overflow-y: auto;">
                {% for u in users[:5] %}
                <div style="padding: 10px; border-bottom: 1px solid var(--bd); display: flex; justify-content: space-between; align-items: center;">
                    <div>
                        <strong>{{u.user}}</strong>
                        <div style="font-size: 0.8em; color: var(--bd);">Port: {{u.port or 'Default'}}</div>
                    </div>
                    <span class="pill pill-{{u.status|lower}}">{{u.status}}</span>
                </div>
                {% endfor %}
            </div>
        </div>
    </div>

    <!-- Manage Users Section -->
    <div id="manage" class="content-section">
        <div class="form-card">
            <h3 class="form-title"><i class="fas fa-users"></i> {{t.user_management}}</h3>
            <div style="display: flex; gap: 10px; margin-bottom: 15px;">
                <!-- Search by User or HWID -->
                <input type="text" id="searchUser" placeholder="{{t.user_search}}" style="flex: 1;">
                <button class="btn btn-primary" onclick="filterUsers()">
                    <i class="fas fa-search"></i>
                </button>
            </div>
        </div>

        <div class="table-container">
            <table id="userTable">
                <thead>
                    <tr>
                        <th>{{t.user}}</th>
                        <th>{{t.password}}</th>
                        <th>{{t.hwid}}</th> <!-- NEW HWID COLUMN -->
                        <th>{{t.expires}}</th>
                        <th>{{t.status}}</th>
                        <th>{{t.actions}}</th>
                    </tr>
                </thead>
                <tbody>
                {% for u in users %}
                <tr data-hwid="{{u.hwid}}" data-user="{{u.user}}">
                    <td><strong>{{u.user}}</strong></td>
                    <td>{{u.password}}</td>
                    <td><small>{{u.hwid or '-'}}</small></td> <!-- NEW HWID CELL -->
                    <td>{{u.expires or '-'}}</td>
                    <td>
                        <span class="pill pill-{{u.status|lower}}">{{u.status}}</span>
                    </td>
                    <td>
                        <div class="action-btns">
                            <button class="action-btn btn-danger" onclick="deleteUser('{{u.user}}')" title="Delete">
                                <i class="fas fa-trash"></i>
                            </button>
                            <!-- Updated Edit button to open custom modal -->
                            <button class="action-btn btn-primary" onclick="openEditModal('{{u.user}}', '{{u.password}}', '{{u.hwid}}')" title="Edit">
                                <i class="fas fa-edit"></i>
                            </button>
                        </div>
                    </td>
                </tr>
                {% endfor %}
                </tbody>
            </table>
        </div>
    </div>

    <!-- Add User Section -->
    <div id="adduser" class="content-section">
        <form method="post" action="/add" class="form-card">
            <h3 class="form-title"><i class="fas fa-user-plus"></i> {{t.add_user}}</h3>
            
            <div class="form-grid">
                <div class="form-group">
                    <label>{{t.user}}</label>
                    <input name="user" placeholder="{{t.user}}" required>
                </div>
                <div class="form-group">
                    <label>{{t.password}}</label>
                    <input name="password" placeholder="{{t.password}}" required>
                </div>
                <div class="form-group">
                    <label>{{t.hwid}}</label> <!-- NEW HWID INPUT -->
                    <input name="hwid" placeholder="Optional HWID Code (e.g., A1B2C3D4)">
                </div>
                <div class="form-group">
                    <label>{{t.expires}}</label>
                    <input name="expires" placeholder="YYYY-MM-DD or days (e.g., 30)">
                </div>
                <div class="form-group">
                    <label>{{t.port}}</label>
                    <input name="port" placeholder="Auto" type="number" min="6000" max="19999">
                </div>
                
                <div class="form-group">
                    <label>{{t.speed_limit}}</label>
                    <input name="speed_limit" placeholder="0 = Unlimited" type="number">
                </div>
                <div class="form-group">
                    <label>{{t.bw_limit}}</label>
                    <input name="bandwidth_limit" placeholder="0 = Unlimited" type="number">
                </div>
                <div class="form-group">
                    <label>{{t.max_conn}}</label>
                    <input name="concurrent_conn" value="1" type="number" min="1" max="10">
                </div>
                <div class="form-group">
                    <label>Plan Type</label>
                    <select name="plan_type">
                        <option value="free">Free</option>
                        <option value="daily">Daily</option>
                        <option value="weekly">Weekly</option>
                        <option value="monthly" selected>Monthly</option>
                        <option value="yearly">Yearly</option>
                    </select>
                </div>
            </div>

            <button type="submit" class="btn btn-success btn-block">
                <i class="fas fa-save"></i> {{t.save_user}}
            </button>
        </form>
    </div>

    <!-- Bulk Operations Section -->
    <div id="bulk" class="content-section">
        <div class="form-card">
            <h3 class="form-title"><i class="fas fa-cogs"></i> {{t.bulk_ops}}</h3>
            <div class="form-grid">
                <div class="form-group">
                    <label>{{t.actions}}</label>
                    <select id="bulkAction">
                        <option value="">{{t.select_action}}</option>
                        <option value="extend">{{t.extend_exp}}</option>
                        <option value="suspend">{{t.suspend_users}}</option>
                        <option value="activate">{{t.activate_users}}</option>
                        <option value="delete">{{t.delete_users}}</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>{{t.user}}</label>
                    <input type="text" id="bulkUsers" placeholder="user1,user2,user3">
                </div>
            </div>
            <button class="btn btn-primary btn-block" onclick="executeBulkAction()">
                <i class="fas fa-play"></i> {{t.execute}}
            </button>
        </div>
    </div>

    <!-- Reports Section -->
    <div id="reports" class="content-section">
        <div class="form-card">
            <h3 class="form-title"><i class="fas fa-chart-bar"></i> {{t.reports}}</h3>
            <div class="form-grid">
                <div class="form-group">
                    <label>From Date</label>
                    <input type="date" id="fromDate">
                </div>
                <div class="form-group">
                    <label>To Date</label>
                    <input type="date" id="toDate">
                </div>
                <div class="form-group">
                    <label>Report Type</label>
                    <select id="reportType">
                        <option value="bandwidth">{{t.report_bw}}</option>
                        <option value="users">{{t.report_users}}</option>
                        <option value="revenue">{{t.report_revenue}}</option>
                    </select>
                </div>
            </div>
            <button class="btn btn-primary btn-block" onclick="generateReport()">
                <i class="fas fa-chart-line"></i> Generate Report
            </button>
        </div>
        <div id="reportResults"></div>
    </div>
</div>

<!-- Bottom Navigation Bar (Removed Settings, kept main navigation) -->
<nav class="bottom-nav">
    <div class="nav-items">
        <a href="javascript:void(0)" class="nav-item active" data-section="home" onclick="showSection('home')">
            <i class="fas fa-home nav-icon"></i>
            <span class="nav-label">{{t.home}}</span>
        </a>
        <a href="javascript:void(0)" class="nav-item" data-section="manage" onclick="showSection('manage')">
            <i class="fas fa-users nav-icon"></i>
            <span class="nav-label">{{t.manage}}</span>
        </a>
        <a href="javascript:void(0)" class="nav-item" data-section="adduser" onclick="showSection('adduser')">
            <i class="fas fa-user-plus nav-icon"></i>
            <span class="nav-label">Add User</span>
        </a>
        <a href="javascript:void(0)" class="nav-item" data-section="bulk" onclick="showSection('bulk')">
            <i class="fas fa-cogs nav-icon"></i>
            <span class="nav-label">Bulk</span>
        </a>
        <a href="javascript:void(0)" class="nav-item" data-section="reports" onclick="showSection('reports')">
            <i class="fas fa-chart-bar nav-icon"></i>
            <span class="nav-label">{{t.reports}}</span>
        </a>
    </div>
</nav>

<!-- Custom Modal for User Edit (Password/HWID) -->
<div id="editUserModal" class="custom-modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3><i class="fas fa-edit"></i> Edit User: <span id="editUsername"></span></h3>
            <button class="close-modal" onclick="closeEditModal()">&times;</button>
        </div>
        <form id="editForm" onsubmit="submitEdit(event)">
            <input type="hidden" id="editOriginalUser">
            <div class="form-group">
                <label>{{t.password}}</label>
                <input type="text" id="editPassword" required>
            </div>
            <div class="form-group">
                <label>{{t.hwid}}</label>
                <input type="text" id="editHWID" placeholder="Hardware ID">
            </div>
            <button type="submit" class="btn btn-primary btn-block">
                <i class="fas fa-save"></i> Save Changes
            </button>
        </form>
    </div>
</div>


<!-- Settings Modal (Remains the same structure) -->
<div id="settingsModal" class="custom-modal">
    <div class="modal-content">
        <div class="modal-header">
            <h3><i class="fas fa-cog"></i> {{t.settings}}</h3>
            <button class="close-modal" onclick="closeSettings()">&times;</button>
        </div>
        
        <div class="setting-group">
            <label class="setting-label"><i class="fas fa-palette"></i> Theme</label>
            <div class="theme-options">
                <div class="theme-option {% if theme == 'dark' %}active{% endif %}" data-theme="dark" onclick="changeTheme('dark')">
                    <i class="fas fa-moon"></i> Dark
                </div>
                <div class="theme-option {% if theme == 'light' %}active{% endif %}" data-theme="light" onclick="changeTheme('light')">
                    <i class="fas fa-sun"></i> Light
                </div>
            </div>
        </div>
        
        <div class="setting-group">
            <label class="setting-label"><i class="fas fa-language"></i> Language</label>
            <div class="lang-options">
                <div class="lang-option {% if lang == 'my' %}active{% endif %}" data-lang="my" onclick="changeLanguage('my')">
                    <i class="fas fa-language"></i> မြန်မာ
                </div>
                <div class="lang-option {% if lang == 'en' %}active{% endif %}" data-lang="en" onclick="changeLanguage('en')">
                    <i class="fas fa-language"></i> English
                </div>
            </div>
        </div>
        
        <div class="setting-group">
            <a class="btn btn-primary btn-block" href="/api/export/users">
                <i class="fas fa-download"></i> Export Users CSV
            </a>
        </div>

        <div class="setting-group">
            <a class="btn btn-danger btn-block" href="/logout">
                <i class="fas fa-sign-out-alt"></i> {{t.logout}}
            </a>
        </div>
    </div>
</div>

{% endif %}

<script>
// Parse Jinja translations for use in JS
const translations = {{t|tojson}};
const allUsers = [
    {% for u in users %}
    {user: "{{u.user}}", password: "{{u.password}}", hwid: "{{u.hwid}}", status: "{{u.status|lower}}", expires: "{{u.expires}}"},
    {% endfor %}
];

// Navigation Functions
function showSection(sectionId) {
    // Hide all sections
    document.querySelectorAll('.content-section').forEach(section => {
        section.classList.remove('active');
    });
    
    // Remove active class from all nav items
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    
    // Show selected section and activate nav item
    document.getElementById(sectionId).classList.add('active');
    
    // Find the corresponding nav item using data-section
    const navItem = document.querySelector(`.nav-item[data-section="${sectionId}"]`);
    if (navItem) {
        navItem.classList.add('active');
    }
}

// Settings Modal Functions (Now uses custom-modal class)
function openSettings() {
    document.getElementById('settingsModal').classList.add('active');
}

function closeSettings() {
    document.getElementById('settingsModal').classList.remove('active');
}

// Theme Functions
function changeTheme(theme) {
    document.body.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    
    // Update active state
    document.querySelectorAll('.theme-option').forEach(option => {
        option.classList.remove('active');
    });
    event.currentTarget.classList.add('active');
}

// Language Functions
function changeLanguage(lang) {
    window.location.href = '/set_lang?lang=' + lang;
}

// Initialize theme/nav from localStorage
document.addEventListener('DOMContentLoaded', () => {
    const storedTheme = localStorage.getItem('theme') || 'dark';
    document.body.setAttribute('data-theme', storedTheme);
    
    // Set active theme option
    document.querySelectorAll('.theme-option').forEach(option => {
        option.classList.remove('active');
        if (option.getAttribute('data-theme') === storedTheme) {
            option.classList.add('active');
        }
    });

    // Handle initial active section (if not home)
    const activeSection = document.querySelector('.content-section.active');
    if (activeSection) {
         const sectionId = activeSection.id;
         const navItem = document.querySelector(`.nav-item[data-section="${sectionId}"]`);
         if (navItem) {
             navItem.classList.add('active');
         }
    }
});

// User Management Functions
function filterUsers() {
    const search = document.getElementById('searchUser').value.toLowerCase();
    
    document.querySelectorAll('#userTable tbody tr').forEach(row => {
        const user = row.getAttribute('data-user').toLowerCase();
        const hwid = row.getAttribute('data-hwid').toLowerCase();
        
        // Search by User or HWID
        const shouldShow = user.includes(search) || hwid.includes(search);
        row.style.display = shouldShow ? '' : 'none';
    });
}

function deleteUser(username) {
    if (confirm(translations.delete_confirm.replace('{user}', username))) {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = '/delete';
        
        const input = document.createElement('input');
        input.type = 'hidden';
        input.name = 'user';
        input.value = username;
        
        form.appendChild(input);
        document.body.appendChild(form);
        form.submit();
    }
}

// NEW: Edit Modal Functions
function openEditModal(username, password, hwid) {
    document.getElementById('editUsername').textContent = username;
    document.getElementById('editOriginalUser').value = username;
    document.getElementById('editPassword').value = password;
    document.getElementById('editHWID').value = hwid;
    document.getElementById('editUserModal').classList.add('active');
}

function closeEditModal() {
    document.getElementById('editUserModal').classList.remove('active');
}

function submitEdit(event) {
    event.preventDefault();
    const user = document.getElementById('editOriginalUser').value;
    const password = document.getElementById('editPassword').value;
    const hwid = document.getElementById('editHWID').value;

    fetch('/api/user/update', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({user, password, hwid})
    }).then(r => r.json()).then(data => {
        alert(data.message); 
        closeEditModal();
        location.reload();
    }).catch(e => {
        alert('Error updating user: ' + e.message);
    });
}


// Bulk Action Function
function executeBulkAction() {
    const action = document.getElementById('bulkAction').value;
    const users = document.getElementById('bulkUsers').value;
    
    if (!action || !users) { 
        alert(translations.select_action + ' / ' + translations.user + ' လိုအပ်သည်'); 
        return; 
    }

    if (action === 'delete' && !confirm(translations.delete_users + ' ' + users + ' ကို ဖျက်ရန် သေချာပါသလား?')) return;
    
    fetch('/api/bulk', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({action, users: users.split(',').map(u => u.trim()).filter(u => u)})
    }).then(r => r.json()).then(data => {
        alert(data.message.replace('{action}', action)); 
        location.reload();
    }).catch(e => {
        alert('Error: ' + e.message);
    });
}

// Report Generation Function
function generateReport() {
    const from = document.getElementById('fromDate').value;
    const to = document.getElementById('toDate').value;
    const type = document.getElementById('reportType').value;
    const reportResults = document.getElementById('reportResults');

    if (!from || !to) {
        alert(translations.report_range);
        return;
    }

    reportResults.innerHTML = '<div class="form-card" style="text-align: center; padding: 30px;"><i class="fas fa-spinner fa-spin"></i> Generating Report...</div>';

    fetch(`/api/reports?from=${from}&to=${to}&type=${type}`)
        .then(r => r.json())
        .then(data => {
            reportResults.innerHTML = `
                <div class="form-card">
                    <h3 class="form-title">${type.toUpperCase()} Report (${from} to ${to})</h3>
                    <pre style="background: var(--bg); padding: 15px; border-radius: var(--radius); border: 1px solid var(--bd); overflow-x: auto;">${JSON.stringify(data, null, 2)}</pre>
                </div>
            `;
        })
        .catch(e => {
            reportResults.innerHTML = '<div class="alert alert-error">Error loading report: ' + e.message + '</div>';
        });
}

// Close modals when clicking outside
window.onclick = function(event) {
    const settingsModal = document.getElementById('settingsModal');
    const editModal = document.getElementById('editUserModal');
    
    if (event.target === settingsModal) {
        closeSettings();
    }
    if (event.target === editModal) {
        closeEditModal();
    }
}
</script>
</body>
</html>
"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()
DATABASE_PATH = os.environ.get("DATABASE_PATH", "/etc/zivpn/zivpn.db")

# *** NEW: Enable permanent sessions (2 weeks) ***
app.permanent_session_lifetime = timedelta(days=14)

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
               concurrent_conn, hwid
        FROM users
    ''').fetchall()
    db.close()
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
        db.commit()
        
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
        # Use an optimized conntrack command to check for presence of a connection on the specific port
        command = f"conntrack -L -p udp 2>/dev/null | awk '/dport={port}\\b/ {{print $1}}' | head -n 1"
        out=subprocess.run(command, shell=True, capture_output=True, text=True).stdout
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
        
        # Handle permanent session if checkbox is checked
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
    html_template = load_html_template()
    return render_template_string(html_template, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
                                 t=t, lang=g.lang, theme=theme)

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

def build_view(msg="", err=""):
    t = g.t
    if not require_login():
        html_template = load_html_template()
        return render_template_string(html_template, authed=False, logo=LOGO_URL, err=session.pop("login_err", None), 
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
            "concurrent_conn": u.get('concurrent_conn', 1),
            "hwid": u.get('hwid', '')
        }))
    
    view.sort(key=lambda x:(x.user or "").lower())
    today=today_date.strftime("%Y-%m-%d")
    
    theme = session.get('theme', 'dark')
    html_template = load_html_template()
    return render_template_string(html_template, authed=True, logo=LOGO_URL, 
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
    csv_data = "User,Password,Expires,Port,HWID,Bandwidth Used (GB),Bandwidth Limit (GB),Speed Limit (MB/s),Max Connections,Status\n"
    for u in users:
        csv_data += f"{u['user']},{u['password']},{u.get('expires','')},{u.get('port','')},{u.get('hwid','')},{u.get('bandwidth_used',0):.2f},{u.get('bandwidth_limit',0)},{u.get('speed_limit',0)},{u.get('concurrent_conn',1)},{u.get('status','')}\n"
    
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
                ORDER BY created_at ASC
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
    hwid = data.get('hwid')

    if user:
        db = get_db()
        try:
            update_fields = []
            params = []
            
            # Allow password update
            if password is not None:
                update_fields.append("password = ?")
                params.append(password)
            
            # Allow HWID update
            if hwid is not None:
                update_fields.append("hwid = ?")
                params.append(hwid)
                
            if not update_fields:
                return jsonify({"ok": False, "err": "No fields to update"}), 400

            query = f'UPDATE users SET {", ".join(update_fields)} WHERE username = ?'
            params.append(user)
            
            db.execute(query, tuple(params))
            db.commit()
            sync_config_passwords()
            return jsonify({"ok": True, "message": "User credentials updated"})
        except Exception as e:
            # Note: The database script needs to ensure the 'hwid' column exists.
            # Assuming the initial setup script has been updated to include it (or it's a new DB).
            print(f"Database error during user update: {e}")
            return jsonify({"ok": False, "err": "Database update failed. Check if 'hwid' column exists."}), 500
        finally:
            db.close()
    
    return jsonify({"ok": False, "err": "Invalid data"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
