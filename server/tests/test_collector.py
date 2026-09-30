import concurrent.futures
import json
import os
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient
from server.collector.app import app
from server.collector.protocol import digest


@pytest.fixture
def client():
    if 'TELEMETRY_DATABASE_URL' not in os.environ:
        pytest.skip('isolated PostgreSQL required')
    with psycopg.connect(os.environ['TELEMETRY_DATABASE_URL']) as db:
        db.execute('TRUNCATE receipts,quarantine,raw_events,installations,enrollment_limits RESTART IDENTITY CASCADE')
    return TestClient(app)


def enroll(client):
    installation = str(uuid4())
    response = client.post('/v1/installations',json={'installationID':installation})
    assert response.status_code == 200
    return installation, {'Authorization':'Bearer '+response.json()['credential']}


def event(installation, sequence=1, **overrides):
    value = dict(schemaVersion=1,eventID=str(uuid4()),installationID=installation,sequence=sequence,
                 bootID=str(uuid4()),sessionID=str(uuid4()),serveID=str(uuid4()),game='patches',kind='solve',
                 createdAt='2026-09-30T10:00:00Z',monotonicSeconds=100.0,
                 consent={'status':'active','version':'test','effectiveAt':None},
                 versions={k:'test' for k in ['app','build','os','architecture','feature','model','generator','timing','calibration','experiment','configHash']},
                 payload={'fixture':True})
    value.update(overrides)
    raw = json.dumps(value,separators=(',',':'))
    return dict(eventID=value['eventID'],sequence=sequence,payload=raw,sha256=digest(raw))


def batch(installation, entries):
    return dict(batchID=str(uuid4()),installationID=installation,schemaVersion=1,events=entries,
                checksum=digest(''.join(e['sha256'] for e in entries)))


def test_durable_retry_and_concurrent_duplicate(client):
    installation, headers = enroll(client)
    data = batch(installation,[event(installation)])
    def post(_):
        response = client.post('/v1/events/batch',json=data,headers=headers)
        assert response.status_code == 200, response.text
        assert len(response.json()['accepted']) == 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(post,range(16)))
    with psycopg.connect(os.environ['TELEMETRY_DATABASE_URL']) as db:
        assert db.execute('SELECT count(*) FROM raw_events').fetchone()[0] == 1
        assert db.execute('SELECT count(*) FROM receipts').fetchone()[0] == 16


def test_mixed_quarantine_no_overwrite(client):
    installation, headers = enroll(client)
    original = event(installation)
    assert client.post('/v1/events/batch',json=batch(installation,[original]),headers=headers).status_code == 200
    entries = [event(installation),event(installation,2),event(installation,3,schemaVersion=99)]
    response = client.post('/v1/events/batch',json=batch(installation,entries),headers=headers).json()
    assert len(response['accepted']) == 1 and len(response['rejected']) == 2
    with psycopg.connect(os.environ['TELEMETRY_DATABASE_URL']) as db:
        assert db.execute('SELECT sha256 FROM raw_events WHERE sequence=1').fetchone()[0] == original['sha256']
        assert db.execute('SELECT count(*) FROM quarantine').fetchone()[0] == 2


def test_auth_limits_and_rotation(client):
    installation, headers = enroll(client)
    data = batch(installation,[event(installation)])
    assert client.post('/v1/events/batch',json=data).status_code == 401
    other,_ = enroll(client)
    assert client.post('/v1/events/batch',json=batch(other,[event(other)]),headers=headers).status_code == 401
    assert client.post('/v1/events/batch',content=b'x'*(512*1024+1),headers=headers).status_code == 413
    rotation = client.post('/v1/credentials/rotate',json={'installationID':installation},headers=headers)
    assert rotation.status_code == 200
    assert client.post('/v1/events/batch',json=data,headers=headers).status_code == 401
    headers = {'Authorization':'Bearer '+rotation.json()['credential']}
    assert client.post('/v1/events/batch',json=data,headers=headers).status_code == 200


def test_out_of_order_and_checksum(client):
    installation, headers = enroll(client)
    entries = [event(installation,i) for i in (3,1,2)]
    data = batch(installation,entries)
    assert len(client.post('/v1/events/batch',json=data,headers=headers).json()['accepted']) == 3
    data['checksum'] = 'bad'
    assert client.post('/v1/events/batch',json=data,headers=headers).status_code == 400
    assert client.get('/health').json()['status'] == 'ready'
