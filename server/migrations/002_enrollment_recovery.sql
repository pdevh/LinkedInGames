BEGIN;
ALTER TABLE installations ADD COLUMN IF NOT EXISTS enrollment_key_hash text;
INSERT INTO schema_migrations(version) VALUES(2) ON CONFLICT DO NOTHING;
COMMIT;
