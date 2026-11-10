# Verification — 10 November 2026

The app and widgets were built with Xcode 27.2. The minimum deployment target is iOS 18; visual checks used an iPhone 17e simulator running iOS 27.2.

Passed locally:

- Eight Swift tests for API decoding/errors, activity rules, links and widget data minimization.
- Unsigned Debug simulator build of the app and widget extension.
- Unsigned Release iPhone build of the app and widget extension.
- Simulator launch and home-screen inspection with the explicitly labelled synthetic-data demonstration mode.
- Backend: six authentication/environment policy tests and fourteen notification/APNs worker tests.
- Backend: frontend and finance-service TypeScript checks and targeted lint checks.
- Local HTTP checks using dummy credentials: mobile endpoints return 404 in production mode even when their enable flag is true; acceptance private profile returns JSON 401 without a credential; configured acceptance association route returns 200 with the expected application ID and paths.

The test server used no real database, Microsoft or Apple credentials. No production service was changed, no migration was applied and no notification was sent.

Still required before a member pilot: live Microsoft sign-in and revocation, acceptance-database verification/migration, paid/free bookings and interrupted Mollie checkout, real scanner compatibility, APNs on signed devices, widget placement/update behavior and accessibility/device testing. An unresolved payment-creation timeout returns a pending error and preserves the booking to avoid a duplicate charge; verify eventual payment recovery with the acceptance finance service before enabling the pilot.

Apple signing, TestFlight upload and App Store submission are not completed by an unsigned local build. Follow [release setup](release.md).

## Activiteitenbeheer en widgetuitbreiding

De uitbreiding is gecontroleerd met 23 Swift-tests, 15 daadwerkelijke-broncode-tests voor beheertoegang/mutaties/widgetrechten en unsigned Debug/Release-builds van app en widgets. Backendtests gebruiken een tijdelijke SQLite-database en vervangers voor externe services; geen echte deelnemers, betalingen of e-mails worden aangemaakt. Negatieve tests controleren vreemde activiteit-/deelnemer-ID’s, commissie- en leidersrechten, ingetrokken widgettoegang, onbetaalde tickets, rollback en ontvangers uit de serverdatabase.

Fysieke camera/QR-scans, gedeelde Keychain met echte provisioning, actuele iOS-widgetplanning en een goedgekeurde testmail vragen nog om een controle op het toestel.
