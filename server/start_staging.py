"""Local TLS staging only. Secrets and logs stay outside the checkout."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
state = Path.home()/'.config/linkedgames-telemetry-staging'
state.mkdir(mode=0o700,parents=True,exist_ok=True)
values = dict(line.split('=',1) for line in (state/'postgres.env').read_text().splitlines())
env = dict(os.environ,TELEMETRY_DATABASE_URL='postgresql://telemetry:'+values['POSTGRES_PASSWORD']+'@127.0.0.1:55439/telemetry')
key, cert = state/'tls.key', state/'tls.crt'
if not key.exists():
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),
                    '-days','30','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    key.chmod(0o600)
with (state/'collector.log').open('ab') as log:
    child = subprocess.Popen([str(root/'.venv/bin/python'),'-m','uvicorn','server.collector.app:app','--host','127.0.0.1','--port','8941',
                              '--ssl-keyfile',str(key),'--ssl-certfile',str(cert),'--no-access-log'],cwd=root,env=env,
                              stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
(state/'collector.pid').write_text(str(child.pid))
print('Started isolated TLS staging on https://localhost:8941; PID',child.pid)
