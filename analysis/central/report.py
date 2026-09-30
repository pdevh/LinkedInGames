"""Versioned deterministic quality/service report from a frozen raw-event export.

Usage: python analysis/central/report.py events.jsonl output.json
Each input line is the original event envelope, not a rewritten summary.
"""
import collections
import hashlib
import json
from pathlib import Path
import sys

VERSION = 1


def report(events):
    identities = set()
    seen = {}
    sequences = collections.defaultdict(set)
    serves, terminals, pools = {}, {}, {}
    issues = collections.Counter()
    feedback = collections.Counter()
    for e in events:
        key = (e['installationID'], e['eventID'])
        canonical = json.dumps(e,sort_keys=True,separators=(',',':'))
        if key in seen:
            issues['identicalDuplicate' if seen[key] == canonical else 'eventCollision'] += 1
            continue
        seen[key] = canonical
        identities.add(e['installationID'])
        sequences[e['installationID']].add(e['sequence'])
        serve = (e['installationID'],e.get('serveID'))
        kind = e['kind']
        if kind == 'serve':
            serves[serve] = e
        elif kind == 'candidateDecision':
            pools[serve] = e
        elif kind in ('solved','solve','skipped','abandoned'):
            if serve in terminals:
                issues['duplicateTerminal'] += 1
            terminals[serve] = e
        elif kind in ('loss','recovery','captureGap'):
            issues[kind] += 1
        elif kind.startswith('feedback'):
            feedback[kind] += 1
    for values in sequences.values():
        issues['sequenceGaps'] += max(values,default=0)-len(values)
    cohorts = collections.defaultdict(lambda:collections.Counter())
    for key, serve in sorted(serves.items()):
        payload = serve['payload']; decision = pools.get(key,{}).get('payload',{})
        cohort = '|'.join(str(x) for x in (serve['game'],payload.get('requested',payload.get('difficulty','unknown')),
                     serve['versions']['timing'],serve['versions']['experiment']))
        counts = cohorts[cohort]; counts['serves'] += 1
        if not decision:
            issues['missingPool'] += 1
        else:
            candidates = decision.get('candidates',[])
            if decision.get('selectedID') not in {c['candidateID'] for c in candidates}:
                issues['selectedNotInPool'] += 1
            if decision.get('expectedCandidateCount',len(candidates)) != len(candidates):
                issues['incompletePool'] += 1
        normal = decision.get('intent','normal') == 'normal'
        if normal:
            counts['normalServes'] += 1
            if isinstance(decision.get('fallback'),bool):
                counts['knownServiceStatus'] += 1
                counts['fallbackServes'] += int(decision['fallback'])
            else:
                counts['unknownServiceStatus'] += 1
        terminal = terminals.get(key)
        if not terminal:
            counts['noTerminalYet'] += 1  # neither abandonment nor failure
            continue
        counts[terminal['kind']] += 1
        result = terminal['payload']
        verdict = result.get('verdict',result.get('experiencedDifficulty'))
        requested = payload.get('requested',payload.get('difficulty'))
        if isinstance(requested,int) and requested in range(3):
            requested = ['easy','medium','hard'][requested]
        if verdict and normal:
            matched = str(requested).lower() == verdict.lower()
            counts['allRatedNormal'] += 1; counts['allMatchedNormal'] += matched
            if decision.get('qualified') is True and decision.get('fallback') is False and decision.get('selectionReason') != 'coldStart':
                counts['qualifiedRated'] += 1; counts['qualifiedMatched'] += matched
    return {'transformVersion':VERSION,'installationsNotPeople':len(identities),'uniqueEvents':len(seen),
            'serves':len(serves),'terminals':len(terminals),'issues':dict(sorted(issues.items())),
            'cohorts':{k:dict(sorted(v.items())) for k,v in sorted(cohorts.items())},
            'feedbackCounts':dict(sorted(feedback.items())),
            'limitations':['No causal or model improvement claim.','No-terminal-yet includes resumable and delayed arrivals.',
                            'Subjective response bias remains; ratings never replace effort.',
                            'Synthetic fixtures establish mechanics only.']}


if __name__ == '__main__':
    raw = Path(sys.argv[1]).read_bytes()
    result = report([json.loads(line) for line in raw.splitlines() if line])
    result['sourceSHA256'] = hashlib.sha256(raw).hexdigest()
    Path(sys.argv[2]).write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
