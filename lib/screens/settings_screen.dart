import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/brand.dart';
import 'login_screen.dart' show signOut;

/// The sign-in details: change the username or password (each needs the current password). A change signs out every
/// other device, and this one carries on with the new session, which is handed back to the orders list on close.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final AdminApi api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AdminApi _api = widget.api;
  AdminAccount? _account;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final account = await _api.account();
      if (mounted) setState(() => (_account = account, _loadError = null));
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  /// Saves a change; returns the error to show, or null when it worked.
  Future<String?> _save({required String currentPassword, String? username, String? newPassword}) async {
    try {
      final signedIn = await _api.updateAccount(currentPassword: currentPassword, username: username, newPassword: newPassword);
      await Session.saveToken(signedIn.token);
      if (!mounted) return null;
      setState(() {
        _api = AdminApi(_api.base, token: signedIn.token);
        _account = signedIn.account;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            newPassword != null ? 'Password changed. Other devices are signed out.' : 'Username changed to ${signedIn.account.username}.',
          ),
        ),
      );
      return null;
    } on ApiException catch (e) {
      if (e.signedOut && mounted) {
        await signOut(context, message: 'Your session ended. Please sign in again.');
        return null;
      }
      return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_api);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: account == null
            ? Center(child: _loadError == null ? const CircularProgressIndicator() : Text(_loadError!))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= Breakpoints.desktop;
                  final usernameForm = _UsernameForm(
                    current: account.username,
                    onSave: (password, username) => _save(currentPassword: password, username: username),
                  );
                  final passwordForm = _PasswordForm(
                    onSave: (current, next) => _save(currentPassword: current, newPassword: next),
                  );
                  return ListView(
                    padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 4, wide ? 32 : 16, 32),
                    children: [
                      PageWidth(
                        maxWidth: 1000,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (account.defaultPassword) ...[
                              Material(
                                color: const Color(0xFFFFF4D6),
                                borderRadius: BorderRadius.circular(16),
                                child: const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'You’re still using the default password. Change it below so only your team can see customer details.',
                                          style: TextStyle(color: Color(0xFF6B4600), fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            SizedBox(
                              height: 132,
                              child: BrandBackdrop(
                                borderRadius: BorderRadius.circular(22),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 22),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: Colors.white.withValues(alpha: .16),
                                        child: Text(
                                          account.username.isEmpty ? '?' : account.username[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Signed in as', style: TextStyle(color: Color(0xFFCDE9E1), fontSize: 13)),
                                            Text(
                                              account.username,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                                            ),
                                            Text(
                                              '${account.updatedAt == null ? 'Sign-in never changed' : 'Last changed ${dateTime(account.updatedAt!)}'} · ${_api.base.replaceFirst(RegExp(r'^https?://'), '')}',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Color(0xFFCDE9E1), fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (wide)
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: usernameForm),
                                    const SizedBox(width: 16),
                                    Expanded(child: passwordForm),
                                  ],
                                ),
                              )
                            else ...[
                              usernameForm,
                              const SizedBox(height: 12),
                              passwordForm,
                            ],
                            const SizedBox(height: 16),
                            const _SidebarBehaviour(),
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => signOut(context),
                                icon: const Icon(Icons.logout),
                                label: const Text('Sign out'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: brand),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _UsernameForm extends StatefulWidget {
  const _UsernameForm({required this.current, required this.onSave});
  final String current;
  final Future<String?> Function(String currentPassword, String username) onSave;

  @override
  State<_UsernameForm> createState() => _UsernameFormState();
}

class _UsernameFormState extends State<_UsernameForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    String? error;
    if (!RegExp(r'^[A-Za-z0-9._@-]{3,40}$').hasMatch(username)) {
      error = 'Use 3 to 40 letters, numbers, dots, dashes, underscores or @.';
    } else if (username.toLowerCase() == widget.current.toLowerCase()) {
      error = 'That’s already your username.';
    } else if (_password.text.isEmpty) {
      error = 'Enter your current password to confirm.';
    }
    if (error != null) return setState(() => _error = error);
    setState(() => (_busy = true, _error = null));
    final failed = await widget.onSave(_password.text, username);
    if (!mounted) return;
    setState(() => (_busy = false, _error = failed));
    if (failed == null) {
      _username.clear();
      _password.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    title: 'Change username',
    children: [
      TextField(
        controller: _username,
        enabled: !_busy,
        autocorrect: false,
        style: const TextStyle(fontSize: 16),
        decoration: const InputDecoration(labelText: 'New username'),
      ),
      const SizedBox(height: 12),
      _PasswordField(controller: _password, label: 'Current password', enabled: !_busy, onSubmitted: _submit),
      if (_error != null) _ErrorText(_error!),
      const SizedBox(height: 14),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Save username')),
    ],
  );
}

/// What the sidebar does when a page opens: always open, always folded to icons, or left as it was.
class _SidebarBehaviour extends StatefulWidget {
  const _SidebarBehaviour();

  @override
  State<_SidebarBehaviour> createState() => _SidebarBehaviourState();
}

class _SidebarBehaviourState extends State<_SidebarBehaviour> {
  String? _mode;

  static const _choices = [
    ('open', 'Open', Icons.view_sidebar_outlined, 'Every page opens with the full sidebar, names and all.'),
    ('closed', 'Folded', Icons.view_compact_outlined, 'Every page opens with the sidebar folded to icons, for more room.'),
    ('remember', 'As I left it', Icons.history, 'Pages open with the sidebar the way you last left it.'),
  ];

  @override
  void initState() {
    super.initState();
    Session.sidebarMode().then((m) {
      if (mounted) setState(() => _mode = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode ?? 'open';
    return _Card(
      title: 'Sidebar',
      children: [
        const Text('When a new page opens, the sidebar is…', style: TextStyle(color: Color(0xFF5A6C68), fontSize: 13.5)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final (value, label, icon, _) in _choices) ButtonSegment(value: value, icon: Icon(icon, size: 18), label: Text(label))],
          selected: {mode},
          onSelectionChanged: (s) {
            setState(() => _mode = s.first);
            Session.saveSidebarMode(s.first);
          },
        ),
        const SizedBox(height: 10),
        Text(_choices.firstWhere((c) => c.$1 == mode).$4, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
        const SizedBox(height: 4),
        const Text('You can always open or fold it with the arrows at its top. On phones the sidebar is the menu button’s side drawer.', style: TextStyle(color: Color(0xFF8A9A96), fontSize: 12.5)),
      ],
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.onSave});
  final Future<String?> Function(String currentPassword, String newPassword) onSave;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    String? error;
    if (_current.text.isEmpty) {
      error = 'Enter your current password.';
    } else if (_next.text.length < 8) {
      error = 'Use at least 8 characters for the new password.';
    } else if (_next.text != _confirm.text) {
      error = 'The new passwords don’t match.';
    } else if (_next.text == _current.text) {
      error = 'The new password is the same as the current one.';
    }
    if (error != null) return setState(() => _error = error);
    setState(() => (_busy = true, _error = null));
    final failed = await widget.onSave(_current.text, _next.text);
    if (!mounted) return;
    setState(() => (_busy = false, _error = failed));
    if (failed == null) {
      for (final c in [_current, _next, _confirm]) {
        c.clear();
      }
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    title: 'Change password',
    children: [
      _PasswordField(controller: _current, label: 'Current password', enabled: !_busy),
      const SizedBox(height: 12),
      _PasswordField(controller: _next, label: 'New password', helper: 'At least 8 characters', enabled: !_busy),
      const SizedBox(height: 12),
      _PasswordField(controller: _confirm, label: 'Confirm new password', enabled: !_busy, onSubmitted: _submit),
      if (_error != null) _ErrorText(_error!),
      const SizedBox(height: 8),
      const Text(
        'Changing the password signs out the app on every other device.',
        style: TextStyle(color: Color(0xFF5B6B67), fontSize: 13),
      ),
      const SizedBox(height: 14),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Save password')),
    ],
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, required this.label, required this.enabled, this.helper, this.onSubmitted});
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: _hide,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(fontSize: 16),
    onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      suffixIcon: IconButton(
        tooltip: _hide ? 'Show password' : 'Hide password',
        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hide = !_hide),
      ),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),
  );
}
