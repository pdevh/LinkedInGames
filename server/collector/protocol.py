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


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError('timestamp')
    date = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise ValueError('timezone')
    return date


def validate(entry, installation):
    raw = entry['payload']
    if not isinstance(raw, str) or digest(raw) != entry['sha256']:
        raise ValueError('checksum')
    event = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite')))
    if type(event.get('schemaVersion')) is not int or event['schemaVersion'] != 1:
        raise ValueError('unknownSchema')
    if uuid(event['installationID']) != installation:
        raise ValueError('identity')
    if uuid(event['eventID']) != uuid(entry['eventID']):
        raise ValueError('eventID')
    seq = event['sequence']
    if type(seq) is not int or type(entry['sequence']) is not int or not 0 < seq < 2**63 or seq != entry['sequence']:
        raise ValueError('sequence')
    for key in ('bootID', 'sessionID'):
        uuid(event[key])
    if event['serveID'] is not None:
        uuid(event['serveID'])
    if event['game'] not in ('zip', 'patches', 'system'):
        raise ValueError('game')
    if not isinstance(event['kind'], str) or not 1 <= len(event['kind']) <= 80:
        raise ValueError('kind')
    timestamp(event['createdAt'])
    mono = event['monotonicSeconds']
    if type(mono) not in (float, int) or not math.isfinite(mono) or mono < 0:
        raise ValueError('monotonic')
    consent = event['consent']
    if not isinstance(consent, dict) or consent['status'] != 'active' or not isinstance(consent['version'], str) or not 1 <= len(consent['version']) <= 80:
        raise ValueError('consent')
    if 'effectiveAt' not in consent:
        raise ValueError('consentEffectiveAt')
    if consent['effectiveAt'] is not None:
        timestamp(consent['effectiveAt'])
    required = {'app','build','os','architecture','feature','model','generator','timing','calibration','experiment','configHash'}
    versions = event['versions']
    if not isinstance(versions, dict) or not required <= versions.keys() or not isinstance(event['payload'], dict):
        raise ValueError('versionsOrPayload')
    if any(type(versions[key]) not in (int, str) or versions[key] == '' for key in required):
        raise ValueError('versionValue')
    return event
