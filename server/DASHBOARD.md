# SSH-only telemetry dashboard

The dashboard reads live events from the production PostgreSQL database using
the existing read-only report role. It does not collect or alter telemetry.
The `linkedgames-dashboard.service` unit binds only to `127.0.0.1:8944` and
has no Nginx or public DNS route. It refreshes every 60 seconds.

From your own computer, open an SSH tunnel (replace the SSH host if needed):

```sh
ssh -N -L 8944:127.0.0.1:8944 phil_user@37.114.42.231
```

Then open `http://localhost:8944/` in your browser. Keep the SSH session open
while using the dashboard. If port 8944 is occupied on your computer, use a
different *first* port in the `-L` argument and browse that port instead.
The server's port remains 8944.

The opening view shows received event volume, gameplay installation IDs,
new serves, imported history, fallback status, selected versus assessed
difficulty, feedback and data-quality signals. Filters use the server receipt
date. Historical imports are kept separate from new serves because their
selection status and, for some records, dates are unknown. The event explorer
paginates all stored raw events, opens exact payloads, and exports filtered
JSONL. Import and upload activity can make receipt dates newer than play dates.

To inspect or restart on the VPS:

```sh
systemctl --user status linkedgames-dashboard.service
systemctl --user restart linkedgames-dashboard.service
curl --fail http://127.0.0.1:8944/health
```

The unit lives in `~/.config/systemd/user/linkedgames-dashboard.service` and
uses the mode-0600 report credential under
`~/.config/linkedgames-telemetry-central/`. Keep that file outside Git. To
update, fast-forward the clean checkout, run the dashboard unit tests, then
restart this unit. Do not point it at the ingestion or database-owner credential.
