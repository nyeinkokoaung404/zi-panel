import sqlite3
import subprocess
import time
import threading
import os
from subprocess import TimeoutError, CalledProcessError # Explicitly import necessary exceptions

# Configuration
DATABASE_PATH = "/etc/zivpn/zivpn.db"
LISTEN_FALLBACK = "5667"

class ConnectionManager:
    def __init__(self):
        # Thread safety အတွက် Lock ကို ထည့်သွင်းထားသည်။
        self.lock = threading.Lock()

    def get_db(self):
        conn = sqlite3.connect(DATABASE_PATH)
        conn.row_factory = sqlite3.Row
        return conn
        
    def get_active_connections(self):
        """
        conntrack ကိုသုံးပြီး 'src=IP' နှင့် 'dport=PORT' ပါသော UDP connections များကို ရယူသည်။
        (Fixed: ပိုမိုခိုင်မာသော parsing logic ဖြင့် ပြင်ဆင်ထားသည်။)
        """
        try:
            # Command looks for connections destined for ZIVPN ports
            command = "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|[1-9][0-9]{4})'"
            result = subprocess.run(
                command,
                shell=True, capture_output=True, text=True, timeout=5
            )
            
            connections = {}
            for line in result.stdout.split('\n'):
                if not line.strip():
                    continue

                # Use a dictionary comprehension to parse key=value pairs easily and robustly
                # key1=value1 key2=value2 -> {'key1': 'value1', 'key2': 'value2'}
                try:
                    parts = dict(part.split('=', 1) for part in line.split() if '=' in part)
                except ValueError:
                    # Skip lines that cannot be parsed as key=value pairs
                    continue
                
                # We need the client's source IP and the server's destination port
                src_ip = parts.get('src')
                dport = parts.get('dport')
                
                if src_ip and dport:
                    try:
                        # Validate port (optional but safer)
                        int(dport) 
                        key = f"{src_ip}:{dport}"
                        # Store only one entry per IP:PORT pair
                        if key not in connections:
                            connections[key] = line  
                    except ValueError:
                        continue
                
            return connections
        
        except TimeoutError:
            # Handle command timeout gracefully
            print("Error fetching conntrack data: Command timed out.")
            return {}
        except CalledProcessError as e:
            # Handle cases where grep finds no matches (return code 1) or other errors
            if e.returncode == 1:
                 return {} # No matching connections found, which is normal
            print(f"Error fetching conntrack data (Subprocess Error): {e}")
            return {}
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
                # Max connections ကို အနည်းဆုံး 1 ဖြစ်အောင် စစ်သည်။
                max_connections = max(1, user['concurrent_conn']) 
                user_port = str(user['port'] or LISTEN_FALLBACK)
                
                # Dictionary to map unique IPs connected to this user's port
                connected_ips = {} 

                # 1. Group connections by unique Source IP hitting the User's Port
                for conn_key in active_connections:
                    # The key format is "ClientIP:ServerPort"
                    if conn_key.endswith(f":{user_port}"):
                        try:
                            ip = conn_key.split(':')[0]
                            if ip not in connected_ips:
                                connected_ips[ip] = []
                            connected_ips[ip].append(conn_key)
                        except IndexError:
                            print(f"Warning: Skipping malformed connection key: {conn_key}")
                            continue
                
                num_unique_ips = len(connected_ips)

                # 2. Enforce the limit based on unique devices (Source IPs)
                if num_unique_ips > max_connections:
                    print(f"Limit Exceeded for {username} (Port {user_port}). IPs found: {num_unique_ips}, Max: {max_connections}")

                    # Determine which IPs to drop (Keep the first 'max_connections' found)
                    # This keeps the oldest/first connecting devices found by conntrack
                    ips_to_keep = list(connected_ips.keys())[:max_connections]
                    
                    for ip, conn_keys in connected_ips.items():
                        if ip not in ips_to_keep:
                            # This IP is an excess device. Drop ALL its connections.
                            print(f"  Dropping excess device IP: {ip} for user {username}")
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
            result = subprocess.run(
                f"conntrack -D -p udp --dport {port} --src {ip}",
                shell=True, capture_output=True, text=True
            )
            # Check for non-zero return code, unless it's the "not found" error
            if result.returncode != 0 and "not found" not in result.stderr:
                 print(f"conntrack -D failed for {connection_key}: {result.stderr.strip()}")

            print(f"Dropped connection: {connection_key}")
        except Exception as e:
            print(f"Error dropping connection {connection_key}: {e}")
            
    def start_monitoring(self):
        """Start the connection monitoring loop"""
        def monitor_loop():
            while True:
                try:
                    # Acquire lock to ensure thread safety during database/subprocess access
                    with self.lock:
                        self.enforce_connection_limits()
                    time.sleep(10)  # 10 စက္ကန့်တိုင်း စစ်ဆေးသည်။
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
