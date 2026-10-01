"""Run only against the named isolated staging database; never reads app data."""
import os
from pathlib import Path
import subprocess
import sys
import psycopg
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from server.staging_settings import staging_dsn

os.chdir(Path(__file__).resolve().parent.parent)
os.environ['TELEMETRY_DATABASE_URL'] = staging_dsn()
os.environ['TELEMETRY_STAGING_RESET'] = '1'
with psycopg.connect(os.environ['TELEMETRY_DATABASE_URL']) as db:
    for migration in sorted(Path('server/migrations').glob('*.sql')):
        db.execute(migration.read_text())
raise SystemExit(subprocess.call([sys.executable,'-m','pytest','server/tests','-q']))
