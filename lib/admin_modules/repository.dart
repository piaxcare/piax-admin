import 'dart:convert';

import 'package:flutter/services.dart';

import '../api.dart';

/// Where the Admin modules' records come from: the dummy data bundled in the app (assets/mock/admin_modules.json),
/// the same locally and when deployed. No website is contacted. Changes last until the app is closed.
class ModuleRepository {
  ModuleRepository._(this.api, this._modules);

  final AdminApi api;
  final Map<String, List<Map<String, dynamic>>> _modules;

  static ModuleRepository? _bundledCache;

  String get sourceLabel => 'Dummy data (demo)';

  /// Loads every module's records from the bundled dummy data.
  static Future<ModuleRepository> open(AdminApi api) async {
    if (_bundledCache != null) return ModuleRepository._(api, _bundledCache!._modules);
    final raw = jsonDecode(await rootBundle.loadString('assets/mock/admin_modules.json')) as Map<String, dynamic>;
    final repo = ModuleRepository._(api, _parse(raw['modules'] as Map<String, dynamic>? ?? {}));
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
    final made = {'id': '${module.substring(0, 3)}_${DateTime.now().millisecondsSinceEpoch}', ...record};
    final stamped = {...made, '_modifiedAt': DateTime.now().toUtc().toIso8601String()};
    (_modules[module] ??= []).insert(0, stamped);
    return stamped;
  }

  Future<Map<String, dynamic>> update(String module, String id, Map<String, dynamic> changes) async {
    final list = _modules[module] ?? [];
    final index = list.indexWhere((r) => r['id'] == id);
    final updated = {...(index >= 0 ? list[index] : {'id': id}), ...changes};
    final stamped = {...updated, '_modifiedAt': DateTime.now().toUtc().toIso8601String()};
    if (index >= 0) list[index] = stamped;
    return stamped;
  }

  Future<void> delete(String module, String id) async {
    _modules[module]?.removeWhere((r) => r['id'] == id);
  }
}
