# uae_pass_kit: advanced guide

Everything the [README](../README.md) leaves out: how the deep-link round trip works, every
configuration option, errors, environments, security trade-offs, and upgrade notes.

**Contents:** [Deep linking](#deep-linking) · [Configuration options](#configuration-options) ·
[Errors](#errors) · [Environments](#environments) · [Security](#security-where-client_secret-belongs) ·
[Why native](#why-native) · [Upgrading from 0.0.5](#upgrading-from-005) ·
[Upgrading from 0.0.4](#upgrading-from-004) ·
[Limitations & known issues](#limitations--known-issues) · [Development](#development)

## Deep linking

This is the part of a UAE Pass integration most people get wrong first. If you only read one
section before shipping, read this one.

### The three URLs you'll see, and what each one is actually for

It's easy to conflate these — they look similar but do completely different jobs. None of the three "URL"/"scheme" values in a UAE Pass integration are interchangeable:

| | What it is | Who owns it | Where it's configured |
|---|---|---|---|
| **UAE Pass's own scheme** (`uaepass://`, `uaepassstg://`) | The custom scheme *UAE Pass's own native app* registers on the device. Native code uses it only to (a) check whether that app is installed, and (b) recognize when the login flow is trying to hand off to it. | UAE Pass | Nothing to configure — see [Environments](#environments). iOS still needs a one-time `LSApplicationQueriesSchemes` declaration (see [Install](../README.md#install)) so `canOpenURL:` is allowed to check for it at all. |
| **Your app-callback scheme** (`UaePassConfig.appCallbackScheme`, e.g. `yourappscheme://`) | A scheme **you** invent and register with your own app, used only as the return address for the app-to-app handoff — the moment control comes back from the native UAE Pass app to yours. | You | `UaePassConfig(appCallbackScheme: ...)` in Dart, **plus** an Android intent-filter and an iOS `CFBundleURLTypes` entry (see [Install](../README.md#install)) — the plugin can't register these for you the way it does its own manifest entries, because they're specific to your app. |
| **Your OAuth `redirect_uri`** (`UaePassConfig.redirectUri`, e.g. `https://yourapp.com/uaepass/callback`) | A plain `https://` URL — UAE Pass's documented OAuth2 redirect target, carrying the final `code`/`state`. It does **not** need to be a reachable server; native code intercepts navigation to it before it would ever actually load. | You | `UaePassConfig(redirectUri: ...)` in Dart only — this one needs **no** platform (manifest/plist) configuration at all, since native code catches it internally and never lets the OS see it. |

The one you're most likely to misconfigure is the second row. Get it wrong and you'll see exactly the symptom this plugin had to be fixed for: after finishing in the native UAE Pass app, a Safari/Chrome page opens showing your `code`/`state` in the address bar, instead of control returning to your app. If you ever see that, it means the app-to-app handoff's return leg isn't reaching your app — check the platform setup in the [README](../README.md#install) first.

**Worked example, with real-shaped values.** Say your app registers the scheme `myapp`, targets `staging`, and your `redirectUri` is `https://myapp.com/callback`. Here's every URL that actually crosses the wire, in order (all inside native code — Android's `WebView` dialog, or iOS's `WKWebView`):

1. Native code loads the authorize URL: `https://stg-id.uaepass.ae/idshub/authorize?...&redirect_uri=https%3A%2F%2Fmyapp.com%2Fcallback&...`
2. UAE Pass's hosted page tries to navigate to its own app: `uaepassstg://authenticate?successurl=https%3A%2F%2Fstg-id.uaepass.ae%2F...&failureurl=...`
3. Native code intercepts step 2, **caches the original `successurl`/`failureurl` locally**, rewrites them to this app's own fixed sentinel URLs, and launches: `uaepassstg://authenticate?successurl=myapp%3A%2F%2Fsuccess&failureurl=myapp%3A%2F%2Ffailure` — the destination from step 2 travels in local native state, not through the OS.
4. The user finishes in the native app. It opens the sentinel your app registered in step 3 — just `myapp://success` (or `myapp://failure`), carrying no payload — this is the one your Android intent filter / iOS `CFBundleURLTypes` (see [Install](../README.md#install)) must actually catch.
5. Your app receives step 4 as a deep link — Android via `onNewIntent`, iOS via `scene(_:openURLContexts:)` (or `application(_:open:options:)` for apps without UIScene), both handled entirely inside this plugin's native code — which reloads the **cached** `successurl` from step 3 to resume the flow (or stops and cancels, for `failureurl`).
6. That resumed flow eventually redirects to `https://myapp.com/callback?code=...&state=...` — your `redirectUri` — which native code catches before it ever loads, and `signIn()` returns.

You never write code for steps 2–6 — they all happen inside native code owned by this plugin. The only thing *you* provide is the scheme in step 3/4 (`appCallbackScheme`) and its platform registration (see [Install](../README.md#install)), and the URL in step 1/6 (`redirectUri`).

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

No app-switching, no custom scheme involved at all. The user identifies themselves (email/mobile/Emirates ID) and confirms via a push notification on another device; the final `code` arrives directly in the same WebView. This path needs no custom scheme at all. You still need the app-callback scheme setup for users who do have the UAE Pass app.

**Worked example.** The only difference from the App-to-App example above is `acr_values` on the very first URL, and that nothing after it ever leaves native code:

1. Native code loads: `https://stg-id.uaepass.ae/idshub/authorize?...&acr_values=urn%3Asafelayer%3Atws%3Apolicies%3Aauthentication%3Alevel%3Alow&...` — no `mobileondevice`, so UAE Pass never tries to hand off to its own app at all.
2. The user enters their UAE Pass identifier on that same hosted page and confirms via a push notification on another device.
3. UAE Pass redirects straight to `https://myapp.com/callback?code=...&state=...` — caught in-app exactly like step 6 of the App-to-App example, and `signIn()` returns. Steps 2–5 of that example (any custom scheme at all) never happen.

**Installed but unopenable** — the app is detected as installed, but the actual launch attempt fails (disabled, frozen by an MDM policy, a broken install, etc.). This is rare, and this plugin doesn't auto-retry as App-to-Web in that case — `signIn()` surfaces it as a failure/cancellation instead of silently switching flows. If you need to handle this specifically, catch it via [`UaePassAuthFailure`](../README.md#quick-start) and prompt the user to retry (by which point the app may no longer report as installed, correctly routing them through App-to-Web instead).

In **both flows**, control returns to (or never leaves) the exact same screen that called `signIn()` — there's no separate "resume" step your app needs to implement.

### Callback handling — what code you actually have to write

None, for the callback itself. This plugin's native code receives the deep link directly from the OS (Android's `onNewIntent` via `PluginRegistry.NewIntentListener`, iOS's `scene(_:openURLContexts:)` via `registrar.addSceneDelegate`, or `application(_:open:options:)` via `registrar.addApplicationDelegate` for apps without UIScene) and resumes the flow with it — there's no Dart-side listener code for you to write anywhere in your app for UAE Pass's flow to work. All you provide is the *platform registration* (the intent filter / `CFBundleURLTypes` from [Install](../README.md#install)) so the OS routes the deep link to your app in the first place — what happens once it arrives is entirely internal, and entirely native.

Two things worth knowing if your app *also* has its own deep-link handling for other purposes (e.g. marketing links, other SSO providers):

- **They coexist safely.** Android's `addOnNewIntentListener` and iOS's `addApplicationDelegate`/`addSceneDelegate` all support multiple registered listeners, so this plugin's internal handler and any handler you attach elsewhere in your app (via `app_links`, `uni_links`, or your own `AppDelegate`/`MainActivity` code) both receive every incoming link independently.
- **This plugin ignores anything that isn't its own callback.** It checks the incoming URI's scheme against your configured `appCallbackScheme` and does nothing for anything else — so your other deep links (a different scheme, or the same scheme with a different host/path) pass through untouched to your own handling.

## Configuration options

### `UaePassConfig`

| Field | Required | Default | What it does |
|---|---|---|---|
| `clientId` | yes | | Your UAE Pass client ID. Staging uses the public `sandbox_stage`. |
| `redirectUri` | yes | | Your OAuth `redirect_uri`, a plain `https://` URL. It never has to load: native code catches it. Must match what you registered with UAE Pass. |
| `appCallbackScheme` | yes | | Your own URL scheme for the return from the UAE Pass app. Lowercase, unique to your app, and registered on both platforms (see [Install](../README.md#install)). |
| `environment` | yes | | `UaePassEnvironment.staging` or `.production`. Every host, package ID and scheme comes from this. |
| `scope` | no | `urn:uae:digitalid:profile:general` | Space-separated OAuth scopes (`kUaePassDefaultScope`). |
| `locale` | no | `UaePassLocale.en` | Language of the UAE Pass pages: `en` or `ar`. |
| `useFaceVerification` | no | `false` | Requests UAE Pass's face-verification login variant. |
| `uaePassClientSecret` | no | | **Deprecated and ignored.** Sign-in never needs `client_secret`. |

### `UaePassKit`

| Parameter | When you need it |
|---|---|
| `config` | Always. |
| `tokenExchanger` **or** `clientSecret` | Always: exactly one of them. `tokenExchanger` calls your backend (recommended); `clientSecret` calls UAE Pass directly from the app. Passing both or neither throws `UaePassConfigurationException`. |
| `signingTokenExchanger` **or** `signingClientSecret` | Only for `signDocument`. Same rule: at most one. |
| `documentShareBackend` | Only for `requestDocumentShare`. |

Call `dispose()` when you're done with the instance to close its HTTP client.

## Errors

`signIn()` never throws for normal outcomes. It returns a sealed `UaePassAuthResult`:

| Result | Meaning |
|---|---|
| `UaePassAuthSuccess(code, state)` | Exchange `code` for tokens. |
| `UaePassAuthCancelled()` | The user backed out or declined. Not an error. |
| `UaePassAuthFailure(exception)` | UAE Pass reported an error, the returned `state` didn't match, or the page failed to load. |

Everything else (`exchangeAuthorizationCode`, `refreshAccessToken`, `getProfile`, `signDocument`,
`requestDocumentShare` and the signing-process helpers) throws a subclass of the sealed
`UaePassException`, each with a `message`:

| Exception | Thrown when |
|---|---|
| `UaePassConfigurationException` | The `UaePassKit` was set up wrongly for the call, e.g. `signDocument` without a signing exchanger. |
| `UaePassNetworkException` | The request never got a response: no connection, or a transport error. `cause` holds the original error. |
| `UaePassServerException` | UAE Pass answered with an error. Has `statusCode`, `errorCode` and `errorDescription`. |
| `UaePassParsingException` | UAE Pass answered, but the body wasn't the JSON expected. |

`logout()` doesn't throw for a failed call to the logout endpoint: local session data is cleared
first, and the endpoint call is best-effort.

`requestDocumentShare` reports a timeout as a `DocumentShareTimedOut` status on its stream, not
as an exception.

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

## Why native

An earlier version of this plugin implemented the entire flow in pure Dart (`webview_flutter` + `url_launcher` + `app_links`). In practice, the deep-link return from the native UAE Pass app (or the system browser) frequently never reached the app — the flow got stuck after control bounced out. The root cause is structural: that hand-off depends on the OS delivering an `onNewIntent`/`application(_:open:)` event back to the *same* running Activity/engine instance, and Dart-side plugins (`app_links`'s stream subscription, a `Navigator`-pushed WebView route) are exactly the layer most likely to have already been torn down or missed the delivery by the time it arrives.

So the parts of the flow that involve that hand-off now run natively, where the platform's own deep-link delivery mechanism is handled directly, with no Dart-side listener in between:

- **Android** drives sign-in and document-signing through an in-app `WebView` dialog (never Chrome), with the plugin receiving the app-to-app return through `onNewIntent`.
- **iOS** drives both flows through an in-app `WKWebView` (never Safari), with the plugin registered as both the `UIApplication` and the `UIScene` delegate for the app-to-app return — so it works whether or not your app has adopted the UIScene life cycle (required from iOS 27).

Every capability that's a plain HTTPS call with no browser/deep-link involved — token exchange, profile fetch, document upload/poll/download, logout's endpoint call — stays in pure Dart, unchanged by any of this.

## Upgrading from 0.0.5

0.0.6 moves the project to Flutter 3.50, makes iOS Swift Package Manager only, and lowers the
Android minimum to 7.0. The Dart API doesn't change, but check these:

| Change | Breaking? | What to do |
|---|---|---|
| Flutter **3.50** (Dart 3.14) or later is required (was 3.38). | **Yes** | Upgrade Flutter. The plugin is built and tested against the 3.50 toolchain (AGP 9.3.1, Kotlin 2.4.20, Gradle 9.5). |
| iOS: CocoaPods is no longer supported; the plugin is a Swift package only. | **Yes**, only if your app has Swift Package Manager turned off | Turn it back on — see [iOS: Swift Package Manager only](../README.md#ios). |
| iOS: the deployment target must be 16.0. | **Yes**, if your Runner project still has Flutter's default 15.0 | Set `IPHONEOS_DEPLOYMENT_TARGET = 16.0` for the Runner project in Xcode. |
| Android `minSdk` lowered from 28 to **24** (Android 7.0), and the plugin's `compileSdk` from 37 to 36. | No | None. Apps on Flutter's default `compileSdk` (36) no longer fail with "Dependency ':uae_pass_kit' requires … version 37". |
| The iOS privacy manifest (`PrivacyInfo.xcprivacy`) is now bundled. | No | None. |

## Upgrading from 0.0.4

0.0.5 moves Android sign-in to the plugin's own `WebView` dialog (the previously bundled sign-in library stopped returning from the app-to-app hand-off on recent devices) and fixes the iOS return for apps on the UIScene life cycle. Most apps need no code changes, but check these:

| Change | Breaking? | What to do |
|---|---|---|
| Flutter **3.38** or later is required (was 3.29). | **Yes** | Upgrade Flutter. The iOS scene-delegate hook the plugin uses was added in 3.38. |
| Android no longer pulls in `retrofit`, `converter-gson`, `converter-scalars`, `gson` or `android-async-http`. | **Yes**, if your app used them without declaring them | Add those dependencies to your own `android/app/build.gradle(.kts)`. |
| On Android, document signing returns to `yourappscheme://success` / `yourappscheme://failure` (was `yourappscheme:///resume_authn?url=...`), and the scheme is sent in lowercase. | **Yes**, only if your intent filter names a host/path or uses uppercase | Use the scheme-only, lowercase intent filter shown in [Android](../README.md#android). |
| `UaePassConfig.uaePassClientSecret` is deprecated and ignored. | No (deprecation warning only) | Remove it. Sign-in never needs `client_secret`, so it no longer has to ship in your Android app. |
| Android sign-in now shows the plugin's full-screen `WebView` instead of the SDK's screen; back goes back a page before cancelling. | No | None. Results are unchanged: cancelling still returns `UaePassAuthCancelled`. |
| Native code now rejects a redirect whose `state` doesn't match the one sent. | No | None. This shows up as a `UaePassAuthFailure`. |
| iOS now also receives the app-to-app return through the scene delegate. | No | None. This fixes the flow stalling after the UAE Pass app returns on UIScene apps (the Flutter default, and required from iOS 27). |

## Limitations & known issues

- **Web:** only the plain HTTPS calls work (token exchange, profile, logout endpoint). There's no
  web sign-in flow; UAE Pass documents a full-page redirect for web, which you drive yourself
  with `UaePassEnvironment.endpoints`.
- **Installed but unopenable UAE Pass app** (disabled, blocked by MDM, broken install): `signIn()`
  returns a failure or cancellation instead of switching to the App-to-Web flow.
- **Logout** clears the plugin's WebView cookies and storage and calls UAE Pass's logout
  endpoint, but can't sign the user out of the UAE Pass app itself. For a stronger guarantee,
  open `uaePassKit.logoutUrl()` in a browser.
- **CocoaPods** isn't supported; iOS needs Swift Package Manager.
- **Emulators and simulators** can't run the App-to-App flow, because the UAE Pass app isn't
  installed there. They always use App-to-Web.

## Development

```
flutter analyze
dart format --set-exit-if-changed .
flutter test

# Native unit tests (build the example once first: cd example && flutter build apk --debug)
cd example/android && ./gradlew :uae_pass_kit:testDebugUnitTest :uae_pass_kit:lintDebug
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The example app ("UAE Pass Kit") uses Material 3 through `package:material_ui` with light and dark themes. Its launcher icons are drawn by scripts in `example/assets/icon/`: Android 8+ uses an adaptive icon made of vector drawables, Android 7 and web use PNGs from `flutter_launcher_icons`, and iOS uses single-size 1024 px icons (light, dark and tinted) that Xcode scales. The steps to regenerate them are in `example/pubspec.yaml`. That folder is in git but left out of the published package.
