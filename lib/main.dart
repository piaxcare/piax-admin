import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'admin_modules/admin_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PiaxOrdersApp());
}

class PiaxOrdersApp extends StatelessWidget {
  const PiaxOrdersApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: brand, primary: brand, secondary: brand2, surface: Colors.white);
    return MaterialApp(
      title: 'PIAX Orders',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Poppins',
        colorScheme: scheme,
        scaffoldBackgroundColor: mist,
        appBarTheme: const AppBarTheme(
          backgroundColor: mist,
          foregroundColor: Color(0xFF0C1C19),
          elevation: 0,
          scrolledUnderElevation: 0.5,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE6ECEA)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFDCE6E3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: brand, width: 1.6)),
        ),
        // Modern Material 3 components across the app: newer page transitions (iOS keeps its swipe back),
        // rounded menus, dialogs and sheets, floating snack bars, pill chips and segmented buttons.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          },
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16302B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
        dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
        bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
        popupMenuTheme: PopupMenuThemeData(color: Colors.white, elevation: 6, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        drawerTheme: const DrawerThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24)))),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(color: const Color(0xFF16302B), borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
          waitDuration: const Duration(milliseconds: 350),
        ),
        chipTheme: ChipThemeData(
          shape: const StadiumBorder(),
          side: const BorderSide(color: Color(0xFFDCE6E3)),
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFD8EEE3),
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.white,
            selectedBackgroundColor: const Color(0xFFD8EEE3),
            selectedForegroundColor: brand,
            side: const BorderSide(color: Color(0xFFDCE6E3)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        dividerTheme: const DividerThemeData(color: Color(0xFFE6EEEB), thickness: 1),
      ),
      // No sign-in: straight into the admin console, on dummy data only (lib/demo_server.dart).
      home: AdminShell(api: AdminApi.demo()),
    );
  }
}
