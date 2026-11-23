# Dan’s Version legislative data services

The default branch contains the Render connection diagnostic and the shared legislative feed. The published dansversion.com workspace has its own Sites repository.

## Verified on Render, September 16, 2026

ILGA sends its leaf certificate without the Sectigo Public Server Authentication CA OV R40 intermediate. The service supplies that public intermediate only after validating its signature against Node's existing trusted root certificates. HTTPS certificate and hostname verification remain enabled. Legislative data is fetched directly from ILGA; no reader proxy or alternate legislative provider is used.

Test completed from 01:15:23.530Z to 01:15:44.407Z: SB0501–SB0600 and HB0501–HB0600. Both range indexes and all 200 bill pages passed (202 requests, no failures). Each bill returned a title and originating-chamber chief sponsor; opposite-chamber sponsor names are retained when listed. These timings are server-side retrieval times, not homepage load times.

## Deployment

Render service: dansversion-ilga-probe, free plan, Ohio. Start command: `node server.mjs`. Build: `node --check server.mjs`. Auto-deployment is disabled. `/health` reports service health and `/probe` reports the latest startup test. The test runs once per process startup; requests cannot initiate arbitrary upstream lookups.

## Reader integration

Start the authenticated feed with `ILGA_FEED_TOKEN` configured and `node feed.mjs`. Keep its token in the website server environment. Browser requests go through the same-origin website server. The existing diagnostic continues to use `server.mjs`.

| GET endpoint | Reader behavior |
| --- | --- |
| `/range-index?url=...` | Return the official range’s numbers, titles and source URLs as soon as the index arrives. Use the link in each row, including ILGA’s internal IDs. |
| `/summary?url=...` | Fetch detail for a visible or opened bill. Display `retrievedAt`, `stale` and `sponsorStatus` separately. A pending or unavailable sponsor is not a verified absence. |
| `/members?chamber=House` or `Senate` | Return the current roster, districts and profile links from the official list in one request. Load an individual’s service history when their profile opens or a service-based sort is selected. |
| `/page?url=...` | Fetch the official page for an explicit detail request. |
| `/range?url=...` | Compatibility endpoint that waits for range details. Use the progressive endpoints for interactive lists. |
| `/status` | Authenticated counters for shared requests, failures, queueing, upstream latency and last verified resources. `/health` reports process liveness. |

The feed performs no startup prefetch. Memory is bounded, simultaneous requests share work and the upstream deadline includes time in the queue. Normalized results retain their original verification times after failed refreshes. A process restart starts with no saved data. Use `refresh=1` for an explicit new check.

Run `node --test reader.test.mjs` to verify cold lists, partial results, refresh failure, official link preservation, concurrency and roster loading. The separate published website must adopt the endpoints and verify click-to-usable time and back navigation on phone and desktop before rollout. The current free Render diagnostic sleeps after idle time.

The intermediate is a public CA certificate, not a private key. Its issuer download URL is http://crt.sectigo.com/SectigoPublicServerAuthenticationCAOVR40.crt. Its signature is independently checked against the already trusted Sectigo Public Server Authentication Root R46.
