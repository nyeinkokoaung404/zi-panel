#!/bin/bash
# ZIVPN Enterprise Management Services Restart Script
# Author: 4 0 4 \ 2.0 [🇲🇲]
set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE"
echo -e "${G}🔄 ZIVPN Enterprise Services Restarting Sequence...${Z}"
echo -e "$LINE"

# ===== Function to Restart and Check Status =====
restart_service() {
    SERVICE_NAME=$1
    say "${C}* Restarting ${SERVICE_NAME}...${Z}"

    # Use 'sudo systemctl restart' for consistency; it handles stopping if active.
    if sudo systemctl restart "${SERVICE_NAME}"; then
        # Wait a moment for the service to actually start up
        sleep 2
        
        if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
            say "${G}  ✅ ${SERVICE_NAME} restarted and running.${Z}"
        else
            say "${R}  ❌ ERROR: ${SERVICE_NAME} failed to start. Checking logs...${Z}"
            # Show the last 15 lines of the journal log for the failed service
            sudo journalctl -u "${SERVICE_NAME}" --since "30 seconds ago" -n 15
        fi
    else
        say "${R}  ❌ FATAL ERROR: Command execution failed for ${SERVICE_NAME}.${Z}"
    fi
}

# ===== Execution Order =====

# 1. Restart core VPN service (zivpn.service)
say "${Y}--- Core VPN Service ---${Z}"
restart_service zivpn.service

# 2. Restart critical operational manager (zivpn-connection.service)
#    - This manager enforces concurrent connection limits using conntrack, essential for user policy.
say "${Y}--- Operational Managers ---${Z}"
restart_service zivpn-connection.service

# 3. Restart management components (API, Web, Bot)
#    - These interface with the database and provide management/user interaction.
say "${Y}--- Management Interfaces ---${Z}"
restart_service zivpn-api.service
restart_service zivpn-web.service
restart_service zivpn-bot.service

# 4. Trigger and ensure periodic timers are active
#    - Timers are responsible for cleanup (expiry) and database backup.
say "${Y}--- Ensuring Periodic Jobs are Active ---${Z}"
sudo systemctl enable --now zivpn-backup.timer 2>/dev/null || true
sudo systemctl enable --now zivpn-cleanup.timer 2>/dev/null || true
say "${G}  ✅ Backup (zivpn-backup.timer) and Cleanup (zivpn-cleanup.timer) timers enabled/checked.${Z}"

echo -e "\n$LINE"
echo -e "${G}✨ All ZIVPN Enterprise Services restart sequence completed!${Z}"
echo -e "$LINE"
