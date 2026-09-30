# Telemetry deployment — staging only

Inspected 2026-09-30: Ubuntu 22.04.5, 6 logical CPUs, 25 GiB RAM (~18 GiB
available), 345 GiB filesystem (211 GiB free), no swap. Shared workloads include
Nginx on 80/443, an existing PostgreSQL on 5432, Docker apps, PM2 apps and mail.
None was altered. Existing public PostgreSQL is unrelated to this deployment.

Isolated test database: `linkedgames-telemetry-staging-db`, PostgreSQL 16.10 image
sha256:21f6013073bc6b92830a2129570e2f5ec42a6c734b5a985a41e83aa58f54c3c1,
loopback 127.0.0.1:55439, dedicated volume `linkedgames-telemetry-staging-pg`.
Requested 512 MiB memory cap. CPU quota request rejected by host kernel; no CPU
isolation claim. Inspect effective limits before sustained load.

Secrets: `/home/phil_user/.config/linkedgames-telemetry-staging/postgres.env`,
mode 0600 inside 0700 directory, outside Git. Never put DSN/credentials in command
output or checked-in configuration. Collector reads TELEMETRY_DATABASE_URL.

Install `.venv/bin/pip install -r server/requirements.lock`. Run migrations with
psycopg as in `server/run_staging_checks.py`. That script truncates only test tables
and is for this isolated staging database. Run from repository root:
`.venv/bin/python server/run_staging_checks.py`.

Verified initial integration: concurrent identical submissions (16 requests / 8
workers) retain one raw row and 16 durable receipts; changed-content sequence
collision quarantines without overwrite; valid events in mixed batches commit;
unknown event schemas reject; out-of-order arrivals retain sequences; auth, token
rotation, body-size and checksum validation pass. This is not a sustained load test.

Provisional launch capacity: UNDECLARED pending representative payload and 30-minute
2x-peak tests. Production activation prohibited until central/local reconciliation,
real supported-Mac overhead, durable crash/retry, HTTPS and restore gates pass.
No end-to-end HTTPS deployment or off-host backup is claimed yet.

Production hostname and encrypted off-host backup destination requested from owner.
Use a separate PostgreSQL role for ingestion with INSERT/SELECT only on raw tables;
keep migrations/admin and read-only report roles separate. Require fsync=on and
synchronous_commit=on. Serve collector behind TLS and bound enrollment at the trusted
reverse proxy; never accept arbitrary X-Forwarded-For. Local test enrollment uses
socket address and 30/hour; proxy topology needs explicit trusted-address setup.

Recovery target: RPO <=1 hour, RTO <=4 hours. Hourly encrypted off-host pg_dump plus
WAL archival where configured; retain 24 hourly / 30 daily copies provisionally.
A local dump is only a drill artifact, not an off-host backup. Restore into a new
isolated database, verify receipt/event hashes and counts, then change endpoint.
Acknowledged data lost from server cannot be repaired by assuming client retention.

Retention target: raw 180 days, derived 365; validate storage projections first.
Do not deploy automatic deletes until retention manifests and frozen research
snapshot ownership are configured. Independent upload rollback retains local queue;
collector shutdown does not require any model/timing rollback.
