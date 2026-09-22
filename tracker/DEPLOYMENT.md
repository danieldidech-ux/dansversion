# Live monitor

Verified September 22, 2026 (UTC).

- URL: https://illinois-filing-tracker.onrender.com/
- Render service: srv-daov9negekts73f725ag, Ohio, Starter.
- Persistent disk: dsk-daova0g0cd8s73b6029g, 1 GB mounted at /var/data.
- Estimated base hosting: $7.25/month ($7 service + $0.25 disk).
- Source polling: 300 seconds. Failed requests use backoff.
- Deployed code: 09a71d86220d0fd65ea241a18de2804b17d7e4ff.
- Successful deployment: dep-daovca79b27s73eoit3g.

## Verification

Ten unit tests passed. A local Gunicorn preload smoke test verified collector startup in the serving worker and persistence across two server processes. Collector initialization was moved to the serving process to avoid starting a thread in a preloading master.

The live database initially saved 1,000 filings at 03:25:23 UTC. After redeployment, the original first-seen timestamps and initial poll checkpoint remained intact. The stored count remained 1,000, with zero recorded failures or gaps; /healthz and /readyz returned successful results. This proves the observed retrieval and restart behavior, not uninterrupted long-term reliability.

## Scope

This deployment is a read-only filing ingestion service and status page. Native iPhone UI, watchlists, verified committee/category membership, device registration, and Apple push notification delivery remain to be implemented. Feed committee names are not official committee IDs. Apple Developer enrollment remains necessary for App Store distribution and production push notifications.
