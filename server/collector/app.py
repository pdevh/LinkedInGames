"""Synchronous commit collector. No analytical work runs on the receipt path."""
import gzip
import hashlib
import json
import os
import secrets
from datetime import datetime, timezone
from uuid import uuid4

import psycopg
from fastapi import FastAPI, HTTPException, Request
from psycopg.types.json import Jsonb
from .protocol import digest, uuid, validate

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def connect():
    return psycopg.connect(os.environ['TELEMETRY_DATABASE_URL'], connect_timeout=5,
                           options='-c synchronous_commit=on -c statement_timeout=10000')


async def body(request):
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > 512 * 1024:
            raise HTTPException(413, 'transportLimit')
    if request.headers.get('content-encoding') == 'gzip':
        import io
        try:
            with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
                data = stream.read(4 * 1024 * 1024 + 1)
        except (OSError, EOFError):
            raise HTTPException(400, 'gzip')
    elif request.headers.get('content-encoding', 'identity') != 'identity':
        raise HTTPException(415, 'encoding')
    if len(data) > 4 * 1024 * 1024:
        raise HTTPException(413, 'inflatedLimit')
    try:
        value = json.loads(data)
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except (ValueError, UnicodeError):
        raise HTTPException(400, 'json')


def authenticate(db, request, installation):
    token = request.headers.get('authorization', '').removeprefix('Bearer ')
    row = db.execute('SELECT credential_hash,disabled FROM installations WHERE id=%s', (installation,)).fetchone()
    if not row or row[1] or not secrets.compare_digest(row[0], digest(token)):
        raise HTTPException(401, 'credential')


@app.get('/')
@app.get('/health')
def health():
    try:
        with connect() as db:
            settings = db.execute('SELECT current_setting(\'fsync\'),current_setting(\'synchronous_commit\')').fetchone()
            if settings != ('on', 'on'):
                raise HTTPException(503, 'durabilityConfiguration')
            versions = {row[0] for row in db.execute('SELECT version FROM schema_migrations')}
            if not {1, 2} <= versions:
                raise HTTPException(503, 'migrationsRequired', headers={'Retry-After': '5'})
        return {'status': 'ready', 'schemaVersion': 1}
    except psycopg.Error:
        raise HTTPException(503, 'database', headers={'Retry-After': '5'})


@app.post('/v1/installations')
async def enroll(request: Request):
    data = await body(request)
    try:
        installation = uuid(data['installationID'])
        enrollment_key = data.get('enrollmentKey')
        if request.url.path == '/v1/installations' and (not isinstance(enrollment_key,str) or not 32 <= len(enrollment_key) <= 200):
            raise ValueError('enrollmentKey')
    except (KeyError, ValueError, TypeError):
        raise HTTPException(400, 'installationID')
    # Trust socket address only, not caller-controlled forwarding headers.
    peer = request.client.host if request.client else 'unknown'
    if peer in ('127.0.0.1','::1') and os.environ.get('TELEMETRY_TRUST_LOOPBACK_PROXY') == 'true':
        import ipaddress
        try:
            peer = str(ipaddress.ip_address(request.headers.get('x-real-ip','')))
        except ValueError:
            raise HTTPException(400, 'proxyAddress')
    address = digest(peer)
    token = secrets.token_urlsafe(32)
    try:
        with connect() as db:
            count = db.execute('''INSERT INTO enrollment_limits VALUES(%s,now(),1)
                ON CONFLICT(address_hash) DO UPDATE SET
                count=CASE WHEN enrollment_limits.window_start < now()-interval '1 hour' THEN 1 ELSE enrollment_limits.count+1 END,
                window_start=CASE WHEN enrollment_limits.window_start < now()-interval '1 hour' THEN now() ELSE enrollment_limits.window_start END
                RETURNING count''', (address,)).fetchone()[0]
            if count <= 30:
                row = db.execute('''INSERT INTO installations(id,credential_hash,enrollment_key_hash) VALUES(%s,%s,%s)
                    ON CONFLICT(id) DO UPDATE SET credential_hash=EXCLUDED.credential_hash
                    WHERE installations.enrollment_key_hash=EXCLUDED.enrollment_key_hash AND NOT installations.disabled
                    RETURNING id''', (installation,digest(token),digest(enrollment_key))).fetchone()
            else:
                row = None
        if count > 30:
            raise HTTPException(429, 'enrollmentLimit', headers={'Retry-After':'3600'})
        if not row:
            raise HTTPException(409, 'existingIdentityRequiresCredential')
        return {'installationID':installation,'credential':token}
    except psycopg.Error:
        raise HTTPException(503, 'database', headers={'Retry-After':'5'})


@app.post('/v1/credentials/rotate')
async def rotate(request: Request):
    data = await body(request)
    try:
        installation = uuid(data['installationID'])
    except (KeyError, ValueError, TypeError):
        raise HTTPException(400, 'installationID')
    token = secrets.token_urlsafe(32)
    try:
        with connect() as db:
            db.execute('SELECT id FROM installations WHERE id=%s FOR UPDATE', (installation,))
            authenticate(db,request,installation)
            db.execute('UPDATE installations SET credential_hash=%s WHERE id=%s',(digest(token),installation))
    except psycopg.Error:
        raise HTTPException(503, 'database', headers={'Retry-After': '5'})
    return {'credential':token}


@app.post('/v1/events/batch')
async def ingest(request: Request):
    data = await body(request)
    try:
        installation, batch = uuid(data['installationID']), uuid(data['batchID'])
        entries = data['events']
        if type(data['schemaVersion']) is not int or data['schemaVersion'] != 1:
            raise HTTPException(422, 'unknownSchema')
        if not isinstance(entries,list) or not 1 <= len(entries) <= 500:
            raise HTTPException(413, 'eventCount')
        if not all(isinstance(e,dict) and isinstance(e.get('sha256'),str) for e in entries):
            raise HTTPException(400, 'entryEnvelope')
        if digest(''.join(e['sha256'] for e in entries)) != data['checksum']:
            raise HTTPException(400, 'batchChecksum')
    except (KeyError, TypeError, ValueError):
        raise HTTPException(400, 'batchEnvelope')
    receipt = {'batchID':batch,'accepted':[],'rejected':[], 'receivedAt':datetime.now(timezone.utc).isoformat()}
    try:
        with connect() as db:
            # Serialize an installation, including concurrent duplicate/sequence submissions.
            db.execute('SELECT id FROM installations WHERE id=%s FOR UPDATE',(installation,))
            authenticate(db,request,installation)
            for entry in entries:
                reason = None
                try:
                    event = validate(entry,installation)
                except (ValueError, KeyError, TypeError, AttributeError):
                    reason = 'invalidEventOrSchema'
                if reason is None:
                    existing = db.execute('SELECT event_id,sequence,sha256 FROM raw_events WHERE installation_id=%s AND (event_id=%s OR sequence=%s)',
                        (installation,entry['eventID'],entry['sequence'])).fetchall()
                    if existing and not (len(existing)==1 and str(existing[0][0])==uuid(entry['eventID']) and existing[0][1]==entry['sequence'] and existing[0][2]==entry['sha256']):
                        reason = 'identityOrSequenceCollision'
                    elif not existing:
                        db.execute('''INSERT INTO raw_events(installation_id,event_id,sequence,sha256,payload,game,kind,serve_id,created_at)
                            VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s)''', (installation,entry['eventID'],entry['sequence'],entry['sha256'],entry['payload'],event['game'],event['kind'],event['serveID'],event['createdAt']))
                if reason:
                    db.execute('INSERT INTO quarantine(installation_id,event_id,reason,sha256,payload) VALUES(%s,%s,%s,%s,%s)',
                        (installation,str(entry.get('eventID',''))[:100],reason,str(entry.get('sha256',''))[:64],str(entry.get('payload',''))))
                    receipt['rejected'].append({'eventID':entry.get('eventID'),'reason':reason,'retryable':False})
                else:
                    receipt['accepted'].append({'eventID':entry['eventID'],'sha256':entry['sha256']})
            db.execute('INSERT INTO receipts(installation_id,batch_id,body) VALUES(%s,%s,%s)',(installation,batch,Jsonb(receipt)))
        # Context manager has COMMITTED before any accepted ID leaves this process.
        return receipt
    except psycopg.Error:
        raise HTTPException(503, 'database', headers={'Retry-After':'5'})
