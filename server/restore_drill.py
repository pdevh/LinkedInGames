"""Local restore drill, not an off-host backup. Uses the isolated named container."""
import hashlib
from pathlib import Path
import subprocess
import time

state = Path.home()/'.config/linkedgames-telemetry-staging'
container = 'linkedgames-telemetry-staging-db'

def command(*args, **kwargs):
    return subprocess.run(['docker','exec',container,*args],check=True,**kwargs)

def hashes(database):
    result = command('psql','-U','telemetry','-d',database,'-Atc',
       "SELECT installation_id::text||event_id::text||sha256 FROM raw_events ORDER BY installation_id,event_id",capture_output=True)
    receipts = command('psql','-U','telemetry','-d',database,'-Atc',
       "SELECT body::text FROM receipts ORDER BY id",capture_output=True)
    return hashlib.sha256(result.stdout+receipts.stdout).hexdigest()

before = hashes('telemetry'); began = time.perf_counter()
backup = state/'restore-drill.dump'
with backup.open('wb') as output:
    command('pg_dump','-U','telemetry','-d','telemetry','-Fc',stdout=output)
backup.chmod(0o600)
# A new database name ensures the drill cannot drop the live test database.
restored = 'restore_'+str(int(time.time()))
command('createdb','-U','telemetry',restored)
with backup.open('rb') as source:
    subprocess.run(['docker','exec','-i',container,'pg_restore','-U','telemetry','-d',restored,'--exit-on-error'],stdin=source,check=True)
assert hashes(restored) == before
elapsed = time.perf_counter()-began
print(f'Local restore verified raw-event and receipt digest {before}; {elapsed:.3f}s; {backup.stat().st_size} bytes')
command('dropdb','-U','telemetry',restored)
