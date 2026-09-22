# Illinois Filing Tracker — iPhone prototype

Working title; final name is undecided. Native SwiftUI, iPhone, iOS 17+. No third-party iOS dependencies.

## Open on your Mac

1. Install Xcode from the Mac App Store. Open it once and install its iOS platform components.
2. Open `IllinoisTracker.xcodeproj` in this folder.
3. Choose the **IllinoisTracker** scheme and an iPhone simulator, then press Run (triangle button). The app connects to the deployed filing service immediately.
4. For a physical iPhone, select the app target → Signing & Capabilities → your development team. Replace the provisional bundle identifier if necessary. A paid Apple Developer team is needed for the Push Notifications capability. To test browsing using a free personal team, temporarily remove the Push Notifications capability from your local target; do not enable alerts.

The project has not been compiled or run in an iOS simulator in the Linux build environment. Xcode compilation, accessibility checks and device testing are required before TestFlight. There is no installable IPA or App Store release yet.

## Included

- Recent filings with pagination, pull-to-refresh and all/following filter.
- Searchable committee directory drawn from the live feed; follow/unfollow committees.
- Persistent installation-specific watchlist stored on the backend, protected by a random credential in Keychain.
- Filing detail with links to official reports; notification taps open the relevant filing.
- Notification permission handling, registration, pause and data deletion.
- Category selection support. Categories are visibly under review and cannot be followed until verified on the server. No committee is classified from its name alone.
- Dynamic Type, native VoiceOver labels, light/dark system appearance. No ads, tracking SDK, email or password.

## Apple setup for real push notifications

1. Enroll at https://developer.apple.com/programs/enroll/ under your chosen publisher identity.
2. Register the app's Bundle ID and enable Push Notifications. Set the same ID in Xcode and the server's `APNS_TOPIC`.
3. Create APNs signing keys in Certificates, Identifiers & Profiles. New keys may be scoped to sandbox or production; configure credentials for each environment you will use. Never commit private `.p8` keys or paste them into source code.
4. In Render's environment settings, configure the credentials described in `tracker/README.md`, then deploy. Do not share private keys in public issue threads.
5. Run a signed Debug build on your iPhone, follow a committee, and enable alerts in Settings. Debug uses APNs sandbox. TestFlight/Release uses production.
6. Verify one real new filing produces one alert showing committee name and report type, tapping opens that report, unfollow/pause stops subsequent alerts, and notifications work with the app closed.

Apple registration: https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
Provider setup: https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns

## Before App Store submission

- Compile, run on simulator and physical devices, test background notification delivery end to end.
- Verify current-cycle House/Senate membership and official committee identity/aliases; activate only complete reviewed groups.
- Finalize name, app icon, screenshots, support contact, public privacy policy and App Store privacy answers. Privacy manifest is a starting declaration, not a completed App Store submission.
- Load-test queues and rate limits, add app attestation/abuse protection for public registration, establish off-host backups and operational alerting.
- Review data retention: active watchlists persist until deletion; delivery metadata is retained up to 30 days; local daily database backups rotate after three days and may contain recently deleted data until rotation.

## Acceptance check on your Mac

Build:

    xcodebuild -project IllinoisTracker.xcodeproj -scheme IllinoisTracker -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build

Then check: search → follow → Following feed → quit/relaunch → unfollow; pagination; search with spaces and ampersands; offline error/retry; large text; light/dark appearance; delete data; notification denied/allowed; cold-start notification tap. Reading and following are usable before APNs configuration. The Enable Alerts button stays disabled until server credentials are configured.
