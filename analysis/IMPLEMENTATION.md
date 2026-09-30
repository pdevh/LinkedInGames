# Implementation acceptance ledger

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
