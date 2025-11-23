# /etc/zivpn/connection_manager.py

import sqlite3
import subprocess
import time
import threading
from datetime import datetime
import os
import logging

# Configuration
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/zivpn/connection_manager.log'),
        logging.StreamHandler()
    ]
)

class ConnectionManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.logger = logging.getLogger(__name__)

    def get_db(self):
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        return conn
        
    def get_active_connections(self):
        """
        conntrack ကိုသုံးပြီး UDP connections များကို ရယူသည်။
        Improved version for better accuracy
        """
        try:
            # More precise conntrack command
            cmd = "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|[1-9][0-9]{4})' | grep ESTABLISHED"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            
            connections = {}
            for line in result.stdout.split('\n'):
                if 'src=' in line and 'dport=' in line:
                    try:
                        parts = line.split()
                        src_ip = None
                        dport = None
                        
                        for part in parts:
                            if part.startswith('src='):
                                src_ip = part.split('=')[1]
                            elif part.startswith('dport='):
                                dport = part.split('=')[1]
                        
                        if src_ip and dport:
                            # Group by source IP and port
                            key = f"{src_ip}:{dport}"
                            connections[key] = {
                                'src_ip': src_ip,
                                'dport': dport,
                                'raw_line': line
                            }
                    except Exception as e:
                        self.logger.debug(f"Error parsing line: {e}")
                        continue
            return connections
        except Exception as e:
            self.logger.error(f"Error fetching conntrack data: {e}")
            return {}
            
    def enforce_connection_limits(self):
        """User တစ်ယောက်ချင်းစီအတွက် connection limit ကို အတိအကျ စစ်ဆေးသည်။"""
        db = self.get_db()
        try:
            # Get all active users with their connection limits and ports
            users = db.execute('''
                SELECT username, concurrent_conn, port 
                FROM users 
                WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)
            ''').fetchall()
            
            active_connections = self.get_active_connections()
            self.logger.info(f"Found {len(active_connections)} active connections")
            
            for user in users:
                username = user['username']
                max_connections = user['concurrent_conn']
                user_port = str(user['port'] or LISTEN_FALLBACK)
                
                self.logger.info(f"Checking user: {username}, Port: {user_port}, Max: {max_connections}")
                
                # Count connections for this user's port
                user_connections = {}
                for conn_key, conn_info in active_connections.items():
                    if conn_info['dport'] == user_port:
                        src_ip = conn_info['src_ip']
                        if src_ip not in user_connections:
                            user_connections[src_ip] = []
                        user_connections[src_ip].append(conn_key)
                
                num_unique_ips = len(user_connections)
                self.logger.info(f"User {username} has {num_unique_ips} unique IPs connected (max: {max_connections})")
                
                # Enforce the limit
                if num_unique_ips > max_connections:
                    self.logger.warning(f"Connection limit exceeded for {username}: {num_unique_ips} > {max_connections}")
                    
                    # Keep the oldest connections, drop the newest
                    ips_to_keep = list(user_connections.keys())[:max_connections]
                    ips_to_drop = list(user_connections.keys())[max_connections:]
                    
                    for ip in ips_to_drop:
                        self.logger.info(f"Dropping connections for IP {ip} (user: {username})")
                        for conn_key in user_connections[ip]:
                            self.drop_connection_by_key(conn_key)

        except Exception as e:
            self.logger.error(f"Error in connection limit enforcement: {e}")
        finally:
            db.close()
            
    def drop_connection_by_key(self, connection_key):
        """Drop connection using connection key (IP:PORT)"""
        try:
            ip, port = connection_key.split(':')
            # Use more specific conntrack deletion
            cmd = f"conntrack -D -p udp --dport {port} --orig-src {ip}"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully dropped connection: {connection_key}")
            else:
                self.logger.warning(f"Failed to drop connection {connection_key}: {result.stderr}")
                
        except Exception as e:
            self.logger.error(f"Error dropping connection {connection_key}: {e}")
            
    def start_monitoring(self):
        """Start the connection monitoring loop"""
        def monitor_loop():
            while True:
                try:
                    self.enforce_connection_limits()
                    time.sleep(15)  # Check every 15 seconds
                except Exception as e:
                    self.logger.error(f"Monitoring loop failed: {e}")
                    time.sleep(30)
                    
        monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
        monitor_thread.start()
        
# Global instance
connection_manager = ConnectionManager()

if __name__ == "__main__":
    print("Starting Enhanced ZIVPN Connection Manager...")
    connection_manager.start_monitoring()
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("Stopping Connection Manager...")
