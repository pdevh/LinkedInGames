#!/usr/bin/env bash
# Run on the VPS as its deployment user. Default is a read-only prerequisite check.
set -euo pipefail
umask 077

mode=${1:---check}
case "$mode" in --check|--install|--verify|--stop) ;; *)
    printf 'Usage: %s [--check|--install|--verify|--stop]\n' "$0" >&2; exit 2;; esac

checkout=${TELEMETRY_VPS_CHECKOUT:-/phil_services/linkedgames-telemetry-staging}
state=${TELEMETRY_STAGING_STATE:-${HOME}/.config/linkedgames-telemetry-staging}
container=linkedgames-telemetry-staging-db
volume=linkedgames-telemetry-staging-pg
image=postgres:16.10@sha256:21f6013073bc6b92830a2129570e2f5ec42a6c734b5a985a41e83aa58f54c3c1
origin=https://github.com/pdevh/LinkedInGames.git
branch=codex/dev-difficulty-telemetry
unit=linkedgames-telemetry-staging.service

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $(id -u) != 0 ]] || fail 'Run as the deployment user, not root.'
for tool in git python3 docker openssl systemctl curl; do
    command -v "$tool" >/dev/null || fail "Missing prerequisite: $tool"
done
[[ -d /phil_services ]] || fail '/phil_services is absent; this script must run on the VPS.'
docker info >/dev/null 2>&1 || fail 'Deployment user cannot access Docker.'
systemctl --user show-environment >/dev/null 2>&1 || fail 'User systemd manager is unavailable.'
[[ $checkout = /* && $state = /* ]] || fail 'Use absolute checkout and state paths.'
export TELEMETRY_STAGING_STATE="$state"

if [[ $mode = --check ]]; then
    printf 'Prerequisites found. Target checkout: %s\nExternal state: %s\n' "$checkout" "$state"
    if docker container inspect "$container" >/dev/null 2>&1; then
        [[ $(docker inspect -f '{{index .Config.Labels "linkedgames.scope"}}' "$container") = staging ]] || fail 'Existing staging container is unmanaged. Preserve it; use a disposable test database and a separate localhost HTTPS port (see VPS_INSTALL.md).'
    elif docker volume inspect "$volume" >/dev/null 2>&1; then
        fail 'Existing staging volume requires manual review; no data changed.'
    fi
    printf 'Staging only: PostgreSQL 127.0.0.1:55439; HTTPS 127.0.0.1:8941. No VPS changes made.\n'
    exit 0
fi

if [[ $mode = --stop ]]; then
    systemctl --user stop "$unit"
    # Leave PostgreSQL and its data intact. Do not stop an unverified existing container.
    printf 'Stopped staging collector; database, queue, credentials and backups retained.\n'
    exit 0
fi

if [[ $mode = --install ]]; then
    if [[ -d $checkout/.git ]]; then
        [[ $(git -C "$checkout" remote get-url origin) = "$origin" ]] || fail 'Existing checkout has a different origin.'
        [[ -z $(git -C "$checkout" status --porcelain) ]] || fail 'Existing checkout has local work; preserve it and resolve separately.'
        [[ $(git -C "$checkout" branch --show-current) = "$branch" ]] || fail 'Existing checkout is on another branch; refusing to switch it.'
        git -C "$checkout" fetch origin "$branch"
        git -C "$checkout" merge --ff-only FETCH_HEAD
    elif [[ -e $checkout ]]; then
        fail 'Target exists without a Git checkout; refusing to overwrite it.'
    else
        git clone --branch "$branch" --single-branch "$origin" "$checkout"
    fi
    git -C "$checkout" merge-base --is-ancestor a350224fa2373bcc91df92188e43f2f24bdc05f4 HEAD || fail 'Required plan commit is absent.'

    # State is deliberately external to Git. Reuse existing secrets; never print them.
    python3 - "$checkout" "$state" <<'PY'
import os, secrets, sys
from pathlib import Path
from urllib.parse import quote
root = Path(sys.argv[1]).resolve()
state = Path(sys.argv[2])
if state.is_symlink():
    raise SystemExit('State directory must not be a symlink')
state = state.resolve()
if state == root or root in state.parents:
    raise SystemExit('Secret state must be outside the checkout')
state.mkdir(mode=0o700, parents=True, exist_ok=True)
if state.is_symlink() or state.stat().st_uid != os.getuid():
    raise SystemExit('State directory must belong to the deployment user')
state.chmod(0o700)
postgres = state / 'postgres.env'
if not postgres.exists():
    with postgres.open('x') as f:
        f.write('POSTGRES_USER=telemetry\nPOSTGRES_DB=telemetry\nPOSTGRES_PASSWORD=' + secrets.token_urlsafe(32) + '\n')
if postgres.is_symlink() or postgres.stat().st_uid != os.getuid():
    raise SystemExit('Unsafe PostgreSQL secret file ownership')
postgres.chmod(0o600)
values = dict(line.split('=', 1) for line in postgres.read_text().splitlines() if line)
password = values.get('POSTGRES_PASSWORD')
if not password or values.get('POSTGRES_USER', 'telemetry') != 'telemetry' or values.get('POSTGRES_DB', 'telemetry') != 'telemetry':
    raise SystemExit('Existing PostgreSQL settings differ; manual review required')
collector = state / 'collector.env'
if collector.exists() and (collector.is_symlink() or collector.stat().st_uid != os.getuid()):
    raise SystemExit('Unsafe collector secret file ownership')
contents = 'TELEMETRY_DATABASE_URL=postgresql://telemetry:' + quote(password, safe='') + '@127.0.0.1:55439/telemetry\n'
if collector.exists() and collector.read_text() != contents:
    raise SystemExit('Existing collector settings differ; preserve them and review manually')
if not collector.exists():
    collector.write_text(contents)
collector.chmod(0o600)
PY
    python3 -m venv "$checkout/.venv"
    "$checkout/.venv/bin/python" -m pip install --disable-pip-version-check -r "$checkout/server/requirements.lock"

    if docker container inspect "$container" >/dev/null 2>&1; then
        [[ $(docker inspect -f '{{index .Config.Labels "linkedgames.scope"}}' "$container") = staging ]] || fail 'Existing staging container is unmanaged by this script; inspect it before adopting or choose a separate deployment.'
        [[ $(docker inspect -f '{{.Config.Image}}' "$container") = "$image" ]] || fail 'Existing staging container image differs.'
        [[ $(docker port "$container" 5432/tcp) = 127.0.0.1:55439 ]] || fail 'Existing staging database port binding differs.'
        docker start "$container" >/dev/null
    else
        # A pre-existing named volume may hold an earlier deployment. Never assume its password or reuse it blindly.
        ! docker volume inspect "$volume" >/dev/null 2>&1 || fail 'Existing staging volume requires manual review; no data changed.'
        docker pull "$image"
        docker volume create --label linkedgames.scope=staging "$volume" >/dev/null
        docker run -d --name "$container" --label linkedgames.scope=staging \
            --restart unless-stopped --memory 512m --publish 127.0.0.1:55439:5432 \
            --env-file "$state/postgres.env" --mount "type=volume,source=$volume,target=/var/lib/postgresql/data" \
            "$image" -c max_connections=20 -c shared_buffers=32MB >/dev/null
    fi
    ready=false
    for attempt in {1..30}; do
        if docker exec "$container" pg_isready -U telemetry -d telemetry >/dev/null 2>&1; then ready=true; break; fi
        sleep 1
    done
    $ready || fail 'PostgreSQL failed to become ready; inspect the staging container log.'
    (
        cd "$checkout"
        .venv/bin/python - <<'PY'
from pathlib import Path
import psycopg
from server.staging_settings import staging_dsn
with psycopg.connect(staging_dsn()) as db:
    for migration in sorted(Path('server/migrations').glob('*.sql')):
        db.execute(migration.read_text())
PY
    )
    if [[ ! -e $state/tls.key && ! -e $state/tls.crt ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -keyout "$state/tls.key" -out "$state/tls.crt" \
            -days 30 -subj /CN=localhost -addext subjectAltName=DNS:localhost,IP:127.0.0.1 >/dev/null 2>&1
    fi
    [[ -f $state/tls.key && -f $state/tls.crt ]] || fail 'Incomplete staging TLS pair; refusing to overwrite keys.'
    chmod 600 "$state/tls.key"
    openssl x509 -checkend 0 -noout -in "$state/tls.crt" >/dev/null || fail 'Staging certificate expired; rotate it explicitly before continuing.'
    mkdir -p "${HOME}/.config/systemd/user"
    python3 - "$checkout" "$state" "${HOME}/.config/systemd/user/$unit" <<'PY'
from pathlib import Path
import sys
root, state, output = sys.argv[1:]
def q(value):
    if '\n' in value or '\r' in value:
        raise SystemExit('Newlines are not valid deployment paths')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%') + '"'
text = f'''[Unit]
Description=LinkedInGames isolated staging collector
After=network-online.target

[Service]
WorkingDirectory={q(root)}
EnvironmentFile={q(state + '/collector.env')}
ExecStart={q(root + '/.venv/bin/python')} -m uvicorn server.collector.app:app --host 127.0.0.1 --port 8941 --ssl-keyfile {q(state + '/tls.key')} --ssl-certfile {q(state + '/tls.crt')} --no-access-log
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
'''
path = Path(output)
if path.exists() and path.read_text() != text:
    raise SystemExit('Existing staging unit differs; preserve it and review changes manually')
path.write_text(text)
PY
    systemctl --user daemon-reload
    systemctl --user enable "$unit"
    systemctl --user restart "$unit"
fi

[[ -d $checkout/.git && -x $checkout/.venv/bin/python ]] || fail 'Run --install first.'
curl --fail --silent --show-error --retry 10 --retry-connrefused --retry-delay 1 \
    --cacert "$state/tls.crt" https://localhost:8941/health
printf '\n'
if [[ $mode = --verify ]]; then
    cd "$checkout"
    .venv/bin/python -m pytest server/tests/test_protocol.py server/tests/test_report.py -q
    .venv/bin/python -m server.staging_reconcile
    .venv/bin/python -m server.restore_drill
fi
printf 'Staging configured. No production endpoint, Nginx route, or off-host backup was changed.\n'
