# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.0.3

- **Fixed app-to-app deep-linking never returning to the app.** The app-callback URL built for the native UAE Pass app's handoff was shaped `yourapp://resume_authn?url=...` (two slashes, `resume_authn` as the host) instead of UAE Pass's own documented `yourapp:///resume_authn?url=...` (three slashes, empty host, `/resume_authn` as the path). UAE Pass's own integration docs warn this exact mismatch causes the native app to fall back to opening the callback in the system browser instead of routing back into your app. Fixed to match the documented format exactly.
- Added an `onNativeAppLaunchFailed` fallback: when the UAE Pass app is detected as installed but the actual launch attempt fails (disabled, frozen, a broken install, etc.), `signIn()` now falls back to the App-to-Web flow in the same screen instead of cancelling the sign-in outright — completing UAE Pass's full three-way flow-selection matrix (installed / not installed / installed-but-unopenable).
- Removed the unused `web` package dependency (never actually imported anywhere in the plugin).
- README: added a dedicated Deep Linking section covering every platform's setup, the three flow types, and the distinction between UAE Pass's install-detection schemes and your own app-callback scheme.
- Example app: demonstrates all three deep-linking flows.

## 0.0.2

- New `UaePassKit` constructor shortcuts, `clientSecret` and `signingClientSecret` — a single-parameter alternative to implementing `UaePassTokenExchanger`/`UaePassSigningTokenExchanger` yourself, building the direct exchangers for you against either `staging` or `production`. Passing both a shortcut and its exchanger, or neither, now throws a `UaePassConfigurationException` immediately instead of failing silently.
- Fixed a real dependency bug: the `url_launcher` lower bound (`>=6.0.0`) allowed versions that predate the `canLaunchUrl`/`launchUrl`/`LaunchMode` functional API this plugin actually calls; raised to `>=6.1.0`.
- Bumped all dependency version constraints to their current latest releases (`web`, `plugin_platform_interface`, `webview_flutter`, `app_links`, `http`, `crypto`, `url_launcher`, `webview_flutter_platform_interface`).
- Relicensed from MIT to Apache-2.0.
- Raised Android `compileSdk` to 37 and `minSdk` to 28; raised the iOS deployment target from 15.0 to 16.0 (podspec, `Package.swift`, and the example Xcode project).
- Removed the `mockito` and `mocktail` test dependencies in favor of hand-written fakes; removed a stale Kotlin plugin test that exercised a method (`getPlatformVersion`) no longer present in the plugin.
- Trimmed the `pubspec.yaml` description to pub.dev's recommended 60–180 character range.
- README: moved Quick start to the top of the page; added an Environments section documenting how every URL/package-ID/scheme is derived per environment and cross-referencing the test coverage that guards against a staging/production mixup.
- Example app: added an install-detection status indicator, a working refresh-token demo, a working e-signature demo against the public sandbox, and a wired-up (but backend-less) document-sharing demo that surfaces the real `UaePassConfigurationException`.

## 0.0.1

Initial release. Full feature set, no staged/partial functionality:

- App-to-app sign-in via the documented WebView-interception flow, in pure Dart (no vendored native SDKs), with graceful cancel/decline handling.
- Pluggable token exchange (`UaePassTokenExchanger`) so `client_secret` never has to ship in a mobile/web build; a direct sandbox-only implementation is included for local development.
- Full profile retrieval (`getProfile`) covering the complete 37-field union found across both official native SDKs, including Arabic/English name pairs and home-address decomposition.
- Token refresh (`refreshAccessToken`) — a capability neither official native SDK implements despite capturing `refresh_token`.
- Real logout (`logout`) that clears local WebView session state and notifies UAE Pass's `/idshub/logout` endpoint.
- Document sharing / proof-of-presentation (`requestDocumentShare`) as a cancelable `Stream<DocumentShareStatus>`, delegating the HMAC-signed backend calls to your own server via `UaePassDocumentShareBackend`.
- PDF e-signature (`signDocument`) wrapping the `esignsp/v2` flow, including multi-signer field placement and Emirates ID signature-image embedding.
- Native install detection (`isUaePassAppInstalled`) with correct Android 11+ package-visibility manifest declarations shipped in the plugin itself.
- Environment configuration limited to exactly `staging` and `production` — the only two UAE Pass issues credentials for.
- Auto-generated, cryptographically random `state` per sign-in attempt.
- Full public API documentation coverage.
