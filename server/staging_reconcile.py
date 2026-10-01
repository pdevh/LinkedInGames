"""100 synthetic attempts / 3 installations over verified local TLS; hash reconcile.

This does not satisfy real-client capture/UI acceptance. Emits frozen fixtures and
report outside Git, including exact source hashes for independent replay.
"""
import json
import os
from pathlib import Path
import ssl
import time
from uuid import uuid4

import httpx
import psycopg
from server.tests.test_collector import event, batch
from analysis.central.report import report
from server.staging_settings import state_directory, staging_dsn

state = state_directory()
dsn = staging_dsn()
client = httpx.Client(base_url='https://localhost:' + str(int(os.environ.get('TELEMETRY_STAGING_HTTPS_PORT', '8941'))),verify=ssl.create_default_context(cafile=str(state/'tls.crt')),timeout=30)
assert client.get('/health').status_code == 200
installations = []
for _ in range(3):
    installation = str(uuid4())
    enrolled = client.post('/v1/installations',json={'installationID':installation,'enrollmentKey':str(uuid4())})
    enrolled.raise_for_status()
    installations.append((installation,{'Authorization':'Bearer '+enrolled.json()['credential']}))
expected, envelopes, timings, sizes = {}, [], [], []
for index,(installation,headers) in enumerate(installations):
    entries = []
    for attempt in range(34 if index == 0 else 33):
        serve = str(uuid4()); game = 'zip' if attempt % 2 else 'patches'
        selected = 'synthetic-'+serve
        payloads = [('candidateDecision',{'expectedCandidateCount':18,'selectedID':selected,'qualified':False,'fallback':True,
                    'selectionReason':'noEligible','intent':'normal','candidates':[{'candidateID':selected if i==0 else str(uuid4())} for i in range(18)]}),
                    ('serve',{'requested':attempt%3}),('solved',{'verdict':['easy','medium','hard'][attempt%3]})]
        for kind,payload in payloads:
            row = event(installation,len(entries)+1,game=game,serveID=serve,kind=kind,payload=payload)
            entries.append(row); envelopes.append(json.loads(row['payload']))
            expected[(installation,row['eventID'])] = row['sha256']
    # Out-of-order arrival and a deliberately ignored first acknowledgment.
    for group in (entries[::2], entries[1::2]):
        request = batch(installation,group); sizes.append(len(json.dumps(request).encode()))
        for retry in range(2):
            start = time.perf_counter()
            response = client.post('/v1/events/batch',json=request,headers=headers)
            timings.append(time.perf_counter()-start); response.raise_for_status()
            assert len(response.json()['accepted']) == len(group)
with psycopg.connect(dsn) as db:
    rows = db.execute('SELECT installation_id,event_id,sha256 FROM raw_events WHERE installation_id=ANY(%s::uuid[])',([i[0] for i in installations],)).fetchall()
actual = {(str(i),str(e)):h for i,e,h in rows}
assert actual == expected
result = report(envelopes)
assert result['serves'] == 100 and result['terminals'] == 100 and result['uniqueEvents'] == 300
assert not any(result['issues'].values())
result['tlsReconciliation'] = {'attempts':100,'installations':3,'events':len(actual),'batchesIncludingRetries':len(timings),
                              'maxReceiptSeconds':max(timings),'batchBytes':sizes,'fixtureOnly':True}
(state/'reconciliation-events.jsonl').write_text(''.join(json.dumps(e,sort_keys=True)+'\n' for e in envelopes))
(state/'reconciliation-report.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print(json.dumps(result['tlsReconciliation'],sort_keys=True))
