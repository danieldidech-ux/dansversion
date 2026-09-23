## Version 9 home design

Home uses blue Democratic cards and red Republican cards, with chamber labels, architectural motifs, gradients, and large type. Party colors remain identifiable in every theme.

## Version 8 navigation

Home opens with four large caucus buttons. Each opens its committee list with a back button and the existing sorting options. Latest Reports is the second tab. Modern Civic, Night Ledger, and Pink Mode are supported. Quarterly itemized receipts and expenditures can be sorted alphabetically or by amount, highest first.

# Illinois Filing Tracker — iPhone prototype

Working title; final name is undecided. Native SwiftUI, iPhone, iOS 17+. No third-party iOS dependencies.

## Open on your Mac

1. Install Xcode from the Mac App Store. Open it once and install its iOS platform components.
2. Open `IllinoisTracker.xcodeproj` in this folder.
3. Choose the **IllinoisTracker** scheme and an iPhone simulator, then press Run (triangle button). The app connects to the deployed filing service immediately.
4. For a physical iPhone, select the app target → Signing & Capabilities → your development team. Replace the provisional bundle identifier if necessary. A paid Apple Developer team is needed for the Push Notifications capability. To test browsing using a free personal team, temporarily remove the Push Notifications capability from your local target; do not enable alerts.

The project passed an Xcode 15.4 simulator build and launched successfully with ad-hoc signing on a GitHub macOS runner. The simulator displayed real filings from the deployed backend. Physical-device, accessibility and end-to-end notification testing are still required before TestFlight. There is no signed installable IPA or App Store release yet.

Native report build evidence: https://github.com/danieldidech-ux/dansversion/actions/runs/35755061709

The live backend returned the verified Rezin filing as $39,223.24 from Illinois Republican Party, in-kind contribution, received September 20, 2026, description Direct mail, vendor Linc Strategy LLC. All 28 backend tests pass, including the real report fixture and incomplete/mismatched-report safeguards.

## Included

- Recent filings with pagination, pull-to-refresh and all/following filter.
- Searchable committee directory drawn from the live feed; follow/unfollow committees.
- Persistent installation-specific watchlist stored on the backend, protected by a random credential in Keychain.
- A-1 filing details use native contribution cards: amount, contributor, monetary/in-kind type as reported, date, description, vendor and expandable addresses. Multiple entries each have a card and an exact decimal total. Follow and Open official report actions are below the contents. Notification taps open the relevant filing.
- Notification permission handling, registration, pause and data deletion.
- Caucuses tab with House/Senate and Democrat/Republican selectors, last-name/district sorting, pinned leader/caucus funds, committee filing pages and individual/group following. Lists use the publisher-approved review draft and selected candidate substitutions.
- Dynamic Type, native VoiceOver labels, light/dark system appearance. No ads, tracking SDK, email or password.

## Apple setup for real push notifications

1. Enroll at https://developer.apple.com/programs/enroll/ under your chosen publisher identity.
2. Register the app's Bundle ID and enable Push Notifications. Set the same ID in Xcode and the server's `APNS_TOPIC`.
3. Create APNs signing keys in Certificates, Identifiers & Profiles. New keys may be scoped to sandbox or production; configure credentials for each environment you will use. Never commit private `.p8` keys or paste them into source code.
4. In Render's environment settings, configure the credentials described in [the backend setup guide](https://github.com/danieldidech-ux/dansversion/blob/illinois-filing-tracker/tracker/README.md), then deploy. Do not share private keys in public issue threads.
5. Run a signed Debug build on your iPhone, follow a committee, and enable alerts in Settings. Debug uses APNs sandbox. TestFlight/Release uses production.
6. Verify one real new filing produces one alert showing committee name and report type, tapping opens that report, unfollow/pause stops subsequent alerts, and notifications work with the app closed.

Apple registration: https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
Provider setup: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns

## Before App Store submission

- Compile, run on simulator and physical devices, test background notification delivery end to end.
- Continue refining the approved directory, unresolved committees, historical names and official-ID aliases before claiming comprehensive coverage.
- Finalize name, app icon, screenshots, support contact, public privacy policy and App Store privacy answers. Privacy manifest is a starting declaration, not a completed App Store submission.
- Load-test queues and rate limits, add app attestation/abuse protection for public registration, establish off-host backups and operational alerting.
- Review data retention: active watchlists persist until deletion; delivery metadata is retained up to 30 days; local daily database backups rotate after three days and may contain recently deleted data until rotation.

## Acceptance check on your Mac

Build:

    xcodebuild -project IllinoisTracker.xcodeproj -scheme IllinoisTracker -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

Then check: search → follow → Following feed → quit/relaunch → unfollow; pagination; search with spaces and ampersands; offline error/retry; large text; light/dark appearance; delete data; notification denied/allowed; cold-start notification tap. Reading and following are usable before APNs configuration. The Enable Alerts button stays disabled until server credentials are configured.

## Installing this update

Close the older project in Xcode. Unzip the updated source download into a new folder, open its `IllinoisTracker.xcodeproj`, select your iPhone simulator and press Run. Xcode will replace the simulator app using the same bundle identifier; its existing Keychain credential and server watchlist remain available. If you customized signing for a physical phone, reselect your team in Signing & Capabilities.

A-1 contents are read by the existing backend from the filing-specific official report and cached for one hour. The app shows native cards, without embedding the state website. Other formats, including PDFs and quarterly reports, currently show an explicit unavailable message and the official link. Unrecognized or paginated A-1 tables fail closed instead of displaying incomplete totals. State-site failures retain a retry option and the official link.

## Report type colors (v4)

Report labels use consistent tinted badges in both the feed and detail header: A-1 blue, D-1 purple, D-2 Quarterly green, and D-2 Final orange. Amendments keep their report category color. Other filing types are neutral. Text labels remain visible and colors adapt to light and dark appearances.

## Caucus directory (v5)

The directory is fetched from `/v1/directory`. Revisions to the server list appear after pulling to refresh, without a new iPhone build. Group follows automatically use revised membership. The approved draft retains historical-name caveats and one missing committee; it is not a complete official candidate roster. Committee filing lookup currently uses normalized committee names, so renamed committees require an explicit directory update.

## Version 6

Adds the complete official committee report index with automatic scrolling, a quarterly cash/investments plus post-quarter A-1 summary, and estimated-cash sorting (highest first, unknown values last). Loading occurs on the server and the first request can take time. Unresolved committee identities, unreadable reports, and ambiguous A-1 amendments show unavailable rather than zero. Estimates are not reconciled bank balances and may include noncash A-1 contributions. Senate Democratic Victory Fund is removed.

## Version 7: native quarterly reports and appearance

Modern Civic is the default light theme. Settings → Appearance also offers Night Ledger, Pink Mode, and Follow iPhone appearance. Preferences persist between launches.

Electronic D-2 quarterly reports display a native financial summary. Tap an itemized category to browse and search receipts, expenditures, transfers, or investments without leaving the app. Unitemized totals remain separate. Official-source links are available at the bottom. PDF-only or unrecognized reports retain a clear unavailable state rather than invented data.
