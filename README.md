# uae_pass_kit

A complete, unofficial Flutter plugin for [UAE Pass](https://uaepass.ae) — the UAE's national digital identity SSO service.

App-to-app sign-in, full profile retrieval, document sharing (proof of presentation), PDF e-signature, token refresh and logout. Sign-in and document-signing's browser/native-app hand-off run **natively** — an in-app `WebView` on Android, an in-app `WKWebView` on iOS — because that hand-off proved unreliable when driven from Dart (`webview_flutter` + `url_launcher` + `app_links`): control would bounce out to the UAE Pass app or system browser and never come back. Every other capability (token exchange, profile fetch, document upload/poll/download) is plain Dart HTTPS calls. Android and iOS are supported (see [Platform support](#platform-support) for why web isn't).

> **Unofficial.** Not endorsed by UAE Pass, Smart Dubai Government, or the UAE government. Built from `docs.uaepass.ae`'s public integration guides. Both platforms implement the publicly documented app-to-app protocol (see [Why native](#why-native-for-the-browserapp-switch-hand-off)).

**Contents:** [Quick start](#quick-start) · [Why native](#why-native-for-the-browserapp-switch-hand-off) · [Features](#features) · [Environments](#environments) · [Security](#security-where-client_secret-belongs) · [Deep Linking](#deep-linking) · [Platform support](#platform-support) · [Upgrading from 0.0.4](#upgrading-from-004) · [Development](#development)

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

## Why native for the browser/app-switch hand-off

An earlier version of this plugin implemented the entire flow in pure Dart (`webview_flutter` + `url_launcher` + `app_links`). In practice, the deep-link return from the native UAE Pass app (or the system browser) frequently never reached the app — the flow got stuck after control bounced out. The root cause is structural: that hand-off depends on the OS delivering an `onNewIntent`/`application(_:open:)` event back to the *same* running Activity/engine instance, and Dart-side plugins (`app_links`'s stream subscription, a `Navigator`-pushed WebView route) are exactly the layer most likely to have already been torn down or missed the delivery by the time it arrives.

So the parts of the flow that involve that hand-off now run natively, where the platform's own deep-link delivery mechanism is handled directly, with no Dart-side listener in between:

- **Android** drives sign-in and document-signing through an in-app `WebView` dialog (never Chrome), with the plugin receiving the app-to-app return through `onNewIntent`.
- **iOS** drives both flows through an in-app `WKWebView` (never Safari), with the plugin registered as both the `UIApplication` and the `UIScene` delegate for the app-to-app return — so it works whether or not your app has adopted the UIScene life cycle (required from iOS 27).

Every capability that's a plain HTTPS call with no browser/deep-link involved — token exchange, profile fetch, document upload/poll/download, logout's endpoint call — stays in pure Dart, unchanged by any of this.

## Features

- **Sign-in** — the documented app-to-app hand-off, run natively, with graceful, typed handling of cancellation/decline (never a crash).
- **Token exchange & refresh** — pluggable, so `client_secret` never has to ship in your app.
- **Full profile retrieval** — the complete profile field set (EN/AR name pairs, Emirates ID, home address, etc.), not a partial hand-picked subset.
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

`UaePassKit.isUaePassAppInstalled()`, `signIn()`'s native hand-off, and every `UaePassEndpoints` URL (`authorize`, `token`, `userInfo`, `logout`, `introspect`, and the `esignsp/v2` signing endpoints) all read from `config.environment` — none of them accept or construct a URL directly. `test/environment_test.dart` runs every assertion against both environments in a loop, including a dedicated regression test that a staging deep-link scheme is never mistaken for production's (and vice versa) — the direct fix for a real past incident where a `sandbox_stage` credential leaked into a production build.

## Security: where `client_secret` belongs

UAE Pass's token endpoint is a **confidential-client** endpoint (HTTP Basic `client_id:client_secret`) — there is no PKCE alternative documented anywhere. That means `client_secret` structurally does not belong in a shipped mobile or web app.

This plugin never bakes that assumption in — `UaePassTokenExchanger` and `UaePassSigningTokenExchanger` are interfaces, so the exchange step is pluggable. The recommended path for production is to implement the interface against your own backend:

> Sign-in itself never needs `client_secret` on any platform — only the token-exchange step does, and that step is pluggable as described here.

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
| **UAE Pass's own scheme** (`uaepass://`, `uaepassstg://`) | The custom scheme *UAE Pass's own native app* registers on the device. Native code uses it only to (a) check whether that app is installed, and (b) recognize when the login flow is trying to hand off to it. | UAE Pass | Nothing to configure — see [Environments](#environments). iOS still needs a one-time `LSApplicationQueriesSchemes` declaration (below) so `canOpenURL:` is allowed to check for it at all. |
| **Your app-callback scheme** (`UaePassConfig.appCallbackScheme`, e.g. `yourappscheme://`) | A scheme **you** invent and register with your own app, used only as the return address for the app-to-app handoff — the moment control comes back from the native UAE Pass app to yours. | You | `UaePassConfig(appCallbackScheme: ...)` in Dart, **plus** an Android intent-filter and an iOS `CFBundleURLTypes` entry (both below) — the plugin can't register these for you the way it does its own manifest entries, because they're specific to your app. |
| **Your OAuth `redirect_uri`** (`UaePassConfig.redirectUri`, e.g. `https://yourapp.com/uaepass/callback`) | A plain `https://` URL — UAE Pass's documented OAuth2 redirect target, carrying the final `code`/`state`. It does **not** need to be a reachable server; native code intercepts navigation to it before it would ever actually load. | You | `UaePassConfig(redirectUri: ...)` in Dart only — this one needs **no** platform (manifest/plist) configuration at all, since native code catches it internally and never lets the OS see it. |

The one you're most likely to misconfigure is the second row. Get it wrong and you'll see exactly the symptom this plugin had to be fixed for: after finishing in the native UAE Pass app, a Safari/Chrome page opens showing your `code`/`state` in the address bar, instead of control returning to your app. If you ever see that, it means the app-to-app handoff's return leg isn't reaching your app — check the platform config below first.

**Worked example, with real-shaped values.** Say your app registers the scheme `myapp`, targets `staging`, and your `redirectUri` is `https://myapp.com/callback`. Here's every URL that actually crosses the wire, in order (all inside native code — Android's `WebView` dialog, or iOS's `WKWebView`):

1. Native code loads the authorize URL: `https://stg-id.uaepass.ae/idshub/authorize?...&redirect_uri=https%3A%2F%2Fmyapp.com%2Fcallback&...`
2. UAE Pass's hosted page tries to navigate to its own app: `uaepassstg://authenticate?successurl=https%3A%2F%2Fstg-id.uaepass.ae%2F...&failureurl=...`
3. Native code intercepts step 2, **caches the original `successurl`/`failureurl` locally**, rewrites them to this app's own fixed sentinel URLs, and launches: `uaepassstg://authenticate?successurl=myapp%3A%2F%2Fsuccess&failureurl=myapp%3A%2F%2Ffailure` — the destination from step 2 travels in local native state, not through the OS.
4. The user finishes in the native app. It opens the sentinel your app registered in step 3 — just `myapp://success` (or `myapp://failure`), carrying no payload — this is the one your Android intent-filter / iOS `CFBundleURLTypes` below must actually catch.
5. Your app receives step 4 as a deep link — Android via `onNewIntent`, iOS via `scene(_:openURLContexts:)` (or `application(_:open:options:)` for apps without UIScene), both handled entirely inside this plugin's native code — which reloads the **cached** `successurl` from step 3 to resume the flow (or stops and cancels, for `failureurl`).
6. That resumed flow eventually redirects to `https://myapp.com/callback?code=...&state=...` — your `redirectUri` — which native code catches before it ever loads, and `signIn()` returns.

You never write code for steps 2–6 — they all happen inside native code owned by this plugin. The only thing *you* provide is the scheme in step 3/4 (`appCallbackScheme`) and its platform registration (below), and the URL in step 1/6 (`redirectUri`).

### The two flows, and which one runs when

`UaePassKit.signIn()` picks one of these automatically — you never choose a flow directly:

**1. App-to-App** — the UAE Pass app is installed and can actually be opened.

```
Your app  →  UAE Pass app  →  user authenticates  →  UAE Pass app  →  your app (deep link)
```

Native code loads UAE Pass's hosted login page, which tries to navigate to `uaepass://`/`uaepassstg://`. Native code intercepts that, caches the success/failure URLs inside it locally, rewrites them to your app-callback scheme's fixed `yourappscheme://success`/`yourappscheme://failure` sentinels, and launches the native app. When the user finishes there, the native app opens one of those sentinels, which this plugin's native code receives directly (Android's `onNewIntent`, iOS's `scene(_:openURLContexts:)` or `application(_:open:options:)`) and uses to reload the cached URL and resume the flow, to complete it.

**2. App-to-Web** — the UAE Pass app is not installed.

```
Your app  →  embedded WebView  →  UAE Pass web login  →  user authenticates  →  callback  →  your app
```

No app-switching, no custom scheme involved at all. The user identifies themselves (email/mobile/Emirates ID) and confirms via a push notification on another device; the final `code` arrives directly in the same WebView. This is why the app-callback scheme setup below is still worth doing even if you expect most users to have the app — every user without it goes through this path instead, and it needs no extra config from you.

**Worked example.** The only difference from the App-to-App example above is `acr_values` on the very first URL, and that nothing after it ever leaves native code:

1. Native code loads: `https://stg-id.uaepass.ae/idshub/authorize?...&acr_values=urn%3Asafelayer%3Atws%3Apolicies%3Aauthentication%3Alevel%3Alow&...` — no `mobileondevice`, so UAE Pass never tries to hand off to its own app at all.
2. The user enters their UAE Pass identifier on that same hosted page and confirms via a push notification on another device.
3. UAE Pass redirects straight to `https://myapp.com/callback?code=...&state=...` — caught in-app exactly like step 6 of the App-to-App example, and `signIn()` returns. Steps 2–5 of that example (any custom scheme at all) never happen.

**Installed but unopenable** — the app is detected as installed, but the actual launch attempt fails (disabled, frozen by an MDM policy, a broken install, etc.). This is rare, and this plugin doesn't auto-retry as App-to-Web in that case — `signIn()` surfaces it as a failure/cancellation instead of silently switching flows. If you need to handle this specifically, catch it via [`UaePassAuthFailure`](#quick-start) and prompt the user to retry (by which point the app may no longer report as installed, correctly routing them through App-to-Web instead).

In **both flows**, control returns to (or never leaves) the exact same screen that called `signIn()` — there's no separate "resume" step your app needs to implement.

### Callback handling — what code you actually have to write

None, for the callback itself. This plugin's native code receives the deep link directly from the OS (Android's `onNewIntent` via `PluginRegistry.NewIntentListener`, iOS's `scene(_:openURLContexts:)` via `registrar.addSceneDelegate`, or `application(_:open:options:)` via `registrar.addApplicationDelegate` for apps without UIScene) and resumes the flow with it — there's no Dart-side listener code for you to write anywhere in your app for UAE Pass's flow to work. All you provide is the *platform registration* (the intent-filter/`CFBundleURLTypes` below) so the OS routes the deep link to your app in the first place — what happens once it arrives is entirely internal, and entirely native.

Two things worth knowing if your app *also* has its own deep-link handling for other purposes (e.g. marketing links, other SSO providers):

- **They coexist safely.** Android's `addOnNewIntentListener` and iOS's `addApplicationDelegate`/`addSceneDelegate` all support multiple registered listeners, so this plugin's internal handler and any handler you attach elsewhere in your app (via `app_links`, `uni_links`, or your own `AppDelegate`/`MainActivity` code) both receive every incoming link independently.
- **This plugin ignores anything that isn't its own callback.** It checks the incoming URI's scheme against your configured `appCallbackScheme` and does nothing for anything else — so your other deep links (a different scheme, or the same scheme with a different host/path) pass through untouched to your own handling.

### Android (`android/app/src/main/AndroidManifest.xml`)

The package-visibility `<queries>` declaration for install detection (row 1 of the table above) ships in the plugin's own manifest and merges into yours automatically — you don't need to add it. You only need an intent filter for **your own** app-callback scheme (row 2), on the same activity Flutter uses (usually `MainActivity`):

```xml
<activity
  android:name=".MainActivity"
  android:launchMode="singleTask"
  android:taskAffinity=""
  ...>
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="yourappscheme"/>
  </intent-filter>
</activity>
```

`launchMode="singleTask"` (or `singleTop`, if `taskAffinity=""` keeps this activity as the sole member of its own task) matters here: it's what makes Android route the returning deep link to your **already-running** activity via `onNewIntent` — which is what this plugin's native code listens for — instead of spinning up a fresh instance that never receives it.

Write the scheme in **lowercase** here (Android matches intent-filter schemes case-sensitively, and the plugin sends the UAE Pass app a lowercase return URL). Don't add a `host` or `path` to this filter: the UAE Pass app returns to `yourappscheme://success` or `yourappscheme://failure` for both sign-in and document signing.

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

`example/lib/main.dart` shows the app-callback scheme actually wired up end-to-end (`uaepasskitexample`) and displays which flow just ran (App-to-App vs. App-to-Web) after every sign-in, so you can watch both flows above happen for real.

## Platform support

| Platform | Status |
|---|---|
| Android | ✅ |
| iOS | ✅ |
| Web | Not implemented here. UAE Pass documents a materially different flow for web (a plain full-page OAuth2 redirect against a real, reachable `redirect_uri`), not the WebView-interception app-to-app dance this package implements. `UaePassEnvironment.endpoints` and the token/profile/logout calls work unchanged on any platform if you want to drive that redirect flow yourself. |

Requirements: Flutter 3.38+, Android minSdk 28 (compileSdk 37), iOS 16+.

## Upgrading from 0.0.4

0.0.5 moves Android sign-in to the plugin's own `WebView` dialog (the previously bundled sign-in library stopped returning from the app-to-app hand-off on recent devices) and fixes the iOS return for apps on the UIScene life cycle. Most apps need no code changes, but check these:

| Change | Breaking? | What to do |
|---|---|---|
| Flutter **3.38** or later is required (was 3.29). | **Yes** | Upgrade Flutter. The iOS scene-delegate hook the plugin now uses was added in 3.38. |
| Android no longer pulls in `retrofit`, `converter-gson`, `converter-scalars`, `gson` or `android-async-http`. | **Yes**, if your app used them without declaring them | Add those dependencies to your own `android/app/build.gradle(.kts)`. |
| On Android, document signing returns to `yourappscheme://success` / `yourappscheme://failure` (was `yourappscheme:///resume_authn?url=...`), and the scheme is sent in lowercase. | **Yes**, only if your intent filter names a host/path or uses uppercase | Use the scheme-only, lowercase intent filter shown in [Android](#android-androidappsrcmainandroidmanifestxml). |
| `UaePassConfig.uaePassClientSecret` is deprecated and ignored. | No (deprecation warning only) | Remove it. Sign-in never needs `client_secret`, so it no longer has to ship in your Android app. |
| Android sign-in now shows the plugin's full-screen `WebView` instead of the SDK's screen; back goes back a page before cancelling. | No | None. Results are unchanged: cancelling still returns `UaePassAuthCancelled`. |
| Native code now rejects a redirect whose `state` doesn't match the one sent. | No | None. This shows up as a `UaePassAuthFailure`. |
| iOS now also receives the app-to-app return through the scene delegate. | No | None. This fixes the flow stalling after the UAE Pass app returns on UIScene apps (the Flutter default, and required from iOS 27). |

## Development

```
flutter analyze
dart format --set-exit-if-changed .
flutter test
```
