# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
