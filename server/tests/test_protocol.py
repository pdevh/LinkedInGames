"""Malformed client records must be quarantined, never coerced into valid data."""
import json
from uuid import uuid4

import pytest

from server.collector.protocol import digest, validate
from server.tests.test_collector import event


@pytest.mark.parametrize('changes', [
    {'schemaVersion': True}, {'sequence': True}, {'sequence': 2**63},
    {'monotonicSeconds': True}, {'monotonicSeconds': -1},
    {'createdAt': '2026-10-01T10:00:00'},
    {'consent': {'status': 'active', 'version': 7, 'effectiveAt': None}},
    {'consent': {'status': 'active', 'version': 'v1', 'effectiveAt': 'unknown'}},
    {'versions': []}, {'payload': []},
])
def test_invalid_wire_fields(changes):
    installation = str(uuid4())
    entry = event(installation, **changes)
    with pytest.raises((ValueError, TypeError)):
        validate(entry, installation)


def test_unknown_consent_date_is_preserved():
    installation = str(uuid4())
    assert validate(event(installation), installation)['consent']['effectiveAt'] is None


def test_envelope_sequence_cannot_be_boolean():
    installation = str(uuid4())
    entry = event(installation)
    entry['sequence'] = True
    with pytest.raises(ValueError):
        validate(entry, installation)


def test_nonfinite_json_is_rejected_even_with_matching_hash():
    installation = str(uuid4())
    entry = event(installation)
    value = json.loads(entry['payload'])
    value['payload']['duration'] = float('nan')
    entry['payload'] = json.dumps(value)
    entry['sha256'] = digest(entry['payload'])
    with pytest.raises(ValueError):
        validate(entry, installation)
