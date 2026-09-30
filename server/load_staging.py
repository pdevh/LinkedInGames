"""30-minute 2x provisional launch peak: 2 batches/s, 10 unique events/batch.

Run after migrations and collector start. Synthetic protocol capacity only.
"""
import concurrent.futures
import json
from pathlib import Path
import ssl
import time
from uuid import uuid4
import httpx
from server.tests.test_collector import event, batch

state = Path.home()/'.config/linkedgames-telemetry-staging'
client = httpx.Client(base_url='https://localhost:8941',verify=ssl.create_default_context(cafile=str(state/'tls.crt')),timeout=10)
installation = str(uuid4())
response = client.post('/v1/installations',json={'installationID':installation,'enrollmentKey':str(uuid4())})
response.raise_for_status(); headers = {'Authorization':'Bearer '+response.json()['credential']}
began = time.monotonic(); timings = []; errors = []; futures = []

def send(index):
    entries = [event(installation,index*10+i+1,kind='loadFixture',game='system') for i in range(10)]
    start = time.monotonic()
    response = client.post('/v1/events/batch',json=batch(installation,entries),headers=headers)
    response.raise_for_status()
    assert len(response.json()['accepted']) == 10
    return time.monotonic()-start

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for i in range(3600):
        wait = began+i/2-time.monotonic()
        if wait > 0: time.sleep(wait)
        futures.append(pool.submit(send,i))
        if i % 120 == 0:
            (state/'load-progress.json').write_text(json.dumps({'scheduled':i+1,'total':3600,'elapsed':time.monotonic()-began}))
    for future in futures:
        try: timings.append(future.result())
        except Exception as error: errors.append(str(error))
ordered = sorted(timings)
result = {'installationID':installation,'durationSeconds':time.monotonic()-began,'batches':len(timings),'events':len(timings)*10,
          'targetBatchesPerSecond':2,'declaredLaunchBatchesPerSecond':1,'eventsPerBatch':10,
          'p95Seconds':ordered[int(len(ordered)*.95)] if ordered else None,'maxSeconds':max(ordered,default=0),'errors':errors,
          'fixtureOnly':True}
(state/'load-result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
