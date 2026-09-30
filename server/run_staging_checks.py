"""Run only against the named isolated staging database; never reads app data."""
import os
from pathlib import Path
import subprocess
import psycopg

secrets = dict(line.split('=',1) for line in Path('/home/phil_user/.config/linkedgames-telemetry-staging/postgres.env').read_text().splitlines())
os.environ['TELEMETRY_DATABASE_URL'] = 'postgresql://telemetry:'+secrets['POSTGRES_PASSWORD']+'@127.0.0.1:55439/telemetry'
with psycopg.connect(os.environ['TELEMETRY_DATABASE_URL']) as db:
    db.execute(Path('server/migrations/001_raw_events.sql').read_text())
raise SystemExit(subprocess.call(['.venv/bin/python','-m','pytest','server/tests','-q']))
