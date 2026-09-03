# uae_pass_kit

A complete, unofficial Flutter plugin for [UAE Pass](https://uaepass.ae) — the UAE's national digital identity SSO service.

App-to-app sign-in, full profile retrieval, document sharing (proof of presentation), PDF e-signature, token refresh and logout — built in pure Dart, on top of `webview_flutter` and `app_links`, with **no vendored native SDKs**. Android and iOS are supported (see [Platform support](#platform-support) for why web isn't).

> **Unofficial.** Not endorsed by UAE Pass, Smart Dubai Government, or the UAE government. Built from `docs.uaepass.ae`'s public integration guides and by decompiling the real official Android SDK, purely to understand the wire protocol — no proprietary code is reused.

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
  tokenExchanger: BackendTokenExchanger(), // recommended: exchange via your backend
  // or, if you'd rather skip the backend for now (see Security below for the tradeoff):
  // clientSecret: 'your-client-secret',
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

## Environments

Every UAE Pass host, install-detection identifier, and native app-callback scheme is derived from a single `UaePassEnvironment` value — nothing is ever hardcoded elsewhere in the plugin, so there's no way for a build to accidentally mix staging and production identifiers:

| | `staging` | `production` |
|---|---|---|
| Identity/signing host | `stg-id.uaepass.ae` | `id.uaepass.ae` |
| Android package (install detection) | `ae.uaepass.mainapp.stg` | `ae.uaepass.mainapp` |
| iOS URL scheme (install detection / WebView interception) | `uaepassstg` | `uaepass` |

`UaePassKit.isUaePassAppInstalled()`, `signIn()`'s WebView interception, and every `UaePassEndpoints` URL (`authorize`, `token`, `userInfo`, `logout`, `introspect`, and the `esignsp/v2` signing endpoints) all read from `config.environment` — none of them accept or construct a URL directly. `test/environment_test.dart` and `test/auth/redirect_interceptor_test.dart` run every assertion against both environments in a loop, including a dedicated regression test that a staging deep-link scheme is never mistaken for production's (and vice versa) — the direct fix for a real past incident where a `sandbox_stage` credential leaked into a production build.

## Security: where `client_secret` belongs

UAE Pass's token endpoint is a **confidential-client** endpoint (HTTP Basic `client_id:client_secret`) — there is no PKCE alternative documented anywhere. That means `client_secret` structurally does not belong in a shipped mobile or web app.

This plugin never bakes that assumption in — `UaePassTokenExchanger` and `UaePassSigningTokenExchanger` are interfaces, so the exchange step is pluggable. The recommended path for production is to implement the interface against your own backend:

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

**Don't have a backend (yet)?** Pass `clientSecret` directly to `UaePassKit` instead of `tokenExchanger`, and it builds a `UaePassDirectTokenExchanger` for you — calling UAE Pass's token endpoint straight from the app, against `staging` or `production` alike:

```dart
final uaePassKit = UaePassKit(
  config: config,
  clientSecret: 'your-client-secret', // instead of tokenExchanger:
);
```

Know what you're trading away first: `client_secret` ships inside your app binary this way, extractable by anyone who decompiles it or inspects network traffic. That's fine for an internal app, prototyping, or the sandbox — for anything else, prefer the backend-proxying `tokenExchanger` above. `UaePassSigningTokenExchanger` has the same two options (`UaePassDirectSigningTokenExchanger`, used the same way), needed only if you call `signDocument`.

## Deep Linking

This is the part of a UAE Pass integration most people get wrong first, so this section explains it slowly. If you only read one section of this README before shipping, read this one.

### The three URLs you'll see, and what each one is actually for

It's easy to conflate these — they look similar but do completely different jobs. None of the three "URL"/"scheme" values in a UAE Pass integration are interchangeable:

| | What it is | Who owns it | Where it's configured |
|---|---|---|---|
| **UAE Pass's own scheme** (`uaepass://`, `uaepassstg://`) | The custom scheme *UAE Pass's own native app* registers on the device. This plugin uses it only to (a) check whether that app is installed, and (b) recognize when the login WebView is trying to hand off to it. | UAE Pass | Nothing to configure — see [Environments](#environments). iOS still needs a one-time `LSApplicationQueriesSchemes` declaration (below) so `canOpenURL:` is allowed to check for it at all. |
| **Your app-callback scheme** (`UaePassConfig.appCallbackScheme`, e.g. `yourappscheme://`) | A scheme **you** invent and register with your own app, used only as the return address for the app-to-app handoff — the moment control comes back from the native UAE Pass app to yours. | You | `UaePassConfig(appCallbackScheme: ...)` in Dart, **plus** an Android intent-filter and an iOS `CFBundleURLTypes` entry (both below) — the plugin can't register these for you the way it does its own manifest entries, because they're specific to your app. |
| **Your OAuth `redirect_uri`** (`UaePassConfig.redirectUri`, e.g. `https://yourapp.com/uaepass/callback`) | A plain `https://` URL — UAE Pass's documented OAuth2 redirect target, carrying the final `code`/`state`. It does **not** need to be a reachable server; the plugin's WebView intercepts navigation to it before it would ever actually load. | You | `UaePassConfig(redirectUri: ...)` in Dart only — this one needs **no** platform (manifest/plist) configuration at all, since the WebView catches it internally and never lets the OS see it. |

The one you're most likely to misconfigure is the second row. Get it wrong and you'll see exactly the symptom this plugin had to be fixed for: after finishing in the native UAE Pass app, a Safari/Chrome page opens showing your `code`/`state` in the address bar, instead of control returning to your app. If you ever see that, it means the app-to-app handoff's return leg isn't reaching your app — check the platform config below first.

**Worked example, with real-shaped values.** Say your app registers the scheme `myapp`, targets `staging`, and your `redirectUri` is `https://myapp.com/callback`. Here's every URL that actually crosses the wire, in order:

1. Your app loads the authorize URL in the WebView: `https://stg-id.uaepass.ae/idshub/authorize?...&redirect_uri=https%3A%2F%2Fmyapp.com%2Fcallback&...`
2. UAE Pass's hosted page tries to navigate the WebView to its own app: `uaepassstg://authenticate?successURL=https%3A%2F%2Fstg-id.uaepass.ae%2F...&failureURL=...`
3. The plugin intercepts step 2, rewrites it, and launches: `uaepassstg://authenticate?successURL=myapp%3A%2F%2F%2Fresume_authn%3Furl%3D<the%20original%20successURL%2C%20re-encoded>&failureURL=...`
4. The user finishes in the native app. It opens the URL your app registered in step 3: `myapp:///resume_authn?url=https%3A%2F%2Fstg-id.uaepass.ae%2F...` — this is the one your Android intent-filter / iOS `CFBundleURLTypes` below must actually catch.
5. Your app receives step 4 as a deep link, unwraps the original UAE-Pass URL from its `url` query parameter, and reloads *that* into the same WebView.
6. That reload eventually redirects to `https://myapp.com/callback?code=...&state=...` — your `redirectUri` — which the WebView catches before it ever loads, and `signIn()` returns.

You never write code for steps 2–6 — they all happen inside `UaePassKit.signIn()`/`UaePassWebFlowScreen`. The only thing *you* provide is the scheme in step 3/4 (`appCallbackScheme`) and its platform registration (below), and the URL in step 1/6 (`redirectUri`).

### The three flows, and which one runs when

`UaePassKit.signIn()` picks one of these automatically, in this order — you never choose a flow directly:

**1. App-to-App** — the UAE Pass app is installed and can actually be opened.

```
Your app  →  UAE Pass app  →  user authenticates  →  UAE Pass app  →  your app (deep link)
```

The login WebView loads UAE Pass's hosted page, which tries to navigate to `uaepass://`/`uaepassstg://`. The plugin intercepts that, rewrites the success/failure URLs inside it to point at your app-callback scheme, and launches the native app. When the user finishes there, the native app opens `yourappscheme:///resume_authn?url=...`, which your app receives as a deep link (via `app_links`) and feeds back into the *same* WebView to complete the flow.

**2. App-to-Web** — the UAE Pass app is not installed.

```
Your app  →  embedded WebView  →  UAE Pass web login  →  user authenticates  →  callback  →  your app
```

No app-switching, no custom scheme involved at all. The user identifies themselves (email/mobile/Emirates ID) and confirms via a push notification on another device; the final `code` arrives directly in the same WebView. This is why the app-callback scheme setup below is still worth doing even if you expect most users to have the app — every user without it goes through this path instead, and it needs no extra config from you.

**Worked example.** The only difference from the App-to-App example above is `acr_values` on the very first URL, and that nothing after it ever leaves the WebView:

1. Your app loads: `https://stg-id.uaepass.ae/idshub/authorize?...&acr_values=urn%3Asafelayer%3Atws%3Apolicies%3Aauthentication%3Alevel%3Alow&...` — no `mobileondevice`, so UAE Pass never tries to hand off to its own app at all.
2. The user enters their UAE Pass identifier on that same hosted page and confirms via a push notification on another device.
3. UAE Pass redirects the WebView straight to `https://myapp.com/callback?code=...&state=...` — caught in-app exactly like step 6 of the App-to-App example, and `signIn()` returns. Steps 2–5 of that example (any custom scheme at all) never happen.

**3. App-to-Web fallback** — the app is installed, but the actual launch attempt fails (disabled, frozen by an MDM policy, a broken install, etc.).

```
Your app  →  UAE Pass app  →  launch fails  →  your app retries as App-to-Web (flow 2), same screen
```

The plugin detects the failed launch and automatically restarts the flow as App-to-Web *in the same screen*, rather than leaving the user stuck. You don't need to do anything for this case either — it's automatic.

In **all three flows**, control returns to (or never leaves) the exact same screen that called `signIn()` — there's no separate "resume" step your app needs to implement.

### Callback handling — what code you actually have to write

None, for the callback itself. `UaePassWebFlowScreen` owns a `package:app_links` listener internally (step 5 of the App-to-App example above) and reloads the unwrapped URL into its own WebView — there's no `onNewIntent`/`AppLinks().uriLinkStream.listen(...)` code for you to write anywhere in your app for UAE Pass's flow to work. All you provide is the *platform registration* (the intent-filter/`CFBundleURLTypes` below) so the OS routes the deep link to your app in the first place — what happens once it arrives is entirely internal.

Two things worth knowing if your app *also* has its own deep-link handling for other purposes (e.g. marketing links, other SSO providers):

- **They coexist safely.** `app_links`' `uriLinkStream` is a broadcast stream, so this plugin's internal listener and any listener you attach elsewhere in your app both receive every incoming link independently — one doesn't steal it from the other, and there's no "stream already has a listener" error.
- **This plugin ignores anything that isn't its own callback.** The internal listener checks the incoming URI's scheme against your configured `appCallbackScheme` and does nothing for anything else — so your other deep links (a different scheme, or the same scheme with a different host/path) pass through untouched.

There's currently no public hook to inject a different deep-link stream — `signIn()`/`signDocument()` always use `app_links`' process-wide singleton internally. That's deliberate: it's what makes the "you write no callback code" guarantee above hold without any setup on your part.

### Android (`android/app/src/main/AndroidManifest.xml`)

The package-visibility `<queries>` declaration for install detection (row 1 of the table above) ships in the plugin's own manifest and merges into yours automatically — you don't need to add it. You only need an intent filter for **your own** app-callback scheme (row 2):

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

iOS needs both an explicit query-schemes declaration (row 1 — Android gets this for free from the plugin's manifest, but iOS has no manifest-merging equivalent, so you must add it yourself) *and* your own URL type (row 2):

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

`yourappscheme` must be a **unique scheme you register with UAE Pass during onboarding** — never reuse a demo/shared scheme, and make sure the exact same value is passed to `UaePassConfig(appCallbackScheme: ...)` in Dart, the Android `<data android:scheme="...">` above, and the iOS `CFBundleURLSchemes` above — all three must match exactly.

### Try it yourself

`example/lib/main.dart` shows the app-callback scheme actually wired up end-to-end (`uaepasskitexample`) and displays which flow just ran (App-to-App vs. App-to-Web) after every sign-in, so you can watch flows 1 and 2 above happen for real. To see flow 3, force-stop or disable the UAE Pass app without uninstalling it, then sign in again.

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
