# Illinois Filing Tracker: live monitor

This first backend milestone retrieves official RSS every five minutes and preserves filings across restarts. It is not yet the full iPhone app or a push-notification service.

## Deployment

The root `render.yaml` provisions one $7/month Ohio Python web service and one 1 GB disk ($0.25/month at the price checked September 22, 2026). The disk mounts at `/var/data`. There is no separate database subscription. The process deliberately refuses to start without its expected disk mount when REQUIRE_PERSISTENT_DISK=1. Deploy branch: `illinois-filing-tracker`; root directory: `tracker`. Auto-deploy is disabled.

Use one Gunicorn worker with four request threads. That worker runs the poller; a filesystem lock prevents accidentally running multiple pollers. SQLite transactions save filings, feed checkpoints, and poll history together. Restart waits until the next due check rather than resetting history. Failures use 10-, 20-, then 30-minute backoff, preserving the last successful checkpoint. At the first successful download, all existing entries are marked baseline so a future notification dispatcher can avoid old-alert floods.

SQLite-native backups are created daily under `/var/data/backups`, retaining three copies. These protect against accidental database changes, not complete disk loss. Off-host backups remain a production follow-up. Disk usage and feed freshness are reported by `/v1/status`. Unresolved overlap gaps remain flagged until investigated; the app does not pretend they were repaired by a later successful poll.

## API for the iPhone client

- `GET /v1/status`: last successful poll, stored filing count, consecutive failures, unresolved gaps, disk capacity, recent checks.
- `GET /v1/filings?limit=50`: newest discoveries first; follow `next_cursor` with `before=` for older results.
- `GET /v1/filings?after=123`: ascending discoveries for synchronization; continue with `after=next_cursor` while has_more is true. Source publication dates are not cursors.
- Optional `committee=<committee key>` filters filings.
- `GET /v1/committees?q=smith`: searchable names observed in the feed. Follow `after=next_cursor` while has_more is true. These are internal name-based keys, not official committee IDs, and this is not a complete committee directory. Official identity mapping and verified category assignments must precede public subscriptions.
- `GET /healthz`: process/database health (Render deployment health check).
- `GET /readyz`: fresh feed, no unresolved gap, adequate storage. Returns 503 for source staleness without triggering endless service restarts.
- `GET /`: human-readable status and recent filings.

The public endpoints are read-only and expose only public filings and operational status. No user accounts, device tokens, watchlists, administrator mutations, or Apple keys exist yet. Rate limits and authenticated device registration must be added before enabling user writes. Pagination bounds response sizes.

## Local checks

    cd tracker
    pip install -r requirements.txt
    python -m unittest discover -s tests -v

To run locally, set DATA_DIR to a local directory and leave REQUIRE_PERSISTENT_DISK unset. The source URL is fixed. Local Cloudflare denials do not establish Render failure: the preceding Render probe obtained three valid snapshots (check its recorded/live evidence for exact results).

## Remaining app work

1. Observe at least a day of real polling, including new filings and restarts; measure source publication lag. Five-minute polling is not a five-minute phone-delivery guarantee.
2. Import the official committee directory; verify House/Senate incumbent, current-cycle candidate, and caucus classifications. Handle renames/aliases with official IDs.
3. Add device-specific watchlists and an atomic notification outbox, APNs retry handling, deduplication, and opt-out/deletion controls.
4. Build and test the SwiftUI client on a Mac; add push entitlement, Apple Developer enrollment, APNs credentials, TestFlight, privacy disclosures, and App Store submission. No iOS binary has been built in this Linux environment.
5. Establish official-source reconciliation if more than the feed window arrives between successful polls. RSS snapshot size and current coverage are not a retention guarantee.

Feed publication dates omit time zones. Preserve them as raw source values until confirmed. Report links beginning with `~/` are normalized to HTTPS, and missing link fields use the GUID document path when possible. Blank report types stay explicitly unspecified.
