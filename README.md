# Dansversion ILGA connection test

This repository currently hosts a diagnostic service, not the production homepage feed.

## Verified on Render, September 16, 2026

ILGA sends its leaf certificate without the Sectigo Public Server Authentication CA OV R40 intermediate. The service supplies that public intermediate only after validating its signature against Node's existing trusted root certificates. HTTPS certificate and hostname verification remain enabled. Legislative data is fetched directly from ILGA; no reader proxy or alternate legislative provider is used.

Test completed from 01:15:23.530Z to 01:15:44.407Z: SB0501–SB0600 and HB0501–HB0600. Both range indexes and all 200 bill pages passed (202 requests, no failures). Each bill returned a title and originating-chamber chief sponsor; opposite-chamber sponsor names are retained when listed. These timings are server-side retrieval times, not homepage load times.

## Deployment

Render service: dansversion-ilga-probe, free plan, Ohio. Start command: `node server.mjs`. Build: `node --check server.mjs`. Auto-deployment is disabled. `/health` reports service health and `/probe` reports the latest startup test. The test runs once per process startup; requests cannot initiate arbitrary upstream lookups.

## Before production

Implement a shared range feed with bounded fetching, background refresh, retrieval timestamps, retained last-successful results and freshness handling. Wire the main website to it and validate navigation, refresh, new filings and amendments. The free plan sleeps after idle time and is not an always-on production solution. No paid compute or persistent storage has been authorized. The production website has not been switched to this diagnostic service.

The intermediate is a public CA certificate, not a private key. Its issuer download URL is http://crt.sectigo.com/SectigoPublicServerAuthenticationCAOVR40.crt. Its signature is independently checked against the already trusted Sectigo Public Server Authentication Root R46.
