import pytest
from server.staging_settings import require_isolated, state_directory


@pytest.mark.parametrize('dsn', [
    'postgresql://localhost:5432/telemetry',
    'postgresql://example.com:55439/telemetry',
    'postgresql://127.0.0.1:55439/production',
])
def test_destructive_tests_refuse_other_databases(dsn):
    with pytest.raises(RuntimeError):
        require_isolated(dsn)


def test_staging_secrets_cannot_be_in_checkout(monkeypatch):
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    monkeypatch.setenv('TELEMETRY_STAGING_STATE', str(root / '.build/staging'))
    with pytest.raises(RuntimeError):
        state_directory()


def test_explicit_external_state_is_reusable(monkeypatch, tmp_path):
    monkeypatch.setenv('TELEMETRY_STAGING_STATE', str(tmp_path))
    assert state_directory() == tmp_path.resolve()
