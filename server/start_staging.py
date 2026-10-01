"""Local TLS staging only. Secrets and logs stay outside the checkout."""
import os
from pathlib import Path
import subprocess
import sys
import socket

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root))
from server.staging_settings import state_directory, staging_dsn
state = state_directory()
state.mkdir(mode=0o700,parents=True,exist_ok=True)
env = dict(os.environ,TELEMETRY_DATABASE_URL=staging_dsn())
with socket.socket() as listener:
    try:
        listener.bind(('127.0.0.1', 8941))
    except OSError:
        raise SystemExit('Staging port 8941 is occupied; preserve the existing listener and PID file')
key, cert = state/'tls.key', state/'tls.crt'
if not key.exists():
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),
                    '-days','30','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    key.chmod(0o600)
with (state/'collector.log').open('ab') as log:
    child = subprocess.Popen([sys.executable,'-m','uvicorn','server.collector.app:app','--host','127.0.0.1','--port','8941',
                              '--ssl-keyfile',str(key),'--ssl-certfile',str(cert),'--no-access-log'],cwd=root,env=env,
                              stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
(state/'collector.pid').write_text(str(child.pid))
print('Started isolated TLS staging on https://localhost:8941; PID',child.pid)
