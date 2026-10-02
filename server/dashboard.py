"""Read-only telemetry dashboard. Serve on 127.0.0.1 and access by SSH tunnel."""
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from html import escape
import json
import os
from uuid import UUID
from zoneinfo import ZoneInfo

import psycopg
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["localhost", "127.0.0.1"])
BERLIN = ZoneInfo("Europe/Berlin")
GAMES = ("all", "zip", "patches", "system")
LEVELS = ("easy", "medium", "hard")
ANALYTIC_KINDS = ("serve", "candidateDecision", "solved", "solve", "skipped", "abandoned",
                  "legacyImport", "feedbackPending", "feedbackSubmitted", "feedbackSkipped",
                  "feedbackShown", "loss", "recovery", "captureGap")
FIXTURES = ("collectorSmoke", "centralSmokeFixture")


def connection():
    return psycopg.connect(os.environ["TELEMETRY_DATABASE_URL"], connect_timeout=5,
                           options="-c default_transaction_read_only=on -c statement_timeout=10000")


def scope(game, days):
    if game not in GAMES or days not in ("7", "30", "all"):
        raise HTTPException(400, "Invalid filter")
    since = None if days == "all" else datetime.now(timezone.utc) - timedelta(days=int(days))
    return since, game if game != "all" else None


def level(value):
    if isinstance(value, int) and value in range(3):
        return LEVELS[value]
    if isinstance(value, str) and value.lower() in LEVELS:
        return value.lower()
    return None


def analyze(rows):
    """Keep new serves and imported records as separate evidence populations."""
    serves, decisions, terminals = {}, {}, {}
    legacy = Counter()
    historical = defaultdict(Counter)
    feedback = Counter()
    alerts = Counter()
    for game, kind, raw in rows:
        event = json.loads(raw)
        key = (event["installationID"], event.get("serveID"))
        payload = event["payload"]
        if kind == "serve":
            serves[key] = event
        elif kind == "candidateDecision":
            decisions[key] = event
        elif kind in ("solved", "solve", "skipped", "abandoned"):
            if key in terminals:
                alerts["duplicateTerminal"] += 1
            terminals[key] = event
        elif kind == "legacyImport":
            legacy[game] += 1
            if payload.get("timestampQuality") == "missingLegacy":
                legacy["missingDate"] += 1
            record = payload.get("record", {})
            requested = level(record.get("difficulty", record.get("requested")))
            if requested:
                historical[game][requested] += 1
            if record.get("outcome") == "solved" or record.get("solved") is True:
                legacy["solved"] += 1
                assessed = level(record.get("experiencedDifficulty", record.get("verdict")))
                if requested and assessed:
                    legacy["rated"] += 1
                    legacy["matched"] += requested == assessed
        elif kind.startswith("feedback"):
            feedback[kind] += 1
        elif kind in ("loss", "recovery", "captureGap"):
            alerts[kind] += 1

    status = defaultdict(Counter)
    matrix = {(a, b): 0 for a in LEVELS for b in LEVELS}
    qualified_match = Counter()
    all_match = Counter()
    outcomes = Counter()
    alerts["terminalWithoutServeInView"] = len(terminals.keys() - serves.keys())
    for key, serve in serves.items():
        game = serve["game"]
        decision = decisions.get(key, {}).get("payload", {})
        if decision.get("fallback") is True:
            status[game]["fallback"] += 1
        elif decision.get("fallback") is False:
            status[game]["normal"] += 1
        else:
            status[game]["unknown"] += 1
        if not decision:
            alerts["missingPool"] += 1
        else:
            candidates = decision.get("candidates", [])
            if decision.get("expectedCandidateCount", len(candidates)) != len(candidates):
                alerts["incompletePool"] += 1
            if decision.get("selectedID") not in {c.get("candidateID") for c in candidates}:
                alerts["selectedNotInPool"] += 1
        terminal = terminals.get(key)
        if terminal is None:
            outcomes["noTerminalYet"] += 1
            continue
        outcomes[terminal["kind"]] += 1
        if terminal["kind"] not in ("solved", "solve"):
            continue
        requested = level(serve["payload"].get("requested", serve["payload"].get("difficulty")))
        assessed = level(terminal["payload"].get("verdict", terminal["payload"].get("experiencedDifficulty")))
        if requested and assessed:
            matrix[(requested, assessed)] += 1
            all_match["rated"] += 1
            all_match["matched"] += requested == assessed
            if decision.get("qualified") is True and decision.get("fallback") is False:
                qualified_match["rated"] += 1
                qualified_match["matched"] += requested == assessed
    return dict(serves=len(serves), status=status, outcomes=outcomes, matrix=matrix,
                all_match=all_match, qualified_match=qualified_match, legacy=legacy,
                historical=historical, feedback=feedback, alerts=alerts)


def data(game, days, page):
    since, chosen_game = scope(game, days)
    if page < 1 or page > 100000:
        raise HTTPException(400, "Invalid page")
    params = (since, since, chosen_game, chosen_game)
    where = "(%s::timestamptz IS NULL OR received_at >= %s) AND (%s::text IS NULL OR game = %s)"
    with connection() as db:
        total, installations = db.execute(
            f"""SELECT count(*),count(DISTINCT installation_id)
                FILTER (WHERE kind NOT IN ('collectorSmoke','centralSmokeFixture'))
                FROM raw_events WHERE {where}""", params).fetchone()
        daily = db.execute(f"""SELECT date(timezone('Europe/Berlin',received_at)),game,count(*)
            FROM raw_events WHERE {where} GROUP BY 1,2 ORDER BY 1""", params).fetchall()
        kinds = db.execute(f"SELECT game,kind,count(*) FROM raw_events WHERE {where} GROUP BY 1,2 ORDER BY 1,2",
                           params).fetchall()
        semantic = db.execute(f"SELECT game,kind,payload FROM raw_events WHERE {where} AND kind = ANY(%s)",
                              (*params, list(ANALYTIC_KINDS))).fetchall()
        events = db.execute(f"""SELECT installation_id,event_id,game,kind,sequence,received_at
            FROM raw_events WHERE {where} ORDER BY received_at DESC, installation_id,sequence DESC
            LIMIT 50 OFFSET %s""", (*params, (page - 1) * 50)).fetchall()
        quarantine = db.execute("SELECT count(*) FROM quarantine").fetchone()[0]
        receipt_count = db.execute("SELECT count(*) FROM receipts").fetchone()[0]
        gaps = db.execute("""SELECT COALESCE(sum(last_sequence-event_count),0) FROM
            (SELECT max(sequence) AS last_sequence,count(*) AS event_count FROM raw_events GROUP BY installation_id) s""").fetchone()[0]
        latest = db.execute("SELECT max(received_at) FROM raw_events").fetchone()[0]
    return dict(total=total, installations=installations, daily=daily, kinds=kinds,
                analysis=analyze(semantic), events=events, quarantine=quarantine,
                receipt_count=receipt_count, gaps=gaps, latest=latest, page=page)


def h(value):
    return escape(str(value), quote=True)


def local_time(value):
    return value.astimezone(BERLIN).strftime("%d %b %Y, %H:%M") if value else "—"


def metric(value, label, note=""):
    return f'<div class="metric"><strong>{h(value)}</strong><span>{h(label)}</span><small>{h(note)}</small></div>'


def bar_chart(daily):
    days = sorted({row[0] for row in daily})
    if not days:
        return '<p class="empty">No received events in this period.</p>'
    counts = {(day, game): count for day, game, count in daily}
    peak = max(sum(counts.get((day, game), 0) for game in GAMES[1:]) for day in days) or 1
    width = max(520, len(days) * 28 + 80)
    elements = []
    for index, day in enumerate(days):
        x = 48 + index * (width - 70) / max(1, len(days))
        bottom = 154
        for game, color in (("zip", "#3b82f6"), ("patches", "#16a6a0"), ("system", "#a9b3c2")):
            count = counts.get((day, game), 0)
            height = 112 * count / peak
            if count:
                elements.append(f'<rect x="{x:.1f}" y="{bottom-height:.1f}" width="16" height="{height:.1f}" fill="{color}"><title>{h(day)} · {game}: {count}</title></rect>')
            bottom -= height
        elements.append(f'<text x="{x+8:.1f}" y="171" text-anchor="middle">{day.strftime("%d %b")}</text>')
    return f'<div class="chart-scroll"><svg viewBox="0 0 {width} 188" role="img" aria-label="Daily received events by game">' + ''.join(elements) + '</svg></div><div class="legend"><i class="zip"></i>Zip <i class="patches"></i>Patches <i class="system"></i>System</div>'


def matrix_chart(matrix):
    largest = max(matrix.values(), default=0)
    header = '<tr><th>Selected ↓ / assessed →</th>' + ''.join(f'<th>{x.title()}</th>' for x in LEVELS) + '</tr>'
    rows = []
    for selected in LEVELS:
        cells = []
        for assessed in LEVELS:
            count = matrix[(selected, assessed)]
            opacity = 0.06 + (0.55 * count / largest if largest else 0)
            cells.append(f'<td style="background:rgba(59,130,246,{opacity:.2f})">{count}</td>')
        rows.append(f'<tr><th>{selected.title()}</th>{"".join(cells)}</tr>')
    return '<table class="matrix">' + header + ''.join(rows) + '</table>'


def history_chart(historical):
    rows = []
    for game in ("zip", "patches"):
        counts = historical[game]
        total = sum(counts.values())
        for selected in LEVELS:
            count = counts[selected]
            fraction = round(100 * count / total) if total else 0
            rows.append(f'<div class="history-row"><span>{game.title()} · {selected.title()}</span><div class="track"><div style="width:{fraction}%"></div></div><b>{count}</b></div>')
    return ''.join(rows) if rows else '<p class="empty">No saved history in this period.</p>'


def render(view, game, days):
    a = view["analysis"]
    status = Counter()
    for values in a["status"].values():
        status.update(values)
    known = status["fallback"] + status["normal"]
    matched, rated = a["all_match"]["matched"], a["all_match"]["rated"]
    match_text = f"{matched}/{rated}" if rated else "—"
    fallback_text = f"{status['fallback']}/{known}" if known else "—"
    scope_note = "All received dates" if days == "all" else f"Last {days} days by server receipt time"
    latest = local_time(view["latest"])
    options = ''.join(f'<option value="{x}" {"selected" if x == game else ""}>{x.title()}</option>' for x in GAMES)
    periods = ''.join(f'<option value="{x}" {"selected" if x == days else ""}>{"All dates" if x == "all" else "Last "+x+" days"}</option>' for x in ("7", "30", "all"))
    fixture_count = sum(n for _, kind, n in view["kinds"] if kind in FIXTURES)
    metrics = ''.join((metric(f'{view["total"]:,}', "Received events", f"{scope_note} · {fixture_count} smoke checks included"),
                       metric(a["serves"], "New puzzles served", "Imported history is separate"),
                       metric(sum(a["legacy"][g] for g in ("zip", "patches")), "Saved records imported", "Dates may be missing"),
                       metric(view["installations"], "Gameplay installation IDs", "Excludes smoke checks; not distinct people")))
    status_note = f'{status["unknown"]} unknown selection statuses; {a["outcomes"]["noTerminalYet"]} serves have no terminal event yet.'
    alignment_note = f'{matched} matches among {rated} assessed new solves. No model accuracy or cause is established from this sample.'
    history_note = f'{a["legacy"]["rated"]} of {a["legacy"]["solved"]} imported solves have both a selected and assessed level; {a["legacy"]["missingDate"]} imported records lack an original date.'
    feedback = a["feedback"]
    quality = f'{view["quarantine"]} quarantined events · {view["gaps"]} sequence gaps · {a["alerts"]["missingPool"]} serves missing a candidate decision · {a["alerts"]["duplicateTerminal"]} duplicate terminals in view · {a["alerts"]["loss"]} loss manifests'
    kind_rows = ''.join(f'<tr><td>{h(g)}</td><td>{h(k)}</td><td class="number">{n:,}</td></tr>' for g, k, n in view["kinds"])
    event_rows = ''.join(f'<tr><td>{h(local_time(at))}</td><td>{h(g)}</td><td>{h(k)}</td><td class="number">{seq}</td><td><a href="/event/{eid}?installation={iid}">{h(str(eid)[:8])}…</a></td></tr>'
                         for iid, eid, g, k, seq, at in view["events"])
    previous = f'<a href="/?game={game}&days={days}&page={view["page"]-1}">Previous</a>' if view["page"] > 1 else ''
    following = f'<a href="/?game={game}&days={days}&page={view["page"]+1}">Next</a>' if view["page"]*50 < view["total"] else ''
    insight = (f'All {known} known new puzzle selections in this view used a fallback.' if known and status["fallback"] == known
               else f'{status["fallback"]} of {known} known new selections used a fallback.' if known else
               'No known selection statuses yet.')
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="60">
<title>LinkedInGames · Difficulty telemetry</title><style>
:root{{font-family:system-ui,-apple-system,sans-serif;color:#1c2940;background:#f4f7fb}}*{{box-sizing:border-box}}
body{{margin:0}}main{{max-width:1280px;margin:auto;padding:28px 26px 80px}}header{{display:flex;justify-content:space-between;gap:20px;align-items:end;flex-wrap:wrap}}
h1{{font-size:29px;margin:0 0 5px}}h2{{font-size:18px;margin:0 0 14px}}p{{line-height:1.45}}.muted,small{{color:#62728b}}
form{{display:flex;gap:10px;align-items:end;flex-wrap:wrap}}label{{display:grid;gap:4px;font-size:12px;color:#52627b;font-weight:600}}
select,button{{padding:8px 12px;border:1px solid #cad4e2;border-radius:8px;background:white;color:#1c2940;font:inherit}}button{{cursor:pointer;background:#1c2940;color:white}}
.grid{{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:22px 0}}.metric,.panel{{background:white;border:1px solid #e2e9f1;border-radius:14px;box-shadow:0 3px 14px #1c294008}}
.metric{{padding:18px;display:grid;gap:5px}}.metric strong{{font-size:27px}}.metric span{{font-weight:650}}.metric small{{font-size:11px}}
.two{{display:grid;grid-template-columns:1.25fr 1fr;gap:14px;margin:14px 0}}.panel{{padding:21px;min-width:0}}.wide{{margin:14px 0}}
.lead{{font-weight:650;color:#17467c}}.chart-scroll{{overflow:auto}}svg{{width:100%;min-width:520px;height:188px}}svg text{{font-size:10px;fill:#66758d}}
.legend{{display:flex;gap:6px;align-items:center;color:#62728b;font-size:12px}}.legend i{{display:inline-block;width:10px;height:10px;border-radius:2px;margin-left:8px}}.zip{{background:#3b82f6}}.patches{{background:#16a6a0}}.system{{background:#a9b3c2}}
table{{width:100%;border-collapse:collapse;font-size:13px}}th,td{{padding:9px 8px;border-bottom:1px solid #edf1f6;text-align:left}}th{{color:#53647c}}.number{{text-align:right}}.matrix td{{text-align:center;font-weight:650}}
.history-row{{display:grid;grid-template-columns:120px 1fr 30px;gap:12px;align-items:center;padding:5px 0;font-size:13px}}.track{{height:12px;background:#edf2f8;border-radius:8px;overflow:hidden}}.track div{{height:100%;background:#3b82f6}}
.table-scroll{{overflow:auto}}a{{color:#135aa0}}.page-links{{display:flex;gap:18px;margin-top:12px}}.empty{{color:#78869c}}
@media(max-width:900px){{.grid{{grid-template-columns:repeat(2,1fr)}}.two{{grid-template-columns:1fr}}}}@media(max-width:560px){{main{{padding:18px 12px}}.grid{{grid-template-columns:1fr}}}}
</style></head><body><main><header><div><h1>Difficulty telemetry</h1><div class="muted">Received through {h(latest)} Berlin time · Read-only source</div></div>
<form method="get"><label>Game<select name="game">{options}</select></label><label>Received<select name="days">{periods}</select></label><button>Apply</button></form></header>
<div class="grid">{metrics}</div>
<div class="two"><section class="panel"><h2>Events received by day</h2>{bar_chart(view['daily'])}<p class="muted">Receipt date shows when the server got data; imported plays may be older.</p></section>
<section class="panel"><h2>New puzzle service</h2><p class="lead">{h(insight)}</p><p>{h(fallback_text)} fallback among known selections. Qualified picks: {status['normal']}. {h(status_note)}</p>
<p class="muted">Fallback means the selected candidate did not qualify for the requested difficulty. An open puzzle is not counted as abandoned.</p></section></div>
<div class="two"><section class="panel"><h2>Selected versus assessed · new solves</h2>{matrix_chart(a['matrix'])}<p>{h(match_text)} match. {h(alignment_note)}</p>
<p class="muted">Qualified-only match: {a['qualified_match']['matched']}/{a['qualified_match']['rated']}. These are app assessments, not player feedback.</p></section>
<section class="panel"><h2>Imported play history</h2>{history_chart(a['historical'])}<p>{h(history_note)}</p>
<p class="muted">Imported history is separate from new puzzles; missing dates are not inferred.</p></section></div>
<div class="two"><section class="panel"><h2>Feedback and capture</h2><p>Invitations: {feedback['feedbackPending']} · Responses: {feedback['feedbackSubmitted']} · Skips: {feedback['feedbackSkipped']} · Verdicts shown: {feedback['feedbackShown']}</p>
<p class="muted">Optional responses are not effort labels. These counts follow event kinds and do not infer missing responses.</p></section>
<section class="panel"><h2>Data quality</h2><p>{h(quality)}</p><p class="muted">{view['receipt_count']} receipt rows · {a['alerts']['terminalWithoutServeInView']} terminals without a serve in this view. Quarantine, sequence gaps and receipts cover all dates. A filtered view can exclude a serve received earlier than its terminal.</p></section></div>
<section class="panel wide"><h2>Received event types</h2><div class="table-scroll"><table><tr><th>Game</th><th>Event</th><th class="number">Count</th></tr>{kind_rows}</table></div></section>
<section class="panel wide"><h2>Raw event explorer</h2><p class="muted">Every stored event is available by page, including puzzle content and the exact payload. <a href="/export?game={game}&days={days}">Download filtered JSONL</a>.</p>
<div class="table-scroll"><table><tr><th>Received</th><th>Game</th><th>Kind</th><th class="number">Sequence</th><th>Event ID</th></tr>{event_rows}</table></div><div class="page-links">{previous}{following}<span class="muted">Page {view['page']} · {view['total']:,} matching events</span></div></section>
</main></body></html>'''


def headers():
    return {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer", "Content-Security-Policy":
            "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"}


@app.get("/", response_class=HTMLResponse)
def home(game: str = "all", days: str = "all", page: int = 1):
    return HTMLResponse(render(data(game, days, page), game, days), headers=headers())


@app.get("/health")
def health():
    with connection() as db:
        db.execute("SELECT 1 FROM raw_events LIMIT 1")
    return {"status": "ready"}


@app.get("/event/{event_id}", response_class=HTMLResponse)
def event_detail(event_id: UUID, installation: UUID):
    with connection() as db:
        row = db.execute("""SELECT game,kind,sequence,received_at,sha256,payload FROM raw_events
            WHERE installation_id=%s AND event_id=%s""", (installation, event_id)).fetchone()
    if row is None:
        raise HTTPException(404, "Event not found")
    game, kind, sequence, received, digest, raw = row
    pretty = json.dumps(json.loads(raw), indent=2, ensure_ascii=False)
    body = f'''<!doctype html><html><head><meta charset="utf-8"><title>Event {h(event_id)}</title>
<style>body{{font:15px system-ui;max-width:1050px;margin:35px auto;padding:0 18px;color:#1c2940}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#f4f7fb;padding:20px;border-radius:10px}}a{{color:#135aa0}}</style></head>
<body><a href="/">← Dashboard</a><h1>{h(game)} · {h(kind)}</h1><p>Received {h(local_time(received))} · Sequence {sequence} · SHA-256 {h(digest)}</p><pre>{h(pretty)}</pre></body></html>'''
    return HTMLResponse(body, headers=headers())


@app.get("/export")
def export(game: str = "all", days: str = "all"):
    since, chosen_game = scope(game, days)

    def lines():
        with connection() as db:
            with db.cursor(name="dashboard_export") as cursor:
                cursor.execute("""SELECT payload FROM raw_events
                    WHERE (%s::timestamptz IS NULL OR received_at >= %s)
                      AND (%s::text IS NULL OR game = %s)
                    ORDER BY received_at,installation_id,sequence""",
                    (since, since, chosen_game, chosen_game))
                for (raw,) in cursor:
                    yield raw + "\n"

    return StreamingResponse(lines(), media_type="application/x-ndjson", headers={
        **headers(), "Content-Disposition": 'attachment; filename="linkedgames-telemetry.jsonl"'})
