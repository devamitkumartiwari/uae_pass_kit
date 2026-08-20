import 'package:flutter/material.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

/// UAE Pass's own publicly documented staging POC credentials, valid only
/// against [UaePassEnvironment.staging]. Never use these — or the direct
/// token exchanger below — against production; see the package README's
/// security section.
const _sandboxClientId = 'sandbox_stage';
const _sandboxClientSecret = 'sandbox_stage';

void main() {
  runApp(const UaePassKitExampleApp());
}

class UaePassKitExampleApp extends StatelessWidget {
  const UaePassKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'uae_pass_kit example', home: const SignInPage());
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final UaePassConfig _config;
  late final UaePassKit _uaePassKit;

  bool _isBusy = false;
  String? _statusMessage;
  UaePassProfile? _profile;
  bool _showArabic = false;

  @override
  void initState() {
    super.initState();

    _config = UaePassConfig(
      clientId: _sandboxClientId,
      // Must exactly match what's registered with UAE Pass. This demo URL
      // doesn't need to be a reachable server — the plugin's WebView
      // intercepts navigation to it before it would actually load.
      redirectUri: Uri.parse('https://uaepasskit.dev/example/callback'),
      // Each integrating app must register and use its own unique scheme —
      // never reuse this demo value in your own app.
      appCallbackScheme: 'uaepasskitexample',
      environment: UaePassEnvironment.staging,
      locale: UaePassLocale.en,
    );

    _uaePassKit = UaePassKit(
      config: _config,
      // Sandbox-only: exchanges the token directly from this app using
      // the public sandbox_stage secret. A production app must supply an
      // implementation that calls its own backend instead — see the
      // package README.
      tokenExchanger: UaePassDirectTokenExchanger(
        clientId: _sandboxClientId,
        clientSecret: _sandboxClientSecret,
        environment: _config.environment,
      ),
    );
  }

  @override
  void dispose() {
    _uaePassKit.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
      _profile = null;
    });

    final result = await _uaePassKit.signIn(context);

    switch (result) {
      case UaePassAuthSuccess(:final code):
        await _exchangeAndFetchProfile(code);
      case UaePassAuthCancelled():
        setState(() {
          _isBusy = false;
          _statusMessage = 'Sign-in cancelled.';
        });
      case UaePassAuthFailure(:final exception):
        setState(() {
          _isBusy = false;
          _statusMessage = 'Sign-in failed: ${exception.message}';
        });
    }
  }

  Future<void> _exchangeAndFetchProfile(String code) async {
    try {
      final token = await _uaePassKit.exchangeAuthorizationCode(code);
      final profile = await _uaePassKit.getProfile(token);
      setState(() {
        _isBusy = false;
        _profile = profile;
        _statusMessage = null;
      });
    } on UaePassException catch (e) {
      setState(() {
        _isBusy = false;
        _statusMessage = 'Could not complete sign-in: ${e.message}';
      });
    }
  }

  Future<void> _signOut() async {
    setState(() => _isBusy = true);
    await _uaePassKit.logout();
    setState(() {
      _isBusy = false;
      _profile = null;
      _statusMessage = 'Signed out.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(title: const Text('uae_pass_kit example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile == null) ...[
              ElevatedButton(
                onPressed: _isBusy ? null : _signIn,
                child: _isBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in with UAE PASS (staging)'),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(_statusMessage!, textAlign: TextAlign.center),
              ],
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      const Text('EN'),
                      Switch(
                        value: _showArabic,
                        onChanged: (v) => setState(() => _showArabic = v),
                      ),
                      const Text('AR'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _ProfileField(
                label: 'Full name',
                value: _showArabic ? profile.fullNameAr : profile.fullNameEn,
              ),
              _ProfileField(
                label: 'Nationality',
                value: _showArabic
                    ? profile.nationalityAr
                    : profile.nationalityEn,
              ),
              _ProfileField(label: 'Emirates ID', value: profile.emiratesId),
              _ProfileField(label: 'Email', value: profile.email),
              _ProfileField(label: 'Mobile', value: profile.mobile),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _isBusy ? null : _signOut,
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 24),
              const Text(
                'Document sharing and e-signature both need a backend '
                'implementation of UaePassDocumentShareBackend / a signing '
                'token exchanger — see the package README for how to wire '
                'those up; they are intentionally not demoed here since '
                "they can't run against a public sandbox secret alone.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value ?? '—')),
        ],
      ),
    );
  }
}
