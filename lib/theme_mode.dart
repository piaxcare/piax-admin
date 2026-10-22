import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's theme: follow the system, or always light or dark. Kept on this device.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final instance = ThemeController._();
  static const _key = 'theme_mode';

  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      value = ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  void set(ThemeMode mode) {
    value = mode;
    SharedPreferences.getInstance().then((p) => p.setString(_key, mode.name)).catchError((_) => false);
  }
}

/// The theme menu for a page's top bar: System, Light or Dark.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  static const _options = [
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ThemeController.instance,
    builder: (context, mode, _) => PopupMenuButton<ThemeMode>(
      tooltip: 'Theme',
      initialValue: mode,
      onSelected: ThemeController.instance.set,
      icon: Icon(_options.firstWhere((o) => o.$1 == mode).$3),
      itemBuilder: (_) => [
        for (final (m, label, icon) in _options)
          CheckedPopupMenuItem(value: m, checked: m == mode, child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)])),
      ],
    ),
  );
}
