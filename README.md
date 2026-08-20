# uae_pass_kit

A complete, unofficial Flutter plugin for [UAE Pass](https://uaepass.ae) — the UAE's national digital identity SSO service.

App-to-app sign-in, full profile retrieval, document sharing (proof of presentation), PDF e-signature, token refresh and logout — built in pure Dart, on top of `webview_flutter` and `app_links`, with **no vendored native SDKs**. Android and iOS are supported (see [Platform support](#platform-support) for why web isn't).

> **Unofficial.** Not endorsed by UAE Pass, Smart Dubai Government, or the UAE government. Built from `docs.uaepass.ae`'s public integration guides and by decompiling the real official Android SDK, purely to understand the wire protocol — no proprietary code is reused.

## Why pure Dart, no vendored SDK

UAE Pass's own Android AAR and iOS framework are wrappers around a documented WebView-interception + URL-scheme-launch + plain HTTP flow — nothing cryptographically proprietary. Implementing that flow directly in Dart means:

- No committed binary blobs that silently go stale (a real, observed problem: the current `docs.uaepass.ae` Android SDK page describes methods that don't exist in the community-distributed AAR).
- No CocoaPods/podspec packaging fragility — the most common class of integration-breaking bug in the ecosystem's existing wrappers.
- One shared implementation of the interception/redirect logic across both platforms, instead of two native implementations that can silently diverge in behavior.
- Native platform code is reduced to the one thing that's inherently platform-specific: checking whether the UAE Pass app is installed.

## Features

- **Sign-in** — the documented app-to-app WebView-interception flow, with graceful, typed handling of cancellation/decline (never a crash).
- **Token exchange & refresh** — pluggable, so `client_secret` never has to ship in your app.
- **Full profile retrieval** — the complete field set found across both official native SDKs (EN/AR name pairs, Emirates ID, home address, etc.), not a partial hand-picked subset.
- **Logout** — clears local session state and notifies UAE Pass's logout endpoint.
- **Document sharing (proof of presentation)** — a cancelable polling stream, delegating the HMAC-signed backend calls to your own server.
- **PDF e-signature** — the `esignsp/v2` flow, including multi-signer field placement.
- **Install detection** — correct Android 11+ package-visibility handling out of the box.
- **Environment safety** — exactly `staging` and `production`, the only two UAE Pass actually issues credentials for.

## Security: where `client_secret` belongs

UAE Pass's token endpoint is a **confidential-client** endpoint (HTTP Basic `client_id:client_secret`) — there is no PKCE alternative documented anywhere. That means `client_secret` structurally does not belong in a shipped mobile or web app.

This plugin never bakes that assumption in. `UaePassTokenExchanger` and `UaePassSigningTokenExchanger` are interfaces — `UaePassDirectTokenExchanger`/`UaePassDirectSigningTokenExchanger` (direct on-device exchange) are provided **only for local development against UAE Pass's public staging POC credentials** (`sandbox_stage`/`sandbox_stage`). For any production integration, implement the interface against your own backend:

```dart
class BackendTokenExchanger implements UaePassTokenExchanger {
  @override
  Future<UaePassTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
  }) async {
    final json = await myApiClient.post('/uaepass/token', body: {'code': code});
    return UaePassTokenResponse.fromJson(json);
  }

  @override
  Future<UaePassTokenResponse> refreshToken({required String refreshToken}) async {
    final json = await myApiClient.post('/uaepass/refresh', body: {'refresh_token': refreshToken});
    return UaePassTokenResponse.fromJson(json);
  }
}
```

`UaePassDocumentShareBackend` follows the same pattern — UAE Pass's Data Sharing Authorization API is HMAC-signed and must be called server-to-server.

## Setup

### Android (`android/app/src/main/AndroidManifest.xml`)

The package-visibility `<queries>` declaration for install detection ships in the plugin's own manifest and merges automatically — you don't need to add it. You only need an intent filter for **your own** app-callback scheme (used during the app-to-app handoff, distinct from your OAuth `redirect_uri`):

```xml
<activity ...>
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="yourappscheme"/>
  </intent-filter>
</activity>
```

### iOS (`ios/Runner/Info.plist`)

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>uaepass</string>
  <string>uaepassstg</string>
</array>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>com.yourcompany.yourapp</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>yourappscheme</string>
    </array>
  </dict>
</array>
```

`yourappscheme` must be a **unique scheme you register with UAE Pass during onboarding** — never reuse a demo/shared scheme.

## Quick start

```dart
final config = UaePassConfig(
  clientId: 'your-client-id',
  redirectUri: Uri.parse('https://yourapp.com/uaepass/callback'),
  appCallbackScheme: 'yourappscheme',
  environment: UaePassEnvironment.staging, // or .production
);

final uaePassKit = UaePassKit(
  config: config,
  tokenExchanger: BackendTokenExchanger(), // never UaePassDirectTokenExchanger in production
);

final result = await uaePassKit.signIn(context);
switch (result) {
  case UaePassAuthSuccess(:final code):
    final token = await uaePassKit.exchangeAuthorizationCode(code);
    final profile = await uaePassKit.getProfile(token);
    print(profile.fullNameEn);
  case UaePassAuthCancelled():
    break; // user backed out — not an error
  case UaePassAuthFailure(:final exception):
    print('Sign-in failed: ${exception.message}');
}
```

See `example/lib/main.dart` for a runnable app using UAE Pass's public staging sandbox credentials.

## Platform support

| Platform | Status |
|---|---|
| Android | ✅ |
| iOS | ✅ |
| Web | Not implemented here. UAE Pass documents a materially different flow for web (a plain full-page OAuth2 redirect against a real, reachable `redirect_uri`), not the WebView-interception app-to-app dance this package implements. `UaePassEnvironment.endpoints` and the token/profile/logout calls work unchanged on any platform if you want to drive that redirect flow yourself. |

## Development

```
flutter analyze
dart format --set-exit-if-changed .
flutter test
```
