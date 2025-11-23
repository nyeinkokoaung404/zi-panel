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

# Setup logging with proper file handling
log_dir = "/var/log/zivpn"
os.makedirs(log_dir, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'{log_dir}/connection_manager.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger('ZIVPNConnectionManager')

class ConnectionManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.logger = logger

    def get_db(self):
        try:
            conn = sqlite3.connect(DATABASE_PATH)
            conn.row_factory = sqlite3.Row
            return conn
        except Exception as e:
            self.logger.error(f"Database connection failed: {e}")
            raise

    def get_active_connections(self):
        """Get active UDP connections using conntrack"""
        try:
            # More reliable conntrack command
            cmd = "conntrack -L -p udp 2>/dev/null | grep -E 'dport=(5667|[6-9][0-9]{3}|[1-9][0-9]{4})' | grep -v src=127.0.0.1"
            
            self.logger.debug("Executing conntrack command...")
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
            
            if result.returncode != 0:
                self.logger.warning(f"Conntrack command failed: {result.stderr}")
                return {}
            
            connections = {}
            for line in result.stdout.split('\n'):
                line = line.strip()
                if not line or 'src=' not in line or 'dport=' not in line:
                    continue
                    
                try:
                    # Parse connection info
                    src_ip = None
                    dport = None
                    
                    for part in line.split():
                        if part.startswith('src='):
                            src_ip = part.split('=')[1]
                        elif part.startswith('dport='):
                            dport = part.split('=')[1]
                    
                    if src_ip and dport and dport.isdigit():
                        key = f"{src_ip}:{dport}"
                        connections[key] = {
                            'src_ip': src_ip,
                            'dport': dport,
                            'raw': line
                        }
                        self.logger.debug(f"Found connection: {key}")
                        
                except Exception as e:
                    self.logger.debug(f"Failed to parse line: {line} - Error: {e}")
                    continue
            
            self.logger.info(f"Total active connections found: {len(connections)}")
            return connections
            
        except subprocess.TimeoutExpired:
            self.logger.error("Conntrack command timed out")
            return {}
        except Exception as e:
            self.logger.error(f"Error getting active connections: {e}")
            return {}

    def enforce_connection_limits(self):
        """Enforce connection limits for all active users"""
        db = self.get_db()
        try:
            # Get active users with their limits
            users = db.execute('''
                SELECT username, concurrent_conn, port 
                FROM users 
                WHERE status = "active" AND (expires IS NULL OR expires >= date('now'))
            ''').fetchall()
            
            if not users:
                self.logger.info("No active users found")
                return
                
            active_connections = self.get_active_connections()
            self.logger.info(f"Checking {len(users)} users against {len(active_connections)} connections")
            
            total_dropped = 0
            
            for user in users:
                username = user['username']
                max_conn = int(user['concurrent_conn'])
                user_port = str(user['port'] or LISTEN_FALLBACK)
                
                self.logger.debug(f"Checking user: {username}, port: {user_port}, max: {max_conn}")
                
                # Find connections for this user's port
                user_conns = {}
                for conn_key, conn_info in active_connections.items():
                    if conn_info['dport'] == user_port:
                        ip = conn_info['src_ip']
                        if ip not in user_conns:
                            user_conns[ip] = []
                        user_conns[ip].append(conn_key)
                
                current_conns = len(user_conns)
                self.logger.info(f"User {username} has {current_conns} unique IPs (max: {max_conn})")
                
                # Enforce limit if exceeded
                if current_conns > max_conn:
                    self.logger.warning(f"User {username} exceeded limit: {current_conns} > {max_conn}")
                    
                    # Keep first max_conn IPs, drop the rest
                    ips_to_keep = list(user_conns.keys())[:max_conn]
                    ips_to_drop = list(user_conns.keys())[max_conn:]
                    
                    for ip in ips_to_drop:
                        self.logger.info(f"Dropping connections from {ip} for user {username}")
                        for conn_key in user_conns[ip]:
                            if self.drop_connection(conn_key):
                                total_dropped += 1
                
            if total_dropped > 0:
                self.logger.info(f"Total connections dropped: {total_dropped}")
                
        except Exception as e:
            self.logger.error(f"Error in connection limit enforcement: {e}")
        finally:
            db.close()

    def drop_connection(self, connection_key):
        """Drop a specific connection"""
        try:
            ip, port = connection_key.split(':')
            
            # Multiple methods to ensure connection is dropped
            commands = [
                f"conntrack -D -p udp --dport {port} --orig-src {ip}",
                f"conntrack -D -p udp --dport {port} --src {ip}",
            ]
            
            for cmd in commands:
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    self.logger.info(f"Successfully dropped: {connection_key}")
                    return True
            
            self.logger.warning(f"Failed to drop: {connection_key}")
            return False
            
        except Exception as e:
            self.logger.error(f"Error dropping connection {connection_key}: {e}")
            return False

    def start_monitoring(self):
        """Start monitoring loop"""
        def monitor_loop():
            self.logger.info("Connection monitoring started")
            while True:
                try:
                    self.enforce_connection_limits()
                    time.sleep(10)  # Check every 10 seconds
                except Exception as e:
                    self.logger.error(f"Monitoring loop error: {e}")
                    time.sleep(30)  # Wait longer on error
                    
        monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
        monitor_thread.start()
        return monitor_thread

# Global instance
connection_manager = ConnectionManager()

if __name__ == "__main__":
    logger.info("=== Starting ZIVPN Connection Manager ===")
    
    # Test database connection
    try:
        db = connection_manager.get_db()
        users = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        logger.info(f"Database connected. Total users: {users}")
        db.close()
    except Exception as e:
        logger.error(f"Database test failed: {e}")
        exit(1)
    
    # Test conntrack
    try:
        test_conns = connection_manager.get_active_connections()
        logger.info(f"Conntrack test successful. Found {len(test_conns)} connections")
    except Exception as e:
        logger.error(f"Conntrack test failed: {e}")
    
    # Start monitoring
    monitor_thread = connection_manager.start_monitoring()
    
    try:
        logger.info("Connection Manager is running. Press Ctrl+C to stop.")
        while True:
            time.sleep(60)
            logger.debug("Connection Manager heartbeat")
    except KeyboardInterrupt:
        logger.info("Received interrupt signal. Shutting down...")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        logger.info("Connection Manager stopped")
