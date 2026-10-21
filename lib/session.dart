import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app keeps on the phone: the website address, the admin session token (in the secure keystore), and the
/// order numbers already seen (so new ones can be flagged). No customer details are stored.
class Session {
  static const defaultServer = 'https://piax.co.in';
  static const _tokenKey = 'admin_token';
  static const _serverKey = 'server_url';
  static const _seenKey = 'seen_order_ids';
  static const _sidebarKey = 'sidebar_open';
  static const _sidebarModeKey = 'sidebar_on_new_page';

  // On macOS the regular login keychain, which works in unsigned development builds (the data-protection keychain
  // needs a signed app with a keychain-sharing entitlement).
  static const _secure = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  static Future<String?> token() => _secure.read(key: _tokenKey);
  static Future<void> saveToken(String token) => _secure.write(key: _tokenKey, value: token);
  static Future<void> clearToken() => _secure.delete(key: _tokenKey);

  static Future<String> server() async => (await SharedPreferences.getInstance()).getString(_serverKey) ?? defaultServer;
  static Future<void> saveServer(String url) async => (await SharedPreferences.getInstance()).setString(_serverKey, url);

  static Future<Set<String>?> seenOrderIds() async {
    final list = (await SharedPreferences.getInstance()).getStringList(_seenKey);
    return list?.toSet();
  }

  /// Whether the dashboard's left sidebar is open (it can be closed for more room).
  static Future<bool> sidebarOpen() async => (await SharedPreferences.getInstance()).getBool(_sidebarKey) ?? true;
  static Future<void> saveSidebarOpen(bool open) async => (await SharedPreferences.getInstance()).setBool(_sidebarKey, open);

  /// What the sidebar does when a new page opens: 'open' (always open), 'closed' (always folded to icons) or
  /// 'remember' (stays as it was left). Set in Settings; open by default.
  static Future<String> sidebarMode() async => (await SharedPreferences.getInstance()).getString(_sidebarModeKey) ?? 'open';
  static Future<void> saveSidebarMode(String mode) async => (await SharedPreferences.getInstance()).setString(_sidebarModeKey, mode);

  static Future<void> saveSeenOrderIds(Set<String> ids) async =>
      (await SharedPreferences.getInstance()).setStringList(_seenKey, ids.take(2000).toList());
}
