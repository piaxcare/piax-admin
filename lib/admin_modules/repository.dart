import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api.dart';

/// Where the Admin modules' records come from:
///   - Local website: a development build pointed at a website on this computer or network (localhost, 127.0.0.1,
///     10.0.2.2 from the Android emulator, 192.168.x / 10.x) uses that website's dummy data (/api/admin/mock), and
///     changes are saved there, so they last while you test.
///   - Bundled dummy data: deployed (release) builds, a live website, or a local website that doesn't serve mock data.
///     The same records ship inside the app (assets/mock/admin_modules.json); changes last until the app is closed.
enum ModuleSource { localServer, bundled }

class ModuleRepository {
  ModuleRepository._(this.api, this.source, this._modules);

  final AdminApi api;
  final ModuleSource source;
  final Map<String, List<Map<String, dynamic>>> _modules;

  static ModuleRepository? _bundledCache;

  String get sourceLabel => source == ModuleSource.localServer ? 'Local website · dummy data' : 'Dummy data (demo)';

  static bool _isLocal(String base) {
    final host = Uri.tryParse(base)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2' || host.startsWith('192.168.') || host.startsWith('10.');
  }

  /// Loads every module's records from the right source.
  static Future<ModuleRepository> open(AdminApi api) async {
    if (!kReleaseMode && _isLocal(api.base)) {
      try {
        return ModuleRepository._(api, ModuleSource.localServer, _parse(await api.mockModules()));
      } on ApiException catch (e) {
        // Signed out is real: let the screen send the admin back to sign in. Anything else (an older website without
        // the mock endpoint, mock data switched off): fall back to the bundled dummy data.
        if (e.signedOut) rethrow;
      }
    }
    if (_bundledCache != null) return ModuleRepository._(api, ModuleSource.bundled, _bundledCache!._modules);
    final raw = jsonDecode(await rootBundle.loadString('assets/mock/admin_modules.json')) as Map<String, dynamic>;
    final repo = ModuleRepository._(api, ModuleSource.bundled, _parse(raw['modules'] as Map<String, dynamic>? ?? {}));
    _bundledCache = repo;
    return repo;
  }

  static Map<String, List<Map<String, dynamic>>> _parse(Map<String, dynamic> raw) => {
    for (final entry in raw.entries)
      entry.key: [for (final item in (entry.value as List? ?? const [])) Map<String, dynamic>.from(item as Map)],
  };

  List<Map<String, dynamic>> records(String module) => _modules[module] ?? const [];
  int count(String module) => records(module).length;

  Future<Map<String, dynamic>> create(String module, Map<String, dynamic> record) async {
    final made = source == ModuleSource.localServer
        ? await api.mockCreate(module, record)
        : {'id': '${module.substring(0, 3)}_${DateTime.now().millisecondsSinceEpoch}', ...record};
    (_modules[module] ??= []).insert(0, made);
    return made;
  }

  Future<Map<String, dynamic>> update(String module, String id, Map<String, dynamic> changes) async {
    final list = _modules[module] ?? [];
    final index = list.indexWhere((r) => r['id'] == id);
    final updated = source == ModuleSource.localServer
        ? await api.mockUpdate(module, id, changes)
        : {...(index >= 0 ? list[index] : {'id': id}), ...changes};
    if (index >= 0) list[index] = updated;
    return updated;
  }

  Future<void> delete(String module, String id) async {
    if (source == ModuleSource.localServer) await api.mockDelete(module, id);
    _modules[module]?.removeWhere((r) => r['id'] == id);
  }
}
