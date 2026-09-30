import json
from analysis.central.report import report
from server.tests.test_collector import event
from uuid import uuid4


def test_report_keeps_unknowns_and_unsolved_denominators():
    installation = str(uuid4()); serve = str(uuid4())
    e = json.loads(event(installation,kind='serve',serveID=serve)['payload'])
    output = report([e,e])
    assert output['uniqueEvents'] == 1 and output['issues']['identicalDuplicate'] == 1
    counts = next(iter(output['cohorts'].values()))
    assert counts['noTerminalYet'] == 1 and counts['unknownServiceStatus'] == 1
    assert 'abandoned' not in counts
