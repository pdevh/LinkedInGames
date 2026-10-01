"""Snapshot-consistent local restore drill. Never drops the source database.

Run with python -m server.restore_drill. Default tools run inside the dedicated
staging container; TELEMETRY_PG_BIN selects matching native PostgreSQL tools.
This is NOT an encrypted off-host backup or production recovery verification.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from server.staging_settings import state_directory, staging_dsn


def database_digest(db):
    digest = hashlib.sha256()
    for table, order in (('raw_events', 'installation_id,event_id'),
                         ('receipts', 'id'), ('quarantine', 'id'),
                         ('installations', 'id'), ('schema_migrations', 'version')):
        rows = db.execute(sql.SQL('SELECT * FROM {} ORDER BY {}').format(
            sql.Identifier(table), sql.SQL(order))).fetchall()
        digest.update(table.encode())
        digest.update(json.dumps(rows, default=str, sort_keys=True, separators=(',', ':')).encode())
    return digest.hexdigest()


def main():
    state, dsn = state_directory(), staging_dsn()
    settings = conninfo_to_dict(dsn)
    local_bin = os.environ.get('TELEMETRY_PG_BIN')
    def command(tool, database, *arguments, **kwargs):
        if local_bin:
            env = dict(os.environ, PGHOST=settings['host'], PGPORT=settings['port'],
                       PGUSER=settings.get('user', 'telemetry'), PGDATABASE=database,
                       PGPASSWORD=settings.get('password', ''))
            cmd = [str(Path(local_bin) / tool), '-d', database, *arguments]
            return subprocess.run(cmd, env=env, check=True, **kwargs)
        cmd = ['docker', 'exec']
        if 'stdin' in kwargs:
            cmd.append('-i')
        cmd += ['linkedgames-telemetry-staging-db', tool, '-U', 'telemetry', '-d', database, *arguments]
        return subprocess.run(cmd, check=True, **kwargs)

    began = time.perf_counter()
    restored = 'linkedgames_restore_' + uuid4().hex
    backup = state / (restored + '.dump')
    created = False
    admin_dsn = make_conninfo(dsn, dbname='postgres')
    try:
        with psycopg.connect(dsn) as source:
            source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
            snapshot = source.execute('SELECT pg_export_snapshot()').fetchone()[0]
            before = database_digest(source)
            fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as output:
                command('pg_dump', settings['dbname'], '-Fc', '--snapshot=' + snapshot, stdout=output)
        with psycopg.connect(admin_dsn, autocommit=True) as admin:
            admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(restored)))
            created = True
        with backup.open('rb') as input_file:
            command('pg_restore', restored, '--exit-on-error', stdin=input_file)
        with psycopg.connect(make_conninfo(dsn, dbname=restored)) as recovered:
            if database_digest(recovered) != before:
                raise RuntimeError('Restore differs from frozen source snapshot; backup retained for diagnosis')
        elapsed = time.perf_counter() - began
        print(f'Local restore verified events, receipts, quarantine, credentials and migrations; {elapsed:.3f}s; {backup.stat().st_size} bytes')
        print('Off-host backup/RPO gate remains unverified.')
    finally:
        if created:
            with psycopg.connect(admin_dsn, autocommit=True) as admin:
                admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(restored)))


if __name__ == '__main__':
    main()
