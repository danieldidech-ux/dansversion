# Illinois RSS access test

Render workspace: My Workspace (explicitly authorized).
Service: illinois-rss-access-test, srv-daouvamgekts73f5vd3g, Ohio, free plan, auto-deploy disabled.
Source commit: 46d90e67f6031b1f45063c8fa4836ea3837e5317.
Status: https://illinois-rss-access-test.onrender.com/status

## Verified September 22, 2026 (UTC)

- 03:02:49: HTTP 200; valid RSS; 1,000 unique filing GUIDs; 0.532 seconds.
- 03:07:49: HTTP 200; valid RSS; 1,000 unique filing GUIDs; 0.132 seconds.
- Second check: 999 overlapping identifiers and one new filing identifier. The first snapshot's latest raw publication date was Mon, 21 Sep 2026 20:58:42; the second's was Mon, 21 Sep 2026 22:01:49.
- No apparent gap between snapshots. New data was retrieved directly from the state feed; the uploaded attachment was not deployed or used as a live fallback.
- Third check remains scheduled for 03:12:49 UTC. This record captures only the two checks actually observed at the time of writing.

Conclusion: live retrieval and new-item detection work from this Render service. The earlier Cloudflare 403 responses from the ChatGPT environment are not a universal denial of this public feed. The precise reason for different access behavior is not established.

Limits: this short test is not a production reliability guarantee. Raw feed dates omit time zones, and source refresh/cache delay has not been measured. No five-minute filing-to-phone SLA is established. Notifications have not been implemented. A longer test across active filing hours and a filing deadline remains necessary. The feed has a rolling window of 1,000 entries in these snapshots; catch-up/reconciliation needs an official source if that window is missed.

The diagnostic stops fetching after three checks; process restarts start a fresh diagnostic. Free hosting sleeps after inactivity and discards its local files. Use an always-on service with persistent filing/delivery state for production. No paid resources were enabled during this test.

Sources for hosting limitations and pricing: https://render.com/docs/free and https://render.com/pricing (checked September 22, 2026). The pricing page lists 0.5c-512mb at $7/month and persistent disks at $0.25/GB/month. Hosting budget excludes Apple membership, usage overages, and optional backup services.
