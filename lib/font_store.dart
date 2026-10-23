import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart' show brand;
import 'palette.dart';

/// The app's font: Poppins (built in), or a font file the team imported from their device in Settings › Font
/// (.ttf or .otf). The imported file is kept on this device and loaded at start-up.
class FontStore extends ChangeNotifier {
  FontStore._();
  static final instance = FontStore._();
  static const _key = 'custom_font';
  static const builtIn = 'Poppins';

  /// Biggest file taken: fonts are kept in the browser's storage, which is small.
  static const maxBytes = 2 * 1024 * 1024;

  /// The imported font's file name, or null for Poppins.
  String? name;

  /// The family the theme uses. Each import gets a new family name, so a replaced font is loaded afresh.
  String family = builtIn;
  int _loads = 0;

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      await _register('${j['name']}', base64Decode('${j['data']}'));
    } catch (_) {
      // Unreadable or not a font: Poppins.
    }
  }

  Future<void> _register(String fileName, Uint8List bytes) async {
    final f = 'CustomFont${++_loads}';
    await (FontLoader(f)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    name = fileName;
    family = f;
    notifyListeners();
  }

  /// Opens the device's file picker for a font file; returns what to tell the user.
  Future<String?> import() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['ttf', 'otf']);
    final bytes = await file?.readAsBytes();
    if (file == null) return null;
    if (bytes == null) return 'Couldn’t read ${file.name}.';
    if (bytes.length > maxBytes) return '${file.name} is over 2 MB. Pick a single weight (Regular) of the font.';
    try {
      await _register(file.name, bytes);
    } catch (_) {
      return '${file.name} isn’t a font file this app can use. Try a .ttf or .otf.';
    }
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({'name': file.name, 'data': base64Encode(bytes)}));
    } catch (_) {
      return 'Using ${file.name} now, but it couldn’t be kept for next time (not enough storage).';
    }
    return 'Using ${file.name}.';
  }

  Future<void> reset() async {
    name = null;
    family = builtIn;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}

/// Settings › Font: the font in use, with a preview; import a font file from the device, or go back to Poppins.
class FontSettings extends StatelessWidget {
  const FontSettings({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FontStore.instance,
    builder: (context, _) {
      final store = FontStore.instance;
      Future<void> pick() async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final said = await store.import();
        if (said != null) messenger?.showSnackBar(SnackBar(content: Text(said)));
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          store.name == null ? 'Poppins (built in)' : store.name!,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Import a font file you’ve downloaded (.ttf or .otf, up to 2 MB). It’s used across the admin on this device.',
          style: TextStyle(fontSize: 12.5, color: TColor(0xFF8A9A96)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const TColor(0xFFF2F6F5), borderRadius: BorderRadius.circular(12)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Founder Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: brand)),
            SizedBox(height: 4),
            Text('Net revenue ₹4,82,300 · 1,284 orders · 98% delivered on time', style: TextStyle(fontSize: 14)),
            Text('AaBbCc 0123456789', style: TextStyle(fontSize: 12.5, color: TColor(0xFF5A6C68))),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          TextButton.icon(onPressed: pick, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Import font file')),
          if (store.name != null)
            TextButton.icon(onPressed: store.reset, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Back to Poppins')),
        ]),
      ]);
    },
  );
}
