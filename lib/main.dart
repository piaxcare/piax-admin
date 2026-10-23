import 'package:flutter/material.dart';

import 'admin_modules/field_store.dart';
import 'admin_modules/site_layout.dart';

import 'api.dart';
import 'font_store.dart';
import 'theme_mode.dart';
import 'format.dart';
import 'palette.dart';
import 'admin_modules/admin_shell.dart';
import 'admin_modules/option_store.dart';
import 'app_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OptionStore.instance.load(); // the team's dropdown menus, before the first form opens
  await FieldStore.instance.load(); // the team's own input fields on each page
  await LayoutStore.instance.load(); // the Site & app builder's demo layout
  await ThemeController.instance.load(); // System, Light or Dark
  await AppLayout.instance.load(); // Settings › Layout & features
  await FontStore.instance.load(); // Settings › Font: an imported font file, if any
  runApp(const PiaxOrdersApp());
}

class PiaxOrdersApp extends StatefulWidget {
  const PiaxOrdersApp({super.key});

  @override
  State<PiaxOrdersApp> createState() => _PiaxOrdersAppState();
}

class _PiaxOrdersAppState extends State<PiaxOrdersApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // System mode follows the device's light / dark setting as it changes.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ThemeController.instance, FontStore.instance]),
    builder: (context, _) {
      final mode = ThemeController.instance.value;
      final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
      if (TColor.dark != dark) {
        TColor.dark = dark;
        // Every screen's fixed colours (TColor) follow the theme: redraw all of them, keeping each page's state.
        WidgetsBinding.instance.addPostFrameCallback((_) => WidgetsBinding.instance.reassembleApplication());
      }
      return _app(dark);
    },
  );

  Widget _app(bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: dark ? null : brand,
      secondary: dark ? null : brand2,
      surface: const TColor(0xFFFFFFFF),
    );
    return MaterialApp(
      title: 'PIAX Admin', // the browser tab and the app switcher
      debugShowCheckedModeBanner: false,
      // Hover hints only when switched on in Settings › Layout & features.
      builder: (context, child) => TooltipVisibility(visible: AppLayout.instance.tooltips, child: child!),
      theme: ThemeData(
        fontFamily: FontStore.instance.family,
        colorScheme: scheme,
        scaffoldBackgroundColor: mist,
        appBarTheme: const AppBarTheme(backgroundColor: mist, foregroundColor: TColor(0xFF0C1C19), elevation: 0, scrolledUnderElevation: 0.5),
        cardTheme: CardThemeData(
          color: TColor(0xFFFFFFFF),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: TColor(0xFFE6ECEA)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        // Outlined and text buttons look like the primary button too: brand green with white text, never a coloured
        // outline or bare coloured words.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const TColor(0xFFE1E8E6),
            disabledForegroundColor: const TColor(0xFF8A9A96),
            side: BorderSide.none,
            minimumSize: const Size(0, 48),
            textStyle: TextStyle(fontFamily: FontStore.instance.family, fontWeight: FontWeight.w600, fontSize: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            backgroundColor: brand,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const TColor(0xFFE1E8E6),
            disabledForegroundColor: const TColor(0xFF8A9A96),
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: TextStyle(fontFamily: FontStore.instance.family, fontWeight: FontWeight.w600, fontSize: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: TColor(0xFFFFFFFF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: TColor(0xFFDCE6E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: brand, width: 1.6),
          ),
        ),
        // Modern Material 3 components across the app:
        // rounded menus, dialogs and sheets, floating snack bars, pill chips and segmented buttons.
        // Pages switch instantly: no slide or fade between them (other animations stay).
        pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: _InstantPageTransitions()}),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16302B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: TColor(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: TColor(0xFFFFFFFF),
          showDragHandle: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: TColor(0xFFFFFFFF),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: TColor(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(color: const Color(0xFF16302B), borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12.5),
          waitDuration: const Duration(milliseconds: 350),
        ),
        chipTheme: ChipThemeData(
          shape: const StadiumBorder(),
          side: const BorderSide(color: TColor(0xFFDCE6E3)),
          backgroundColor: TColor(0xFFFFFFFF),
          selectedColor: const TColor(0xFFD8EEE3),
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: TColor(0xFFFFFFFF),
            selectedBackgroundColor: const TColor(0xFFD8EEE3),
            selectedForegroundColor: brand,
            side: const BorderSide(color: TColor(0xFFDCE6E3)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        dividerTheme: const DividerThemeData(color: TColor(0xFFE6EEEB), thickness: 1),
      ),
      // No sign-in: straight into the admin console, on dummy data only (lib/demo_server.dart).
      home: AdminShell(api: AdminApi.demo()),
    );
  }
}

/// A page appears straight away, with no transition.
class _InstantPageTransitions extends PageTransitionsBuilder {
  const _InstantPageTransitions();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
