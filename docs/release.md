# Build, signing and release

## Apple organization setup

Use Salve Mundi's existing Apple Developer organization. An account administrator must confirm ownership/availability and register:

- Main app bundle ID: `nl.salvemundi.ios`.
- Widget extension bundle ID: `nl.salvemundi.ios.widgets`.
- App Group: `group.nl.salvemundi.ios` for both targets.
- Push Notifications for the app and Associated Domains for the app links.

Choose the organization team in Xcode for both targets. Keep APNs private keys on the backend only. The app must not contain a database password, Microsoft client secret or Apple provider key.

## Before testing live acceptance data

1. Review and merge the backend PR into `acceptance` only.
2. Compare acceptance and production database names without exposing credentials. Apply the documented additive migration manually only after its target is confirmed.
3. Enable the API only in the acceptance environment. Configure the authentication callback and HTTPS origin.
4. Confirm the website still signs in, registers members and handles payments as before.
5. Run the notification worker with delivery disabled first. Then allowlist test accounts and use sandbox devices with APNs credentials configured.
6. Set `MOBILE_APPLE_TEAM_ID` in the GitHub Acceptance environment; the backend serves the association file with the real Apple Team ID. Confirm activity, ticket and checkout-return links open the app.

## Validation

Run `swift test`, then build the app and widget extension for an iPhone simulator. Test Microsoft login cancellation and expiry, offline ticket display, scanner compatibility, membership pricing, full/deadline events, duplicate registration and Mollie return/webhook reconciliation.

Test APNs on a physical development iPhone. Confirm preferences, denied permission, token changes, logout and user switching. Verify both widgets in light/dark mode, with no bookings, after logout and with stale data. Check VoiceOver and large text on a small iPhone.

## TestFlight and App Store

Create an App Store Connect record in the organization, archive a signed Release build and upload through Xcode Organizer. Start with internal TestFlight testers, then expand the member pilot after the live flows pass.

TestFlight builds are distribution-signed and use production APNs tokens even when connecting to the acceptance backend. The acceptance worker defaults to sandbox-only delivery. Testing push in TestFlight therefore requires a deliberate acceptance-only configuration change allowing production APNs tokens for the same allowlisted testers; it must not switch the app to the production website or enable general-member delivery.

Before public App Store submission, prepare screenshots, support/privacy URLs, accurate privacy disclosures and reviewer access. Confirm account-lifecycle requirements and review the Microsoft organization-login policy with Apple's current guidelines. Production API promotion and changing the release app's server origin are separate decisions after the acceptance pilot.
