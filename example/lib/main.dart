import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:uae_pass_kit/uae_pass_kit.dart';

/// UAE Pass's own publicly documented staging POC credentials.
const _sandboxClientId = 'sandbox_stage';
const _sandboxClientSecret = 'sandbox_stage';

void main() {
  runApp(const UaePassKitExampleApp());
}

/// The gold accent used for the example's Material 3 colour scheme.
const _brandSeed = Color(0xFFAD904C);

class UaePassKitExampleApp extends StatelessWidget {
  const UaePassKitExampleApp({super.key});

  static ThemeData _theme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _brandSeed,
        brightness: brightness,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UAE Pass Kit',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SignInPage(),
    );
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
  UaePassTokenResponse? _token;
  bool _showArabic = false;
  bool? _isAppInstalled;
  String? _signingStatus;
  String? _documentShareStatus;

  /// Which of the two deep-linking flows the last sign-in attempt took —
  /// see the README's "Deep Linking" section for what each one means.
  String? _lastFlowType;

  @override
  void initState() {
    super.initState();

    _config = UaePassConfig(
      clientId: _sandboxClientId,
      // The OAuth redirect_uri — a plain https:// URL carrying the final
      // code/state. It never needs to be reachable: the plugin's WebView
      // intercepts navigation to it before it would actually load, so no
      // platform (manifest/plist) configuration is needed for this one.
      redirectUri: Uri.parse('https://uaepasskit.dev/example/callback'),
      // This app's OWN scheme — registered below in both
      // android/app/src/main/AndroidManifest.xml and
      // ios/Runner/Info.plist — used only as the return address when the
      // native UAE Pass app hands control back (the app-to-app flow). See
      // the README's "Deep Linking" section for the full explanation of
      // why this is a distinct value from redirectUri above, and from UAE
      // Pass's own uaepass://uaepassstg:// schemes.
      appCallbackScheme: 'uaepasskitexample',
      environment: UaePassEnvironment.staging,
      locale: UaePassLocale.en,
    );

    _uaePassKit = UaePassKit(
      config: _config,
      tokenExchanger: UaePassDirectTokenExchanger(
        clientId: _sandboxClientId,
        clientSecret: _sandboxClientSecret,
        environment: _config.environment,
      ),
      signingTokenExchanger: UaePassDirectSigningTokenExchanger(
        clientId: _sandboxClientId,
        clientSecret: _sandboxClientSecret,
        environment: _config.environment,
      ),
    );

    _checkAppInstalled();
  }

  @override
  void dispose() {
    _uaePassKit.dispose();
    super.dispose();
  }

  Future<void> _checkAppInstalled() async {
    final installed = await _uaePassKit.isUaePassAppInstalled();
    if (!mounted) return;
    setState(() => _isAppInstalled = installed);
  }

  Future<void> _signIn() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
      _profile = null;
      _token = null;
      _signingStatus = null;
      _documentShareStatus = null;
      // This is what UaePassKit.signIn() itself checks to pick a flow — see
      // the README's "Deep Linking" section. If the app is installed but
      // can't actually be opened (rare), signIn() surfaces that as a
      // failure/cancellation rather than switching flows, so this label
      // reflects the *attempted* flow, not necessarily which one the user
      // ended up completing.
      _lastFlowType = _isAppInstalled == true ? 'App-to-App' : 'App-to-Web';
    });

    // Note there's no deep-link listening code anywhere in this file — the
    // app-to-app callback is handled entirely inside native code, called
    // from signIn() itself. See the README's "Deep Linking" →
    // "Callback handling" section for why that's true even if this app
    // also has its own unrelated deep links elsewhere.
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
        _token = token;
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
      _token = null;
      _signingStatus = null;
      _documentShareStatus = null;
      _lastFlowType = null;
      _statusMessage = 'Signed out.';
    });
  }

  Future<void> _refreshToken() async {
    final refreshToken = _token?.refreshToken;
    if (refreshToken == null) {
      setState(() => _statusMessage = 'No refresh token available.');
      return;
    }

    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      final refreshed = await _uaePassKit.refreshAccessToken(refreshToken);
      setState(() {
        _isBusy = false;
        _token = refreshed;
        _statusMessage = 'Token refreshed.';
      });
    } on UaePassException catch (e) {
      setState(() {
        _isBusy = false;
        _statusMessage = 'Refresh failed: ${e.message}';
      });
    }
  }

  Future<void> _signSampleDocument() async {
    setState(() {
      _isBusy = true;
      _signingStatus = null;
    });
    try {
      final outcome = await _uaePassKit.signDocument(
        context,
        UaePassSigningRequest(
          documentBytes: _buildSamplePdfBytes(),
          documentFileName: 'sample.pdf',
          finishCallbackUrl: Uri.parse('uaepasskitexample://sign/finish'),
          signer: const UaePassSigner(
            fields: [
              UaePassSignatureField(
                name: 'signature1',
                pageNumber: 1,
                rectangle: UaePassSignatureRectangle(
                  x: 50,
                  y: 50,
                  width: 100,
                  height: 50,
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _signingStatus = 'Successfully signed: ${outcome.name}';
      });
    } on UaePassException catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _signingStatus = 'Signing failed: ${e.message}';
      });
    }
  }

  Future<void> _requestDocumentShare() async {
    final profile = _profile;
    final token = _token;
    if (profile == null || token == null) return;

    setState(() {
      _isBusy = true;
      _documentShareStatus = null;
    });
    try {
      await for (final status in _uaePassKit.requestDocumentShare(
        UaePassDocumentShareRequest(
          accessToken: token.accessToken,
          emiratesId: profile.emiratesId ?? '',
          uuid: profile.uuid ?? '',
          documents: const [
            UaePassDocumentRequestItem(
              documentType: 'EmiratesId',
              required: true,
            ),
          ],
          successUrl: Uri.parse('uaepasskitexample://doc-share/success'),
          failureUrl: Uri.parse('uaepasskitexample://doc-share/failure'),
          origin: UaePassDocumentShareOrigin.mobile,
        ),
      )) {
        if (!mounted) return;
        setState(() => _documentShareStatus = status.runtimeType.toString());
      }
    } on UaePassConfigurationException catch (e) {
      if (!mounted) return;
      setState(() => _documentShareStatus = e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UAE Pass Kit'),
        actions: [
          if (_profile != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _isBusy ? null : _signOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _profile == null ? _buildLoginView() : _buildProfileView(),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('login_view'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              Icons.fingerprint,
              size: 72,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'UAE Pass Kit',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unofficial UAE PASS sign-in demo (staging)',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 56),
          FilledButton.icon(
            onPressed: _isBusy ? null : _signIn,
            icon: _isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_isBusy ? 'Connecting...' : 'Sign in with UAE PASS'),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 24),
            Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
          _AppStatusCard(isInstalled: _isAppInstalled),
        ],
      ),
    );
  }

  Widget _buildProfileView() {
    final profile = _profile!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('profile_view'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_lastFlowType != null)
                _FlowTypeChip(flowType: _lastFlowType!),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('EN')),
                  ButtonSegment(value: true, label: Text('AR')),
                ],
                selected: {_showArabic},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    setState(() => _showArabic = v.first),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Welcome,', style: theme.textTheme.titleLarge),
          Text(
            (_showArabic ? profile.fullNameAr : profile.fullNameEn) ?? 'User',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Card.outlined(
            child: Column(
              children: [
                _ProfileListTile(
                  icon: Icons.badge_outlined,
                  label: 'Emirates ID',
                  value: profile.emiratesId,
                ),
                const Divider(height: 1, indent: 56),
                _ProfileListTile(
                  icon: Icons.public_outlined,
                  label: 'Nationality',
                  value: _showArabic
                      ? profile.nationalityAr
                      : profile.nationalityEn,
                ),
                const Divider(height: 1, indent: 56),
                _ProfileListTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: profile.email,
                ),
                const Divider(height: 1, indent: 56),
                _ProfileListTile(
                  icon: Icons.phone_android_outlined,
                  label: 'Mobile',
                  value: profile.mobile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('Actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _refreshToken,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh session'),
          ),
          if (_statusMessage != null) _ResultText(_statusMessage!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _signSampleDocument,
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Digital signature (sandbox)'),
          ),
          if (_signingStatus != null) _ResultText(_signingStatus!),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _requestDocumentShare,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Request document sharing'),
          ),
          if (_documentShareStatus != null) _ResultText(_documentShareStatus!),
          const SizedBox(height: 40),
          Text(
            'Some features need a backend integration, as described in the '
            'README.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A short result line shown under an action button.
class _ResultText extends StatelessWidget {
  const _ResultText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Shows which of the two deep-linking flows the last sign-in attempt
/// took — see the README's "Deep Linking" section for what each one means.
class _FlowTypeChip extends StatelessWidget {
  const _FlowTypeChip({required this.flowType});
  final String flowType;

  @override
  Widget build(BuildContext context) {
    final isAppToApp = flowType == 'App-to-App';
    return Chip(
      avatar: Icon(isAppToApp ? Icons.phone_iphone : Icons.public, size: 18),
      label: Text(flowType),
    );
  }
}

class _AppStatusCard extends StatelessWidget {
  const _AppStatusCard({required this.isInstalled});
  final bool? isInstalled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (isInstalled) {
      true => (
        Icons.check_circle_outline,
        colors.primary,
        'UAE PASS app is installed',
      ),
      false => (
        Icons.info_outline,
        colors.tertiary,
        'UAE PASS app is not detected (App-to-Web flow)',
      ),
      null => (
        Icons.hourglass_empty,
        colors.outline,
        'Checking for the UAE PASS app...',
      ),
    };
    return Card.outlined(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text),
      ),
    );
  }
}

class _ProfileListTile extends StatelessWidget {
  const _ProfileListTile({required this.icon, required this.label, this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(value ?? '—', style: theme.textTheme.titleMedium),
    );
  }
}

Uint8List _buildSamplePdfBytes() {
  const header = '%PDF-1.4\n';
  const obj1 = '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n';
  const obj2 = '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n';
  const obj3 =
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> '
      '/MediaBox [0 0 200 200] >>\nendobj\n';

  final offset1 = header.length;
  final offset2 = offset1 + obj1.length;
  final offset3 = offset2 + obj2.length;
  final xrefOffset = offset3 + obj3.length;

  String padOffset(int offset) => offset.toString().padLeft(10, '0');

  final xref =
      'xref\n0 4\n'
      '0000000000 65535 f \n'
      '${padOffset(offset1)} 00000 n \n'
      '${padOffset(offset2)} 00000 n \n'
      '${padOffset(offset3)} 00000 n \n';
  final trailer =
      'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF';

  final pdf = '$header$obj1$obj2$obj3$xref$trailer';
  return Uint8List.fromList(utf8.encode(pdf));
}
