#!/bin/bash
# ZIVPN Enterprise Web Panel Uninstall Script
# This script removes all components, services, and configurations installed by ZIVPN.

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${R}🚨 ZIVPN UDP Server + Web UI - Uninstall Script ${Z}\n${M}⚠️ All data and configurations will be removed. ${Z}\n$LINE"

# ===== Root Check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}❌ ဤ script ကို root ဖြင့် run ပါ (sudo -i)${Z}"; exit 1
fi

read -r -p "$(echo -e "${Y}⚠️ ZIVPN စနစ်တစ်ခုလုံးကို ဖျက်သိမ်းရန် သေချာပါသလား? (y/N): ${Z}")" CONFIRM
if [[ "$CONFIRM" != [yY] ]]; then
  echo -e "${G}✅ ဖျက်သိမ်းခြင်းကို ဖျက်သိမ်းလိုက်ပါပြီ။${Z}"
  exit 0
fi

# =================================================================
# 1. Services Stop and Disable
# =================================================================
say "\n${Y}🛑 ZIVPN Services အားလုံး ရပ်ပြီး disable လုပ်နေပါတယ်...${Z}"
systemctl stop zivpn.service 2>/dev/null || true
systemctl disable zivpn.service 2>/dev/null || true

systemctl stop zivpn-web.service 2>/dev/null || true
systemctl disable zivpn-web.service 2>/dev/null || true

systemctl stop zivpn-api.service 2>/dev/null || true
systemctl disable zivpn-api.service 2>/dev/null || true

systemctl stop zivpn-bot.service 2>/dev/null || true
systemctl disable zivpn-bot.service 2>/dev/null || true

systemctl stop zivpn-connection.service 2>/dev/null || true
systemctl disable zivpn-connection.service 2>/dev/null || true

systemctl stop zivpn-cleanup.timer 2>/dev/null || true
systemctl disable zivpn-cleanup.timer 2>/dev/null || true
systemctl stop zivpn-cleanup.service 2>/dev/null || true
systemctl disable zivpn-cleanup.service 2>/dev/null || true

systemctl stop zivpn-backup.timer 2>/dev/null || true
systemctl disable zivpn-backup.timer 2>/dev/null || true
systemctl stop zivpn-backup.service 2>/dev/null || true
systemctl disable zivpn-backup.service 2>/dev/null || true

systemctl daemon-reload

# =================================================================
# 2. Files and Directories Removal
# =================================================================
say "${Y}🗑️ ZIVPN ဖိုင်များနှင့် directories များ ဖျက်နေပါတယ်...${Z}"

# Remove systemd unit files
rm -f /etc/systemd/system/zivpn*.service
rm -f /etc/systemd/system/zivpn*.timer

# Remove binary
rm -f /usr/local/bin/zivpn

# Remove configuration, database, and all scripts
rm -rf /etc/zivpn

say "${G}✅ /usr/local/bin/zivpn နှင့် /etc/zivpn directory ကို ဖျက်ပြီးပါပြီ။${Z}"

# =================================================================
# 3. Networking Cleanup (IPTables/UFW)
# =================================================================
say "${Y}🧯 IPTables NAT စည်းမျဉ်းများ ဖျက်နေပါတယ်...${Z}"

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# 1. DNAT rule ဖျက်သည်။
# PREROUTING တွင် 6000:19999 မှ 5667 သို့ redirect လုပ်ထားသော DNAT rule ကို ဖျက်သည်။
iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || true

# 2. MASQUERADE rule ဖျက်သည်။
# ZIVPN server မှ ထွက်သွားသော traffic အတွက် MASQUERADE rule ကို ဖြုတ်သည်။
iptables -t nat -D POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || true

# 3. IP Forwarding ကို sysctl.conf မှ ဖြုတ်သည်။
say "${Y}⚙️ net.ipv4.ip_forward setting ကို sysctl မှ ဖြုတ်နေပါတယ်...${Z}"
sed -i '/^net.ipv4.ip_forward=1/d' /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

echo -e "${G}✅ NAT/MASQUERADE စည်းမျဉ်းများ ဖျက်ပြီးပါပြီ။ (UFW rules များ မဖျက်ပါ) ${Z}"

# =================================================================
# 4. Completion
# =================================================================
echo -e "\n$LINE"
echo -e "${G}🎉 ZIVPN Enterprise Edition Uninstall အောင်မြင်စွာ ပြီးစီးပါပြီ။${Z}"
echo -e "${C}👉 ကျန်ရှိသော packages များ (Python, Flask, Conntrack) ကို manual ဖြုတ်နိုင်ပါသည်။${Z}"
echo -e "$LINE"
