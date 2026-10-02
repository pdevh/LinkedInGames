"""Representative new and historical telemetry must stay distinct in the dashboard."""
import json
from uuid import uuid4

from fastapi.testclient import TestClient

from server.dashboard import analyze, app


def envelope(game, kind, serve, payload):
    return (game, kind, json.dumps({"installationID": "test-installation", "serveID": serve,
                                    "game": game, "kind": kind, "payload": payload}))


def test_new_service_status_and_historical_missingness():
    serve = str(uuid4())
    rows = [
        envelope("zip", "serve", serve, {"difficulty": "HARD"}),
        envelope("zip", "candidateDecision", serve,
                 {"fallback": True, "qualified": False, "selectedID": "p1",
                  "expectedCandidateCount": 1, "candidates": [{"candidateID": "p1"}]}),
        envelope("zip", "solved", serve, {"experiencedDifficulty": "medium"}),
        envelope("patches", "legacyImport", str(uuid4()),
                 {"timestampQuality": "missingLegacy", "record":
                  {"requested": 1, "solved": True, "verdict": "medium"}}),
    ]
    result = analyze(rows)
    assert result["serves"] == 1
    assert result["status"]["zip"]["fallback"] == 1
    assert result["all_match"] == {"rated": 1, "matched": 0}
    assert result["qualified_match"] == {}
    assert result["matrix"][("hard", "medium")] == 1
    assert result["legacy"]["missingDate"] == 1
    assert result["legacy"]["matched"] == 1
    assert result["alerts"]["missingPool"] == 0
    assert result["alerts"]["terminalWithoutServeInView"] == 0


def test_loopback_host_guard():
    local = TestClient(app, base_url="http://localhost")
    assert local.get("/?days=invalid").status_code == 400
    foreign = TestClient(app, base_url="http://example.com")
    assert foreign.get("/").status_code == 400
