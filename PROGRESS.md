# RouteShield — PROGRESS

## Environment check (2026-10-30)
- Installed: Node 22, npm 10, Java 21, git
- NOT installed / unavailable: Flutter, Dart, Android SDK. pub.dev and storage.googleapis.com are unreachable from this sandbox, so `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk` CANNOT run here.
- MongoDB Atlas unreachable from this sandbox; DB-backed endpoints can't be integration-tested here.

## Done and tested
- [x] backend/ scaffold (TypeScript 5.6, Jest)
- [x] Segment-wise safety engine (src/services/safetyEngine.ts): explainable, configurable, risk and confidence separate, missing data => unknown (never "safe"), freshness decay. 5 unit tests.

## Remaining
- [ ] Express app, JWT auth, validation, rate limiting, error handling
- [ ] Mongoose models (User, TrustedContact, Journey, RouteAssessment, SafetyReport, Notification, Preferences)
- [ ] Route comparison + recommendation service (Google Routes API + labelled demo provider)
- [ ] Safe Haven (Places API + demo provider), reports moderation/expiry, safety plan compiler, check-in escalation
- [x] Flutter frontend source WRITTEN (32 Dart files, ~2.5k lines): theme tokens, API client with labelled demo fallback, Riverpod providers, 17 screens + glass bottom nav, deviation detector, safety-plan compiler, simulated call, battery mode. NOT compiled/analyzed/run (no Flutter SDK here). Only a crude bracket/import check was done. Pure-Dart tests written in mobile/test/logic_test.dart but NOT run.
- [ ] Run `flutter create`, `flutter pub get`, `flutter analyze`, `flutter test` on a real machine and fix errors (see mobile/README.md)
- [ ] README, API docs, architecture, scoring doc, team split, .env.example
