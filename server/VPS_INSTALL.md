# Run this deployment on the VPS

The October 1 continuation ran in an isolated Debian cloud machine. It had no
`/phil_services` directory and no VPS SSH connection. **No VPS installation or
production changes were made in that continuation.** Earlier September 30 VPS
observations in `DEPLOYMENT.md` are historical records from the previous agent;
recheck them on the actual VPS before relying on them.

For fewer than five users, use one collector and one small PostgreSQL instance.
There is no queue broker, warehouse, fleet rollout, or sustained synthetic load
job. The first deployment is isolated staging. It does not activate app uploads,
change models, or make the release ready.

## Prerequisites and inspection

Run as the existing non-root deployment user on the VPS, with Git, Python 3.10+
and its venv support, Docker access, OpenSSL, curl, and a user systemd manager.
The user must be able to create the staging checkout under `/phil_services`.
Do not install or replace Docker, PostgreSQL, Nginx, certificates, or existing
applications just to run this script.

Before installation, inspect current resources and listeners:

```sh
uname -a
getconf _NPROCESSORS_ONLN
free -m
df -h /phil_services
docker ps --format '{{.Names}} {{.Ports}}'
ss -ltn
systemctl --user list-units --type=service
```

Do not dump environment variables, full Docker inspect output, or secret files.
Docker's full configuration contains database credentials.

Get the script from the implementation branch in an existing clean checkout, or
clone to a separate temporary checkout without disturbing prior work:

```sh
git clone --branch codex/dev-difficulty-telemetry --single-branch \
  https://github.com/pdevh/LinkedInGames.git /tmp/linkedgames-installer
bash /tmp/linkedgames-installer/server/install-vps.sh --check
bash /tmp/linkedgames-installer/server/install-vps.sh --install
```

`--check` is read-only. `--install` creates/refreshes:

| Resource | Default |
| --- | --- |
| Staging checkout | `/phil_services/linkedgames-telemetry-staging` |
| Secrets, TLS material, reports, drill dumps | `~/.config/linkedgames-telemetry-staging`, directory 0700 / secrets 0600 |
| PostgreSQL container | `linkedgames-telemetry-staging-db`, pinned PostgreSQL 16.10 image digest |
| Persistent database volume | `linkedgames-telemetry-staging-pg` |
| Database listener | `127.0.0.1:55439`, database `telemetry` |
| Database limits | 512 MiB container memory cap, 20 connections, 32 MiB shared buffers |
| Collector | `linkedgames-telemetry-staging.service` in user systemd, one Uvicorn worker |
| Collector listener | `127.0.0.1:8941`, locally trusted staging TLS |

The script validates origin and the plan ancestor, refuses dirty checkouts or a
different branch, and updates only by fast-forward. Existing unmanaged containers,
orphaned volumes, differing secret configuration, and differing service units
cause a stop for manual inspection. It never deletes their data, resets branches,
changes Nginx, or replaces production services. This conservative refusal is
intentional because the previous agent may already have deployed staging.

If defaults conflict with existing state, preserve it and inspect ownership,
image, listener and volume using selective Docker formatting. Do not simply
delete the existing volume. The current script does not automatically adopt the
previous agent's unlabelled container. An administrator must decide whether to
reuse that deployment or arrange a separate staging slot before continuing.

`TELEMETRY_VPS_CHECKOUT` and `TELEMETRY_STAGING_STATE` override checkout and external
state paths. Listener/container/volume names remain fixed to prevent accidentally
running destructive test helpers against a production database. Reuse the same
paths on subsequent invocations; never put secret state inside Git.

The staging certificate is valid for 30 days and has localhost/127.0.0.1 SANs.
Clients explicitly trust that certificate; TLS verification stays enabled. If
the pair is incomplete or expired, installation stops rather than overwriting it.
Rotate the staging pair explicitly while the collector is stopped, retaining
prior material securely until the replacement has passed checks.

## Verify, stop, and restart

```sh
bash /phil_services/linkedgames-telemetry-staging/server/install-vps.sh --verify
systemctl --user status linkedgames-telemetry-staging.service
journalctl --user -u linkedgames-telemetry-staging.service --since '1 hour ago'
```

`--verify` runs non-destructive protocol/report tests, then adds 100 synthetic
attempts across three installations over verified TLS, including out-of-order
delivery and deliberately ignored acknowledgments. It reconciles 300 source
event IDs and hashes, then performs a snapshot-consistent restore into a new
temporary database. Reports/fixtures and a 0600 dump remain outside Git. Only
the temporary restore database is dropped. Existing staging rows remain intact.
Synthetic protocol attempts are not complete native-client replay fixtures or
evidence that difficulty predictions improved.

The separate `server/run_staging_checks.py` integration runner **truncates test
tables**. Run it only against a disposable staging database with no data worth
keeping. Its safety check requires a loopback host, port 55439, and database
`telemetry`; the test fixture also requires `TELEMETRY_STAGING_RESET=1`, which
that explicit runner sets. Do not point it at existing user telemetry.

```sh
bash /phil_services/linkedgames-telemetry-staging/server/install-vps.sh --stop
systemctl --user start linkedgames-telemetry-staging.service
```

Stopping retains the database, credentials and artifacts. PostgreSQL uses Docker's
`unless-stopped` restart policy. For the collector to restart after a VPS reboot
without a login, check `loginctl show-user "$USER" -p Linger`; if disabled, a VPS
administrator can enable lingering for the deployment user. Verify a restart and
health response on the actual VPS; it has not been tested from this cloud task.

## Production activation remains separate

Do not repoint the app to this loopback staging service or overwrite the documented
production service at `/phil_services/linkedgames-telemetry`. Before production:

- Recheck the actual hostname/TLS/Nginx configuration and existing deployment.
- Use separate migration/admin, restricted ingestion, and read-only report roles.
  Staging deliberately uses its own database owner for migrations and restore tests;
  it is not a production-role template.
- Verify the Swift client's consent, persisted retries, complete pools/terminals,
  pre-verdict feedback and UI behavior on macOS, and reconcile real client fixtures.
- Configure encrypted off-host backups and actually restore one. The local dump
  drill does not establish off-host protection, hourly RPO, or four-hour RTO.
- Measure representative native payload/storage growth and app overhead. Keep
  optional algorithm changes disabled until their evidence gates pass.

For this user base, an internal trial with explicit integrity checks is more
useful than pretending that 5%/25% stages create meaningful cohorts. Record each
installation's activation and keep upload, feedback, timing and model rollback
independent. Do not claim a statistically reliable replacement model from a
handful of installations or activate one through this installer.

## Current validation, not VPS acceptance

In the October 1 cloud machine: pinned Python dependencies installed; collector
tests ran against isolated native PostgreSQL 17.11; 100 synthetic TLS attempts
reconciled all 300 IDs/hashes; snapshot-consistent restore matched events,
receipts, quarantine, installation credentials and migrations. See the current
acceptance ledger for exact test counts and timings.

The shell installer was syntax-checked and its missing-VPS guard was exercised.
Its Docker/PostgreSQL 16.10 and user-systemd installation path remains unexecuted
on the actual VPS. Docker Hub rate-limited the cloud pull; a mirror was denied,
so local tests used authoritative Debian packages with verified checksums.
macOS builds/UI and Actions status remain unverified; GitHub API access was denied.

## October 1 VPS continuation: preserved deployment and disposable checks

Current working checkout: `/phil_services/linkedgames-difficulty-dev`. Both required
handoff commits are ancestors. The older `/home/phil_user/LinkedInGames` checkout
has local work and remains untouched. The live collector remains at
`/phil_services/linkedgames-telemetry` on port 8942; the older staging collector
remains on 8941. The installer now reports the unmanaged staging container during
`--check`, before creating secrets or installing dependencies. Do not run
`--install` to bypass that refusal.

```sh
cd /phil_services/linkedgames-difficulty-dev
TELEMETRY_VPS_CHECKOUT="$PWD" bash server/install-vps.sh --check
```

For isolated checks without replacing the existing staging deployment, test helpers
also accept a **newly created** database named `telemetry_test_<32 lowercase hex
characters>` on the same loopback staging port 55439. Other database names, remote
hosts and production port 55440 remain refused. `TELEMETRY_STAGING_RESET=1` remains
required by destructive tests. The name guard cannot prove a database is disposable:
never reuse a database that contains telemetry worth keeping.

Create a new external state directory (0700), create a new database through the
existing staging administrator connection, and pass its DSN only in the child
process environment. Use `TELEMETRY_STAGING_STATE` for the new external directory
and `TELEMETRY_STAGING_HTTPS_PORT=8943` (check that it is free first). Then run, in
order, with those environment settings:

```sh
.venv/bin/python server/run_staging_checks.py
.venv/bin/python server/start_staging.py
.venv/bin/python -m server.staging_reconcile
.venv/bin/python -m server.restore_drill
```

The restore helper uses the existing staging container's matching PostgreSQL tools
but dumps only the explicitly selected disposable database. It drops only its own
new temporary restore database. The synthetic source database and external dump
remain available. Stop only the collector PID in the **new** state directory after
checking its working directory and listener. Never stop the older staging PID.

This run's retained evidence is under
`/home/phil_user/.config/linkedgames-difficulty-check-20261001`:
`database-name`, `reconciliation-events.jsonl`, `reconciliation-report.json`, and
a mode-0600 local restore dump. Its external `run.py` records the exact fresh-database
procedure, without embedding credentials. It creates a new database on every run;
8943 must be free before starting it. No existing tables were truncated.

### Client trial and rollback

Build and run native self-tests on macOS before distributing the app. Sharing is
opt-in through the application menu; turning it off stops new capture and future
requests, while retaining queued data. An already in-flight request can finish.
Upload is independently disabled unless `difficulty.telemetry.uploadEnabled` is
true and `difficulty.telemetry.endpoint` is an HTTPS URL in the app's defaults.
The menu explains that collection can remain local until upload is enabled.
Do not enable upload for a trial until the endpoint, consent and recovery checks
are accepted. The existing production endpoint was only health-checked here;
its running code was not upgraded.

Rollback: disable the upload preference or withdraw sharing consent; stop only a
new isolated collector. Retain progress JSON, its `.backup`, SQLite journal/WAL,
Keychain identity and server volumes. Feedback can be disabled separately in the
menu. No model, effort coefficient or timing policy was changed. Production
migration/restart and encrypted off-host backup configuration remain separate work;
the local restore drill does not establish off-host recovery or an RPO/RTO.
