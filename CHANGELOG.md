# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.0.5

See [Upgrading from 0.0.4](README.md#upgrading-from-004) in the README for what to check when upgrading.

- **Breaking:** requires Flutter 3.38 or later (was 3.29), for the iOS scene-delegate API used below.
- **Breaking (Android):** the bundled native sign-in library and its transitive `retrofit`, `converter-gson`, `converter-scalars`, `gson` and `android-async-http` dependencies are gone. If your app used any of these without declaring them itself, add them to your own `build.gradle`.
- **Breaking (Android):** the app-to-app return for document signing now uses the same `yourappscheme://success` / `yourappscheme://failure` URLs as sign-in, instead of `yourappscheme:///resume_authn?url=...`. An intent filter on the scheme alone (as the README shows) keeps working; one that also filtered on the `resume_authn` path must be changed. The scheme is sent to the UAE Pass app in lowercase, so the Android intent filter must use a lowercase scheme.
- **Fixed: iOS app-to-app return on UIScene apps.** The plugin now also registers as a `UIScene` delegate (`scene(_:openURLContexts:)`). Apps on the UIScene life cycle (the default for new Flutter apps, required from iOS 27) deliver deep links there rather than to `application(_:open:options:)`, so the return from the UAE Pass app was never seen and the flow stalled. Requires Flutter 3.38 or later.
- **Android sign-in now runs in the plugin's own native `WebView` dialog**, the same one used for document signing, mirroring iOS. The previously bundled sign-in library stopped returning from the app-to-app hand-off on recent devices; it and its retrofit/gson/android-async-http dependencies are removed.
  - `UaePassConfig.uaePassClientSecret` is now deprecated and ignored: sign-in no longer needs `client_secret` on any platform, so it no longer has to ship in your Android app.
  - The hand-off to the UAE Pass app changed: `uaepass://` links are retargeted at the environment's app (`uaepassstg://` on staging), and only `successurl`/`failureurl` are forwarded. In particular, the iOS-only `closeondone` is no longer passed through; with it, the Android UAE Pass app closes without returning.
- Android `WebView` dialog hardening: content stays within the system bars, display cutout and keyboard (edge-to-edge, targetSdk 35+); back goes back a page before cancelling (with predictive back on Android 13+); DOM storage is enabled; a loading indicator is shown; the `WebView` is destroyed on close; a pending flow fails instead of hanging if the activity goes away; a second concurrent flow is rejected; and the callback scheme is matched case-insensitively.
- iOS: `uaepass://` links are now retargeted at the environment's app the same way, fixing the staging hand-off. The web view respects the bottom safe area, and the presenting view controller is found even when no window is key yet.
- The returned `state` is now checked against the one sent, on both platforms.
- `logout()` also clears `WebView` storage on Android, not only cookies.
- The plugin's `AndroidManifest.xml` now declares `INTERNET` and drops the deprecated `package` attribute.

## 0.0.4

- **Breaking: the browser/native-app hand-off for `signIn()` and `signDocument()` now runs natively**, replacing the pure-Dart `webview_flutter` + `url_launcher` + `app_links` implementation, which proved unreliable at surviving the deep-link return — the flow could get stuck after control bounced out to the UAE Pass app or the system browser and never come back.
  - **Android** uses a bundled native library for `signIn()`, which owns the app-switch and `onNewIntent` resume internally. `signDocument()`'s WebView step now runs in a native `android.webkit.WebView` dialog using the same app-switch/deep-link mechanics.
  - **iOS** drives both flows through an in-app `WKWebView` (never Safari), with the plugin registered as the `UIApplication` delegate (`application(_:open:options:)`) for the app-to-app return (fixed `yourscheme://success`/`yourscheme://failure` sentinel URLs; the actual destination is cached in native state, not round-tripped through the returning deep link).
  - Every plain HTTPS call with no browser/deep-link involved (token exchange, profile fetch, document upload/poll/download, the logout endpoint call) is unchanged, still pure Dart.
- **Breaking:** `UaePassConfig` gains `uaePassClientSecret` (optional in the constructor, but required to call `signIn()` on Android) — the bundled Android sign-in library requires `client_secret` up front just to obtain an authorization code. iOS's sign-in flow does not need it.
- **Breaking:** removed `UaePassRedirectInterceptor`, `UaePassWebFlowScreen`, and the public constants `kUaePassAcrMobileOnDevice`/`kUaePassAcrPushNotificationFallback` — their responsibilities moved into native code and `UaePassKit` itself.
- **Behavior change:** dropped the 0.0.3 `onNativeAppLaunchFailed` auto-fallback (installed-but-unopenable silently retrying as App-to-Web in the same screen) — the native implementation has no equivalent hook, so that case now surfaces as a normal sign-in failure/cancellation instead.
- Removed the now-unused `webview_flutter` and `app_links` dependencies, and the unused `crypto` dependency (state generation uses `dart:math`'s `Random.secure()`, not `package:crypto`).
- `logout()` now clears cookies via native code (Android's `CookieManager`, iOS's `WKWebsiteDataStore`) instead of `webview_flutter`'s `WebViewCookieManager`.
- README rewritten throughout to describe the native architecture, including the new `uaePassClientSecret` requirement and the `android:launchMode="singleTask"` manifest guidance the native deep-link resume depends on.

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

- App-to-app sign-in via the documented WebView-interception flow, in pure Dart, with graceful cancel/decline handling.
- Pluggable token exchange (`UaePassTokenExchanger`) so `client_secret` never has to ship in a mobile/web build; a direct sandbox-only implementation is included for local development.
- Full profile retrieval (`getProfile`) covering the complete 37-field profile, including Arabic/English name pairs and home-address decomposition.
- Token refresh (`refreshAccessToken`) using the `refresh_token` UAE Pass returns.
- Real logout (`logout`) that clears local WebView session state and notifies UAE Pass's `/idshub/logout` endpoint.
- Document sharing / proof-of-presentation (`requestDocumentShare`) as a cancelable `Stream<DocumentShareStatus>`, delegating the HMAC-signed backend calls to your own server via `UaePassDocumentShareBackend`.
- PDF e-signature (`signDocument`) wrapping the `esignsp/v2` flow, including multi-signer field placement and Emirates ID signature-image embedding.
- Native install detection (`isUaePassAppInstalled`) with correct Android 11+ package-visibility manifest declarations shipped in the plugin itself.
- Environment configuration limited to exactly `staging` and `production` — the only two UAE Pass issues credentials for.
- Auto-generated, cryptographically random `state` per sign-in attempt.
- Full public API documentation coverage.
