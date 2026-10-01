# Practical VPS continuation — 2026-10-01

Scope: fewer than five users. Ship focused client recovery/retry and optional
feedback improvements, with isolated VPS verification. The historical plan below
is context, not a release checklist. No root cause or finished difficulty fix is
claimed; effort coefficients and active selection/timing models are unchanged.

- **Implemented:** reused the prior unfinished consent/feedback integration;
  pre-verdict feedback gates in both games; answer/skip/stop/close handling;
  preserve post-terminal responses during recovery; recover without Keychain;
  reject incomplete/contradictory receipts before acknowledgments; persisted retry
  delays including enrollment Retry-After; drain acknowledged batches promptly.
- **Verified on this VPS:** full-history clean checkout and both required ancestors;
  31 backend/protocol/report/isolation tests passed, no skips; PostgreSQL 16.10;
  verified localhost TLS, 100 synthetic attempts / 300 exact event ID/hash matches,
  3 installations, 12 requests including ignored ACKs and out-of-order delivery;
  max receipt 0.137 seconds; local snapshot restore 0.681 seconds / 119,290 bytes.
  Synthetic candidate fixtures do not establish native payload capacity.
- **Preserved:** original dirty checkout, unmanaged staging container/volume and
  listener, live central service, all unrelated services. The temporary 8943
  collector was stopped after validation; 8941/8942 remain running. New test source database
  and artifacts retained outside Git. Installer --check now identifies unmanaged
  staging before making changes. Public HTTPS /health responded ready.
- **Native verified:** [macOS run 36909356739](https://github.com/pdevh/LinkedInGames/actions/runs/36909356739)
  passed at `af17e28` (the final Swift source): AppKit build, real sheet ordering,
  answer/skip/stop/close, recovery/retry, SIGKILL and existing gameplay regressions.
  The first run exposed an overlapping-access compiler error, fixed in that commit.
  Human VoiceOver/keyboard/visual acceptance remains unverified.
- **Deferred:** new statistical models, experiments, percentage rollout, generator
  redesign, exhaustive semantic tracing and research reporting. Existing candidate
  observations and policy versions are reused; complete capture is not claimed.
- **Unresolved:** encrypted off-host backup destination and restored backup;
  production deployment of this branch; real-device complete native-pool upload,
  401/413 network fault injection, disk-full persistence behavior and storage growth.
  Capture errors remain logged; the queue is not a complete-trace guarantee.

See `server/VPS_INSTALL.md` for the actual checkout, retained evidence, isolated
validation steps and rollback. Default upload remains independently disabled.

---

# Implementation acceptance ledger

## October 1 cloud continuation: deployment handoff

This continuation runs on isolated Debian Linux, not the VPS. `/phil_services`
is absent. September 30 VPS observations below are inherited historical evidence;
they were not reverified. The user instructed this continuation to supply an
installer/docs for execution on the VPS rather than deploy there from this host.

Origin verified, requested branch fetched explicitly, checkout fast-forwarded,
and `a350224fa2373bcc91df92188e43f2f24bdc05f4` confirmed ancestor of HEAD. Existing
tracked work was clean and preserved; no private historical audit is required.

| Requirement / change | Files | Current evidence | Status |
| --- | --- | --- | --- |
| Strict wire types / retryable database outages / schema-aware health | `server/collector/{protocol,app}.py`, `server/tests/test_{protocol,collector}.py` | 28 backend/protocol/report/safety tests passed, zero skipped, native isolated PostgreSQL 17.11 | implemented and locally verified |
| Portable isolated staging settings / prevent unintended truncation | `server/staging_settings.py`, test runner and helpers | refuse other hosts/ports/databases; external secret-path tests pass | implemented and locally verified |
| VPS staging install and startup instructions | `server/install-vps.sh`, `server/VPS_INSTALL.md` | shell syntax check passed; missing `/phil_services` guard refused execution as intended | implemented; real Docker/systemd install blocked until execution on VPS |
| TLS duplicate/lost-ACK reconciliation | `server/staging_reconcile.py` | 100 synthetic attempts, three installations, 300 exact central event ID/hash matches, 12 requests | locally verified protocol mechanics; full native-pool replay still pending |
| Snapshot-consistent local restore | `server/restore_drill.py` | frozen snapshot and restored events/receipts/quarantine/credentials/migrations matched; 0.161 seconds, 129,012-byte dump in first successful local drill | locally verified on PostgreSQL 17.11; VPS PostgreSQL 16.10 and encrypted off-host recovery unverified |

Cloud capacity only: five visible logical CPUs, ~33.3 GiB available RAM, ~30 GiB
free workspace disk. Native PostgreSQL used port 55439, 32 MiB shared buffers,
20 connections. TLS listener used port 8941 with explicitly trusted localhost
certificate. Secrets/dumps/fixtures stayed under `/workspace/linkedgames-staging`
outside Git. Docker Hub rate-limited the pinned image pull; the mirror was denied.
Authoritative Debian 17.11 package downloads were checked against repository
SHA-256 values. These cloud limits are not measured VPS limits or full-native
candidate payload capacity.

No broad activation milestone is complete. Mandatory client semantic capture,
native complete-pool replay, uploader crash/fault coverage, feedback presentation
and accessibility, honest UI metrics, versioned timing, generation cancellation/
budget behavior, forward-validation reports and independent rollback remain as
listed below. No fixed effort coefficient or production model changed here.
macOS build/UI checks remain unverified: this machine has no macOS SDK and the
GitHub Actions API returned Forbidden. Pushing will trigger the existing macOS
workflow, but its outcome must be checked before claiming native acceptance.

Handoff ETA: installer/docs are delivered now; VPS setup/reconciliation can run
when its operator executes the documented commands. A release ETA cannot be
revised responsibly before native/client gap validation and VPS results arrive.
The previous 23–37-day plan is historical estimation, not a commitment or
evidence of remaining progress. No root cause or completed algorithm fix is claimed.

## Inherited September 30 ledger

Updated 2026-09-30. Release is NOT READY. No root cause established. Fixed effort
coefficients remain unchanged. Synthetic evidence is not population evidence.

Repository: origin verified; clean checkout switched/fast-forwarded to
codex/dev-difficulty-telemetry; a350224fa2373bcc91df92188e43f2f24bdc05f4 is ancestor.
Historical private audit files are unavailable and are not prerequisites.

Status vocabulary: implemented = code exists; verified = named check passed;
deferred = intentionally gated optional work; blocked = external prerequisite;
pending = required work not yet finished. No partial milestone counts as complete.

| Requirement | Files | Acceptance evidence | Status |
|---|---|---|---|
| Contract / consent / versions | telemetry/CONTRACT.md | cross-language fixtures | implemented; tests pending |
| P01 WAL journal / outbox / terminal recovery | DifficultyJournal.swift | crash/checkpoint/reconcile | pending |
| P01 complete pools / semantic replay / timestamps | both controllers/models | 30 serves/game, 3 installs | pending |
| P04 discarded attempts / lower bounds | both controllers | exact counter replay | pending |
| P12 upload / identity / retries / overflow | client telemetry files | 401/413/429/503/lost ACK | pending |
| P12 PostgreSQL / HTTPS / credentials | server/ | 100-attempt reconciliation | pending |
| P12 operational capacity / backups | server/DEPLOYMENT.md | 30 min 2x peak; restore | pending |
| P03 exports / frozen forward validation | analysis/central/ | native parity / future leakage | pending |
| P13 daily quality / hypothesis reports | analysis/central/ | source-ID reconciliation | pending |
| P02 service status / exact denominators | DifficultyMetrics.swift / screens | cohort and switch fixtures | pending |
| P11 pre-verdict feedback / accessibility | coordinator / both games | macOS all presentation paths | pending |
| P07 monotonic clocks / epochs | ForegroundPlayClock.swift | foreground/background/sleep | pending |
| P10 selection / cancellation / budgets | both generators/models | uniqueness/deadline fixtures | pending |
| P14 signed flags / migration / rollback | configuration / CI | independent rollback fixtures | pending |
| macOS compilation / self-tests / UI | .github/workflows/ | hosted runner + UI evidence | pending |
| P05/P06 statistical replacements | unchanged production models | independent prospective evidence | deferred; shadow only |
| P08 trace/features, P09 exploration, P10 steering/buffers | gated | correctness/performance/evidence | deferred until gates pass |

Activation order: contract → durable client → collector/reports → feedback/status →
timing/generation → release checklist. Zero of six milestones complete initially.
Plan estimate remains 23–37 developer days plus production staging; revise using
measured acceptance progress. Off-host backup destination and human accessibility
verification are not yet established. Do not activate production collection on
synthetic tests alone.

## Evidence checkpoint 1

Implemented and pushed: versioned wire contract; WAL/FULL serialized Swift journal;
atomic event/outbox, exact-hash acknowledgments, idempotent terminals; initial
consent-aware controller hooks and JSON terminal recovery; Patches timestamps and
replacement skips; candidate decision capture; persisted HTTPS upload batches;
PostgreSQL raw migration, credential enrollment/rotation, mixed-batch quarantine,
durable receipts and local TLS staging; deterministic initial quality report.

Verified: macOS hosted Actions build and native tests at 47ff91e (run 36730928323),
including basic journal restart/rollback/hash checks. PostgreSQL tests initially
5 passed; 100-attempt protocol-only synthetic TLS reconciliation has 300 identical
central ID/hash rows, 3 installations, zero report gaps, max receipt 0.0712s.
Neither synthetic collector attempts nor native unit tests replace app UI acceptance.

Scale assumption: a handful of installations. Sustained synthetic throughput testing
is intentionally omitted; use short correctness/retry smoke tests and measure actual
payload/storage growth. A previously started 30-minute run was stopped after five
minutes and is not acceptance evidence.

Remaining core gaps: complete semantic hooks and session/visibility handling;
unknown-count interruption/loss manifests; measured bounded queue retention; true
full-pool native export/replay fixtures; uploader fault-injection coverage;
terminal failure propagation; snapshot ordering/migration edge cases; full report
metrics/forward baseline. Feedback, clocks, generation budgets and rollout controls
are still pending. Off-host destination/production hostname requested, not yet
configured. No broad milestone complete; estimate still 23–37 developer days.
