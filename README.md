# uae_pass_kit

[![pub package](https://img.shields.io/pub/v/uae_pass_kit.svg)](https://pub.dev/packages/uae_pass_kit)
[![pub points](https://img.shields.io/pub/points/uae_pass_kit)](https://pub.dev/packages/uae_pass_kit/score)
[![license: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![platforms](https://img.shields.io/badge/platform-android%20%7C%20ios-lightgrey.svg)](#platform-support)

Sign in with [UAE Pass](https://uaepass.ae), the UAE's national digital identity, from Flutter.
Also fetches the user's profile, refreshes tokens, signs PDFs and requests shared documents.

Sign-in hands off to the UAE Pass app when it's installed and comes back to yours, or runs in an
in-app web page when it isn't. That round trip runs in native code, so it survives the app switch.
You don't write any deep-link handling yourself.

> **Unofficial.** Not endorsed by UAE Pass, TDRA or the UAE government. Built from the public
> guides at [docs.uaepass.ae](https://docs.uaepass.ae).

## Install

```yaml
dependencies:
  uae_pass_kit: ^0.0.6
```

```dart
import 'package:uae_pass_kit/uae_pass_kit.dart';
```

Pick a URL scheme for your app, for example `myapp`. The UAE Pass app uses it to return to your
app after sign-in. Write it in lowercase, register it with UAE Pass, and use the same value on
both platforms and in `UaePassConfig.appCallbackScheme`.

### Android

Add an intent filter for your scheme to the activity Flutter uses, in
`android/app/src/main/AndroidManifest.xml`:

```xml
<activity
  android:name=".MainActivity"
  android:launchMode="singleTop"
  android:taskAffinity=""
  ...>
  <intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="myapp"/>
  </intent-filter>
</activity>
```

Keep `launchMode` as `singleTop` (Flutter's default, with `taskAffinity=""`) or `singleTask`, so
the return reaches your running app. Don't add a `host` or `path` to the filter.

The plugin adds the rest to your app automatically:

| Entry | Used for |
|---|---|
| `INTERNET` permission | The sign-in page and the UAE Pass API calls. |
| `<queries>` for `ae.uaepass.mainapp` and `ae.uaepass.mainapp.stg` | Detecting the UAE Pass app on Android 11+. |

### iOS

Add the UAE Pass schemes and your own scheme to `ios/Runner/Info.plist`:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>uaepass</string>
  <string>uaepassstg</string>
</array>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.yourcompany.yourapp</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myapp</string>
    </array>
  </dict>
</array>
```

Needs **Flutter 3.50+**, **Android 7.0+ (API 24)** and **iOS 16+**.

**iOS needs Swift Package Manager.** There's no CocoaPods podspec. Other plugins in your app can
still use CocoaPods. SPM is on by default from Flutter 3.50. If you turned it off, turn it back on
with `flutter config --enable-swift-package-manager`.

Set your app's iOS deployment target to 16.0 in Xcode (Runner → General → Minimum Deployments).
If a build fails with *"requires minimum platform version 16.0 … but this target supports 15.0"*
even though you already did, run the build again or run `flutter clean`. Flutter's build tool can
reset its generated plugin package to iOS 15.0 when your dependencies have just changed, and the
next build sets it back to 16.0.

## Quick start

**1. Configure** the plugin. Staging works with UAE Pass's public `sandbox_stage` credentials:

```dart
final uaePass = UaePassKit(
  config: UaePassConfig(
    clientId: 'sandbox_stage',
    redirectUri: Uri.parse('https://myapp.com/uaepass/callback'),
    appCallbackScheme: 'myapp',
    environment: UaePassEnvironment.staging, // or .production
  ),
  clientSecret: 'sandbox_stage', // for production, use a tokenExchanger instead
);
```

**2. Sign in.** The result tells you what happened. It doesn't throw:

```dart
final result = await uaePass.signIn(context);
```

**3. Get the tokens and the profile:**

```dart
if (result case UaePassAuthSuccess(:final code)) {
  final token = await uaePass.exchangeAuthorizationCode(code);
  final profile = await uaePass.getProfile(token);
  print(profile.fullNameEn);
}
```

**4. Handle the other outcomes:**

```dart
switch (result) {
  case UaePassAuthSuccess():
    break; // step 3
  case UaePassAuthCancelled():
    break; // the user backed out; not an error
  case UaePassAuthFailure(:final exception):
    print(exception.message);
}
```

## Features

| Group | Features |
|---|---|
| [Sign-in](#sign-in) | [Check for the app](#check-for-the-uae-pass-app) · [Sign in](#sign-the-user-in) · [Keep the secret on your server](#keep-the-secret-on-your-server) · [Refresh](#refresh-the-token) · [Log out](#log-out) |
| [User data](#user-data) | [Profile](#profile) · [Document sharing](#document-sharing) |
| [Signing](#signing) | [Sign a PDF](#sign-a-pdf) |
| [Errors](#errors) | Typed results for sign-in, and one sealed exception type for everything else |

---

## Sign-in

### Check for the UAE Pass app

Find out whether the UAE Pass app is installed for the configured environment. `signIn()` checks
this itself, so you only need it to change your UI.

```dart
final installed = await uaePass.isUaePassAppInstalled();
```

[example](example/lib/main.dart)

### Sign the user in

Opens the UAE Pass sign-in page over your app. The plugin picks the flow:

| UAE Pass app | What happens |
|---|---|
| Installed | **App-to-App.** The user approves in the UAE Pass app, which returns to yours. |
| Not installed | **App-to-Web.** The user enters their ID on the page and approves on another device. |

```dart
final result = await uaePass.signIn(context);
```

Options such as Arabic pages or face verification are set on `UaePassConfig`:

```dart
UaePassConfig(
  ...,
  locale: UaePassLocale.ar,
  useFaceVerification: true,
);
```

[example](example/lib/main.dart) · [all options](doc/advanced.md#configuration-options) ·
[how the deep link works](doc/advanced.md#deep-linking)

### Keep the secret on your server

UAE Pass's token endpoint needs your `client_secret`. Anything shipped in an app can be extracted,
so in production let your backend do the exchange:

```dart
class BackendTokenExchanger implements UaePassTokenExchanger {
  @override
  Future<UaePassTokenResponse> exchangeAuthorizationCode({
    required String code,
    required Uri redirectUri,
  }) async =>
      UaePassTokenResponse.fromJson(await api.post('/uaepass/token', {'code': code}));

  @override
  Future<UaePassTokenResponse> refreshToken({required String refreshToken}) async =>
      UaePassTokenResponse.fromJson(
        await api.post('/uaepass/refresh', {'refresh_token': refreshToken}),
      );
}

final uaePass = UaePassKit(config: config, tokenExchanger: BackendTokenExchanger());
```

Sign-in itself never needs the secret. Passing `clientSecret:` instead calls UAE Pass straight
from the app, which is fine for staging, prototypes and internal apps.

[security guide](doc/advanced.md#security-where-client_secret-belongs)

### Refresh the token

```dart
final fresh = await uaePass.refreshAccessToken(token.refreshToken!);
```

[example](example/lib/main.dart)

### Log out

Clears the sign-in page's cookies and storage, and tells UAE Pass to end the session.

```dart
await uaePass.logout();
```

---

## User data

### Profile

The full UAE Pass profile: names in English and Arabic, Emirates ID, nationality, contact details,
home address and more.

```dart
final profile = await uaePass.getProfile(token);
print(profile.emiratesId);
print(profile.fullNameAr);
print(profile.homeAddress?.emirateDescriptionEn);
```

[example](example/lib/main.dart)

### Document sharing

Ask the user to share documents, such as their Emirates ID, from UAE Pass. The calls are signed
with a key that must stay on your server, so you implement `UaePassDocumentShareBackend` there.
The plugin opens the UAE Pass app and reports progress as a stream:

```dart
final uaePass = UaePassKit(config: config, tokenExchanger: ..., documentShareBackend: myBackend);

await for (final status in uaePass.requestDocumentShare(request)) {
  switch (status) {
    case DocumentSharePending():
      break; // still waiting for the user
    case DocumentShareComplete(:final items):
      print(items.map((i) => i.documentType));
    case DocumentShareTimedOut():
      print('The user did not respond in time');
  }
}
```

[example](example/lib/main.dart)

---

## Signing

### Sign a PDF

The user signs a PDF with their UAE Pass identity. You place the signature fields:

```dart
final uaePass = UaePassKit(
  config: config,
  tokenExchanger: ...,
  signingTokenExchanger: mySigningExchanger, // or signingClientSecret: on staging
);

final outcome = await uaePass.signDocument(
  context,
  UaePassSigningRequest(
    documentBytes: pdfBytes,
    documentFileName: 'contract.pdf',
    finishCallbackUrl: Uri.parse('myapp://sign/finish'),
    signer: const UaePassSigner(
      fields: [
        UaePassSignatureField(
          name: 'signature1',
          pageNumber: 1,
          rectangle: UaePassSignatureRectangle(x: 50, y: 50, width: 100, height: 50),
        ),
      ],
    ),
  ),
);
print(outcome); // UaePassSigningOutcome.finished or .cancelled
```

For more control, `createSigningProcess`, `getSigningProcess`, `downloadSignedDocument` and
`deleteSigningProcess` expose each step.

[example](example/lib/main.dart)

---

## Errors

`signIn()` returns `UaePassAuthCancelled` or `UaePassAuthFailure` instead of throwing. Everything
else throws a `UaePassException`, a sealed type you can switch over:

```dart
try {
  final profile = await uaePass.getProfile(token);
} on UaePassException catch (e) {
  switch (e) {
    case UaePassNetworkException():
      showRetry(); // no connection
    case UaePassServerException(:final statusCode):
      showError('UAE Pass error $statusCode: ${e.message}');
    default:
      showError(e.message);
  }
}
```

[All exceptions and when they're thrown](doc/advanced.md#errors)

## Platform support

| | Android | iOS | Web |
|---|---|---|---|
| Sign-in (App-to-App and App-to-Web) | ✅ | ✅ | ❌ |
| PDF signing | ✅ | ✅ | ❌ |
| Document sharing | ✅ | ✅ | ❌ |
| Token exchange, refresh, profile, logout call | ✅ | ✅ | ✅ |
| Detect the UAE Pass app | ✅ | ✅ | always `false` |

On web, UAE Pass uses a full-page redirect that this plugin doesn't drive. You can build it with
`UaePassEnvironment.endpoints` and still use the token and profile calls.

## Good to know

- **Use a real device for App-to-App.** Emulators and simulators don't have the UAE Pass app, so
  they always use App-to-Web.
- **Staging and production need different apps.** Staging talks to the *UAE Pass Staging* app
  (`uaepassstg://`), production to the store app (`uaepass://`).
- **`redirectUri` never has to load.** It just has to match what you registered with UAE Pass;
  the plugin catches it before the page opens.
- **The scheme must match everywhere.** `appCallbackScheme`, the Android `<data android:scheme>`
  and the iOS `CFBundleURLSchemes` entry must be the same, in lowercase.

More in [Limitations & known issues](doc/advanced.md#limitations--known-issues).

## What's new in 0.0.6

- **Flutter 3.50:** built on the 3.50 templates; needs Flutter 3.50 or later.
- **Android 7.0+:** the minimum Android version dropped from 9 to 7.
- **iOS: Swift Package Manager only.** The CocoaPods podspec is gone. Other plugins in your app
  can still use CocoaPods. The privacy manifest is now included.
- **Fixed:** apps with `compileSdk` 36 (the Flutter default) failing to build, and web and WASM
  failing to compile.
- **No Material dependency:** the plugin only needs `package:flutter/widgets.dart`.
- No changes to the Dart API or to how sign-in and signing behave.

Upgrading from 0.0.5? See [what to check](doc/advanced.md#upgrading-from-005). See
[CHANGELOG.md](CHANGELOG.md) for everything.

## Example app

[`example/`](example) is a full demo against UAE Pass staging: sign-in, profile, token refresh,
PDF signing and document sharing. To run it: `cd example && flutter run`.

## Learn more

- [Advanced guide](doc/advanced.md): the deep-link round trip step by step, every option, errors,
  environments, security, and upgrade notes
- [CHANGELOG.md](CHANGELOG.md)
- [UAE Pass developer docs](https://docs.uaepass.ae)

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/devamitkumartiwari/uae_pass_kit/issues).
For support or business inquiries, see the [web portal](https://hireamit.web.app/).

## License

Apache-2.0. See [LICENSE](LICENSE).
