# Illinois Filing Tracker · Version 15

## Install the update
Unzip the download, open IllinoisTracker.xcodeproj in Xcode, select your iPhone or simulator, and press Run. Use the same bundle identifier and signing team to preserve installation preferences. No Terminal steps are required.

## Donor-history removal
Donor search, cross-committee donor histories, and donor follows are removed. Contributor names and amounts remain available in individual filings. Private lists track committees only.

## Compact committee lists
Sort and follow controls share one row. Committee data appears immediately below. Tap the info button for freshness, following and estimate details. Stale-data notices and errors remain visible.

## New observer tools
- Committee balances separate monetary A-1 receipts from in-kind support. Estimates add only monetary receipts to the most recent quarterly cash and investments and do not subtract unreported spending. Period-end dates govern the cutoff. Ambiguous duplicate or amended A-1 disclosures are flagged for review rather than silently counted.
- Settings → Alert filters, digests & quiet hours: every filing, quarterly only, or individual A-1 contributions meeting a minimum; immediate, 8 AM, or 6 PM delivery; quiet hours use America/Chicago. iOS groups alerts by committee. Digests link to a delivered-alert inbox.
- Watchlist → My private lists: named lists of committees, new-report counts since the last visit, explicit mark-as-seen, rename and membership editing. Add a committee from its detail page. List members participate in alert delivery when push is enabled.
- Share reports or individual contributions with stable public browser links. Export quarterly summaries, itemized schedules and A-1s as CSV after opening them in the app. No account or app is required for recipients.
- Saved verified report and directory data can be used during network failures, with visible freshness labels. Malformed directory rows are skipped with a visible warning instead of breaking every Home destination. Native directory decoding is checked in CI.

## Current operational boundaries
Apple push delivery still requires the publisher's Apple Developer membership, signing entitlements, and APNs credentials on the server. Preferences can be configured now; no claim of physical iPhone delivery is made before that setup.


Private lists belong to this installation; they do not sync across devices. Public sharing exposes only public filing data, never private lists or credentials. Settings → Delete my data removes server-side preferences, lists and push registration.

## Build and verify
The app uses native SwiftUI and Foundation with no third-party iOS dependencies. Minimum iOS 17. Automated checks validate local and live directory responses using the native models, then compile the simulator app and capture previews. Backend regression checks cover calculations, identity, private-list isolation, notification scheduling, CSV safety, and data ingestion.
