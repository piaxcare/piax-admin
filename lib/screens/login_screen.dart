import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../session.dart';
import '../widgets/brand.dart';
import '../admin_modules/admin_shell.dart';

/// Sign in with the app's username and password (admin / admin until it's changed in Settings). Desktops and wide
/// tablets show the PIAX panel beside the form; phones show it as a header above it.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.message});
  final String? message;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _hidePassword = true;
  bool _busy = false;
  bool _editServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    Session.server().then((url) {
      if (!mounted) return;
      setState(() => _server.text = url);
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String get _serverUrl => _server.text.trim().isEmpty ? Session.defaultServer : _server.text.trim();

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final server = _serverUrl;
      final signedIn = await AdminApi(server).login(username, password);
      await Session.saveServer(server);
      await Session.saveToken(signedIn.token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminShell(api: AdminApi(server, token: signedIn.token)),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth >= Breakpoints.desktop;
          if (side) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: constraints.maxWidth >= Breakpoints.wide ? 6 : 5,
                  child: const BrandBackdrop(child: _BrandPanel()),
                ),
                Expanded(
                  flex: 4,
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(40),
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _form(card: false)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          // Phones and tablets: the brand as a header, the form in a card that rises over its lower edge.
          final tablet = constraints.maxWidth >= Breakpoints.tablet;
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: tablet ? 300 : 240,
                  child: BrandBackdrop(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, tablet ? 40 : 24, 24, 56),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            BrandLogo(height: tablet ? 52 : 44),
                            const Spacer(),
                            Text(
                              'Order desk',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: tablet ? 30 : 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Every order, from paid to delivered.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFFCDE9E1), fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: _form(card: true)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _form({required bool card}) {
    final form = AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19), letterSpacing: -.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to manage orders, deliveries and customer updates.',
            style: TextStyle(color: Color(0xFF5B6B67), fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 28),
          _Label('Username'),
          TextField(
            controller: _username,
            autofocus: true,
            enabled: !_busy,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            style: const TextStyle(fontSize: 16),
            decoration: _decoration(hint: 'admin', icon: Icons.person_outline),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          _Label('Password'),
          TextField(
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: _hidePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            style: const TextStyle(fontSize: 16),
            decoration: _decoration(
              hint: '••••••••',
              icon: Icons.lock_outline,
              suffix: IconButton(
                tooltip: _hidePassword ? 'Show password' : 'Hide password',
                icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB3261E), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Text('Sign in'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 20)],
                    ),
            ),
          ),
          const SizedBox(height: 20),
          _serverRow(),
        ],
      ),
    );
    if (!card) return form;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1A052620), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: form,
    );
  }

  /// Which website the app signs in to: shown quietly, editable for testing against a local copy.
  Widget _serverRow() {
    if (_editServer) {
      return TextField(
        controller: _server,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        style: const TextStyle(fontSize: 16),
        decoration: _decoration(hint: Session.defaultServer, icon: Icons.language).copyWith(
          labelText: 'Website address',
          helperText: 'For testing, e.g. http://localhost:3000',
          suffixIcon: IconButton(tooltip: 'Done', icon: const Icon(Icons.check), onPressed: () => setState(() => _editServer = false)),
        ),
      );
    }
    final host = _serverUrl.replaceFirst(RegExp(r'^https?://'), '');
    return Row(
      children: [
        const Icon(Icons.language, size: 18, color: Color(0xFF5B6B67)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Connected to $host',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 13.5),
          ),
        ),
        TextButton(onPressed: _busy ? null : () => setState(() => _editServer = true), child: const Text('Change')),
      ],
    );
  }

  InputDecoration _decoration({required String hint, required IconData icon, Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFA3B1AD)),
    prefixIcon: Icon(icon, color: const Color(0xFF5B6B67)),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFF6F9F8),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE5E2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE5E2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: brand, width: 1.6),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF0C1C19)),
    ),
  );
}

/// The left half of the desktop sign-in: logo, what the app is for, and three things it does.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    const features = [
      (
        Icons.notifications_active_outlined,
        'New orders as they’re paid',
        'Every paid order appears within seconds, flagged until you open it.',
      ),
      (Icons.local_shipping_outlined, 'From packed to delivered', 'Move each order along and the customer’s order page updates at once.'),
      (Icons.chat_outlined, 'Customers kept in the loop', 'A ready-made WhatsApp message for every step, sent once.'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandLogo(height: 52),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                    child: const Text(
                      'ORDER DESK',
                      style: TextStyle(color: Color(0xFFCDE9E1), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Every order, from paid to delivered.',
                    style: TextStyle(color: Colors.white, fontSize: 40, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -1),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pack, ship and keep customers updated, on your phone, tablet or desktop.',
                    style: TextStyle(color: Color(0xFFCDE9E1), fontSize: 17, height: 1.45),
                  ),
                  const SizedBox(height: 36),
                  for (final (icon, title, text) in features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                            child: Icon(icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(text, style: const TextStyle(color: Color(0xFFB9D6CF), fontSize: 14, height: 1.4)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            const Text('PIAX LIFE PRIVATE LIMITED · Ranipet, Tamil Nadu', style: TextStyle(color: Color(0xFF8DB8AE), fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Forgets the session and returns to sign-in (on sign-out, or when the server says the session has expired).
Future<void> signOut(BuildContext context, {String? message}) async {
  await Session.clearToken();
  if (!context.mounted) return;
  // The app-wide navigator: pages inside the admin frame have their own, and signing out leaves the frame.
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => LoginScreen(message: message)), (_) => false);
}
