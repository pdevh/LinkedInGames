"""Wire validation independent of HTTP and PostgreSQL; never coerce unknowns."""
import hashlib
import json
import math
from datetime import datetime
from uuid import UUID


def digest(payload):
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()


def uuid(value):
    if not isinstance(value, str):
        raise ValueError('uuid')
    return str(UUID(value))


def validate(entry, installation):
    raw = entry['payload']
    if not isinstance(raw, str) or digest(raw) != entry['sha256']:
        raise ValueError('checksum')
    event = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite')))
    if event.get('schemaVersion') != 1:
        raise ValueError('unknownSchema')
    if uuid(event['installationID']) != installation:
        raise ValueError('identity')
    if uuid(event['eventID']) != uuid(entry['eventID']):
        raise ValueError('eventID')
    seq = event['sequence']
    if type(seq) is not int or not 0 < seq < 2**63 or seq != entry['sequence']:
        raise ValueError('sequence')
    for key in ('bootID', 'sessionID'):
        uuid(event[key])
    if event['serveID'] is not None:
        uuid(event['serveID'])
    if event['game'] not in ('zip', 'patches', 'system'):
        raise ValueError('game')
    if not isinstance(event['kind'], str) or not 1 <= len(event['kind']) <= 80:
        raise ValueError('kind')
    date = datetime.fromisoformat(event['createdAt'].replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise ValueError('timezone')
    mono = event['monotonicSeconds']
    if type(mono) not in (float, int) or not math.isfinite(mono) or mono < 0:
        raise ValueError('monotonic')
    consent = event['consent']
    if consent['status'] != 'active' or not consent['version']:
        raise ValueError('consent')
    if 'effectiveAt' not in consent:
        raise ValueError('consentEffectiveAt')
    required = {'app','build','os','architecture','feature','model','generator','timing','calibration','experiment','configHash'}
    if not required <= event['versions'].keys() or not isinstance(event['payload'], dict):
        raise ValueError('versionsOrPayload')
    return event
