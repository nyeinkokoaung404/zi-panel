import sqlite3
import subprocess
import time
import threading
import os

# Configuration
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"

class ConnectionManager:
    def __init__(self):
        self.lock = threading.Lock()

    def get_db(self):
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        return conn
        
    def get_active_connections(self):
        """
        conntrack ကိုသုံးပြီး 'src=IP' နှင့် 'dport=PORT' ပါသော UDP connections များကို ရယူသည်။
        """
        try:
            # conntrack -L -p udp: UDP connections list ကို ပြသည်။
            # grep -E 'dport=(...)' : ZIVPN ports များ (5667 or 6000-19999) ကို စစ်သည်။
            result = subprocess.run(
                "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|[1-9][0-9]{4})'",
                shell=True, capture_output=True, text=True, timeout=5
            )
            
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
                            key = f"{src_ip}:{dport}"
                            # Store only one entry per IP:PORT pair (first one found)
                            if key not in connections:
                                connections[key] = line 
                    except:
                        continue
            return connections
        except Exception as e:
            print(f"Error fetching conntrack data: {e}")
            return {}
            
    def enforce_connection_limits(self):
        """Unique Source IP အရေအတွက်ကို စစ်ဆေးပြီး Max Connections ကို ထိန်းချုပ်သည်။"""
        db = self.get_db()
        try:
            # Get all active users with their connection limits
            users = db.execute('''
                SELECT username, concurrent_conn, port 
                FROM users 
                WHERE status = "active" AND (expires IS NULL OR expires >= CURRENT_DATE)
            ''').fetchall()
            
            active_connections = self.get_active_connections()
            
            for user in users:
                username = user['username']
                max_connections = user['concurrent_conn']
                user_port = str(user['port'] or LISTEN_FALLBACK)
                
                # Dictionary to map unique IPs connected to this user's port
                # Key: Source IP (Device), Value: List of full connection keys (IP:PORT)
                connected_ips = {} 

                # 1. Group connections by unique Source IP hitting the User's Port
                for conn_key in active_connections:
                    # Check if the connection destination port matches the user's port
                    if conn_key.endswith(f":{user_port}"):
                        ip = conn_key.split(':')[0]
                        if ip not in connected_ips:
                            connected_ips[ip] = []
                        connected_ips[ip].append(conn_key)
                
                num_unique_ips = len(connected_ips)

                # 2. Enforce the limit based on unique devices (Source IPs)
                if num_unique_ips > max_connections:
                    print(f"Limit Exceeded for {username} (Port {user_port}). IPs found: {num_unique_ips}, Max: {max_connections}")

                    # Determine which IPs to drop (Keep the first 'max_connections' found)
                    # This keeps the oldest/first connecting devices
                    ips_to_keep = list(connected_ips.keys())[:max_connections]
                    
                    for ip, conn_keys in connected_ips.items():
                        if ip not in ips_to_keep:
                            # This IP is an excess device. Drop ALL its connections.
                            print(f"  Dropping excess device IP: {ip} for user {username}")
                            for conn_key in conn_keys:
                                self.drop_connection(conn_key)

        except Exception as e:
            print(f"An error occurred during connection limit enforcement: {e}")
            
        finally:
            db.close()
            
    def drop_connection(self, connection_key):
        """Drop a specific connection using conntrack"""
        try:
            # connection_key format: "IP:PORT"
            ip, port = connection_key.split(':')
            # conntrack -D command ဖြင့် သက်ဆိုင်ရာ source IP နှင့် destination port ကို ဖြတ်ချသည်။
            subprocess.run(
                f"conntrack -D -p udp --dport {port} --src {ip}",
                shell=True, capture_output=True, text=True
            )
            print(f"Dropped connection: {connection_key}")
        except Exception as e:
            print(f"Error dropping connection {connection_key}: {e}")
            
    def start_monitoring(self):
        """Start the connection monitoring loop"""
        def monitor_loop():
            while True:
                try:
                    # Acquire lock before accessing shared resources (if any) or potentially long-running process
                    with self.lock:
                        self.enforce_connection_limits()
                    time.sleep(10)  # 10 စက္ကန့်တိုင်း စစ်ဆေးသည်။
                except Exception as e:
                    print(f"Monitoring loop failed: {e}")
                    time.sleep(30)
                    
        monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
        monitor_thread.start()
        
# Global instance
connection_manager = ConnectionManager()

if __name__ == "__main__":
    print("Starting ZIVPN Connection Manager...")
    connection_manager.start_monitoring()
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("Stopping Connection Manager...")
