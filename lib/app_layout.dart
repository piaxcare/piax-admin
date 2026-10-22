import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the team set up the admin app's frame in Settings › Layout & features: where the icon rail sits and how it
/// looks, the wide panel's width, which features show (search, theme switch, favourites, Edit fields, the page
/// trail), how page content is aligned, and their own names for sections and pages (and pages taken off the panel).
/// Kept on this device.
class AppLayout extends ChangeNotifier {
  AppLayout._();
  static final instance = AppLayout._();
  static const _key = 'app_layout';

  // Navigation bar.
  bool railRight = false;
  bool railLabels = true;
  String panelWidth = 'normal'; // narrow, normal, wide

  // Features.
  bool search = true;
  bool themeOnRail = true;
  bool favorites = true;
  bool editFields = true;
  bool breadcrumb = true;
  bool tooltips = false; // hover hints on buttons and names

  // Alignment.
  bool centered = false; // page content: full width, or centred at [contentMax]
  static const contentMax = 1440.0;

  // Structure.
  final names = <String, String>{};
  final hiddenPages = <String>{};

  double get panelPixels => switch (panelWidth) { 'narrow' => 220, 'wide' => 320, _ => 264 };

  /// A section's or page's name: the team's own, or the built-in one.
  String label(String id, String fallback) => names[id] ?? fallback;

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      railRight = j['railRight'] == true;
      railLabels = j['railLabels'] != false;
      panelWidth = '${j['panelWidth'] ?? 'normal'}';
      search = j['search'] != false;
      themeOnRail = j['themeOnRail'] != false;
      favorites = j['favorites'] != false;
      editFields = j['editFields'] != false;
      breadcrumb = j['breadcrumb'] != false;
      tooltips = j['tooltips'] == true;
      centered = j['centered'] == true;
      names.addAll({for (final e in ((j['names'] as Map?) ?? {}).entries) '${e.key}': '${e.value}'});
      hiddenPages.addAll([for (final id in (j['hiddenPages'] as List?) ?? const []) '$id']);
    } catch (_) {
      // Unreadable: the defaults.
    }
  }

  /// Applies a change, saves it and redraws every screen (keeping each page's state).
  void update(void Function(AppLayout l) change) {
    change(this);
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.reassembleApplication());
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode(_toJson())))
        .catchError((_) => false);
  }

  void rename(String id, String name, String fallback) => update((l) {
    final n = name.trim();
    n.isEmpty || n == fallback ? l.names.remove(id) : l.names[id] = n;
  });

  void setPageHidden(String id, bool hide) => update((l) => hide ? l.hiddenPages.add(id) : l.hiddenPages.remove(id));

  void reset() => update((l) {
    l
      ..railRight = false
      ..railLabels = true
      ..panelWidth = 'normal'
      ..search = true
      ..themeOnRail = true
      ..favorites = true
      ..editFields = true
      ..breadcrumb = true
      ..tooltips = false
      ..centered = false;
    l.names.clear();
    l.hiddenPages.clear();
  });

  Map<String, dynamic> _toJson() => {
    'railRight': railRight,
    'railLabels': railLabels,
    'panelWidth': panelWidth,
    'search': search,
    'themeOnRail': themeOnRail,
    'favorites': favorites,
    'editFields': editFields,
    'breadcrumb': breadcrumb,
    'tooltips': tooltips,
    'centered': centered,
    'names': names,
    'hiddenPages': hiddenPages.toList(),
  };
}
