# Working on the iPhone app

- Keep this an independent native iPhone repository. Do not add website/backend source here.
- Backend work belongs on a website branch based on `acceptance`, targeting `acceptance` only.
- Keep acceptance as the app's default origin. Production promotion requires a separate user decision.
- Never commit real member data, authentication secrets, APNs private keys or signing files.
- Preserve server authority over identity, membership, pricing, capacity, payment and QR validity.
- Run `swift test` and an unsigned app/widget build after meaningful changes. Report unavailable device or service checks honestly.
