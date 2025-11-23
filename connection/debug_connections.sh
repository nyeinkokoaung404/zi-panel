#!/bin/bash
echo "=== ZIVPN Connection Debug ==="

echo "1. Database users and ports:"
sqlite3 /etc/zivpn/zivpn.db "SELECT username, port, concurrent_conn, status FROM users;"

echo ""
echo "2. Active conntrack connections on ZIVPN ports:"
sudo conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|1[0-9]{4})' | head -20

echo ""
echo "3. Connection count by port:"
sudo conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|1[0-9]{4})' | awk '{print $6}' | cut -d= -f2 | sort | uniq -c | sort -nr

echo ""
echo "4. Recent logs:"
sudo tail -n 30 /var/log/zivpn/connection_manager.log

echo ""
echo "5. Check if user device is connected:"
read -p "Enter username to check: " username
port=$(sqlite3 /etc/zivpn/zivpn.db "SELECT port FROM users WHERE username='$username';")
echo "User $username port: $port"

if [ -n "$port" ]; then
    echo "Connections on port $port:"
    sudo conntrack -L -p udp 2>/dev/null | grep "dport=$port" | grep ESTABLISHED
fi
