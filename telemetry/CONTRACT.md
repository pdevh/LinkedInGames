# Difficulty telemetry protocol 1

Status: implementation contract; no production activation. JSON is UTF-8. UTC dates
use RFC3339; durations use monotonic seconds. Unknown historical values are null,
never inferred. All integer sequences are positive signed 64-bit values.

Each event has schemaVersion, eventID, installationID, sequence, bootID, sessionID,
serveID (nullable for installation events), game (zip/patches/system), kind,
createdAt, monotonicSeconds, consent {status,version,effectiveAt}, versions
{app,build,os,architecture,feature,model,generator,timing,calibration,experiment,
configHash}, and payload. Consent effectiveAt may be null. Only active supplied
consent permits capture/upload; user authorization does not fabricate past consent.

Wire batches carry batchID, installationID, schemaVersion=1, and events, where each
entry is {eventID,sequence,payload,sha256}. payload is the exact event JSON as a
string; sha256 hashes its UTF-8 bytes. This avoids cross-language float or dictionary
canonicalization differences. Batch checksum hashes concatenated lowercase event
hashes in array order. Limits: 500 entries, 512 KiB encoded/compressed transport,
4 MiB inflated JSON. HTTPS only outside local tests.

Receipts carry batchID, accepted [{eventID,sha256}], rejected
[{eventID,reason,retryable}], receivedAt. Only committed identical hashes may be
accepted. A batch retry may receive a new receipt timestamp. Different content at
an existing ID or sequence is quarantined. Unknown schemas are never acknowledged.
Client removes only exact ID/hash matches. Rejected data remains locally available.

A serve freezes full puzzle content, SHA256 content identity, all policy versions,
requested level, invitation assignment, clock epoch, selection and model state.
Candidate decisions declare expected candidate count and chunks, selected content
ID, qualification (true/false/null), intent, reason and generation timing. Each
candidate retains full content, eligibility/exclusion, raw/scaled features,
structural/unblended/blended estimates, probabilities/support and timing. Missing
chunks prohibit complete-pool claims. Terminal events freeze counters, effort,
verdict and snapshot before compatible JSON progress saves. Recovery reconciles by
serveID and terminal identity, not wall time.

Invited feedback state sequence: solved, feedbackPending, submitted|skipped,
verdictShown. Rating is optional ordinal 1..5 and never an effort label. All UI and
accessibility disclosure uses that state. Invitation decided before outcome, 25%,
max 3 displayed/session and 6/local day; missing/skipped/suppressed stay distinct.

Local SQLite transactions atomically append event and outbox under WAL/FULL.
Retention/overflow creates loss manifests; loss excludes complete-trace claims.
Server PostgreSQL commits raw events and receipts synchronously before responding.
Production activation, signed configuration, load, restore and macOS UI gates are
tracked independently in analysis/IMPLEMENTATION.md.
