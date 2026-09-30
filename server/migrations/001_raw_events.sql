BEGIN;
CREATE TABLE IF NOT EXISTS schema_migrations(version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS installations(
 id uuid PRIMARY KEY, credential_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 disabled boolean NOT NULL DEFAULT false);
CREATE TABLE IF NOT EXISTS raw_events(
 installation_id uuid NOT NULL REFERENCES installations(id), event_id uuid NOT NULL,
 sequence bigint NOT NULL CHECK(sequence>0), sha256 text NOT NULL CHECK(length(sha256)=64),
 payload text NOT NULL, game text NOT NULL, kind text NOT NULL, serve_id uuid,
 created_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(installation_id,event_id), UNIQUE(installation_id,sequence));
CREATE INDEX IF NOT EXISTS raw_serve ON raw_events(installation_id,serve_id);
CREATE INDEX IF NOT EXISTS raw_time ON raw_events(game,created_at);
CREATE TABLE IF NOT EXISTS receipts(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, installation_id uuid NOT NULL REFERENCES installations(id),
 batch_id uuid NOT NULL, body jsonb NOT NULL, received_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS quarantine(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, installation_id uuid NOT NULL REFERENCES installations(id),
 event_id text, reason text NOT NULL, sha256 text, payload text,
 received_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS enrollment_limits(
 address_hash text PRIMARY KEY, window_start timestamptz NOT NULL, count integer NOT NULL);
INSERT INTO schema_migrations(version) VALUES(1) ON CONFLICT DO NOTHING;
COMMIT;
