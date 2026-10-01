"""Explicit isolated test settings; credentials never appear in diagnostics."""
import os
from pathlib import Path
from urllib.parse import quote

from psycopg.conninfo import conninfo_to_dict


def state_directory():
    state = Path(os.environ.get('TELEMETRY_STAGING_STATE',
                    str(Path.home() / '.config/linkedgames-telemetry-staging'))).resolve()
    root = Path(__file__).resolve().parent.parent
    if state == root or root in state.parents:
        raise RuntimeError('Staging secrets must be outside the checkout')
    return state


def staging_dsn():
    supplied = os.environ.get('TELEMETRY_DATABASE_URL')
    if supplied:
        dsn = supplied
    else:
        values = dict(line.split('=', 1) for line in
                      (state_directory() / 'postgres.env').read_text().splitlines())
        dsn = 'postgresql://telemetry:' + quote(values['POSTGRES_PASSWORD'], safe='') + '@127.0.0.1:55439/telemetry'
    require_isolated(dsn)
    return dsn


def require_isolated(dsn):
    settings = conninfo_to_dict(dsn)
    if (settings.get('host') not in ('localhost', '127.0.0.1', '::1')
            or settings.get('port') != '55439'
            or settings.get('dbname') != 'telemetry'):
        raise RuntimeError('Refusing destructive tests outside loopback staging port 55439/database telemetry')
