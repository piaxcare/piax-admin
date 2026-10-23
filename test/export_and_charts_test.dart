import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/chart_switch.dart';
import 'package:piax_orders_admin/admin_modules/charts.dart' show BarList;
import 'package:piax_orders_admin/admin_modules/competitors.dart';
import 'package:piax_orders_admin/admin_modules/dashboard_widgets.dart';
import 'package:piax_orders_admin/admin_modules/exporter.dart';
import 'package:piax_orders_admin/admin_modules/field_store.dart';
import 'package:piax_orders_admin/admin_modules/insights.dart';
import 'package:piax_orders_admin/admin_modules/nav_config.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/section_export.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final table = ExportTable(
    title: 'Purchase orders',
    columns: ['ID', 'Supplier', 'Status', 'Value'],
    rows: [
      ['PO-1', 'Acme & Co', 'Open', '₹1,200'],
      ['PO-2', 'Leaf "Ltd"', 'Closed', '₹800'],
      ['PO-3', 'Acme & Co', 'Open', '₹450'],
    ],
  );
  final bundle = ExportBundle(title: 'Procurement', subtitle: 'Demo', tables: [table, table.only({'ID', 'Status'})], skipped: ['Orders']);

  test('charts come from the records: counts by a choice column, and amount totals by it', () {
    expect(table.charts.map((c) => c.title), containsAll(['By supplier', 'By status', 'Value by supplier']));
    final byStatus = table.charts.firstWhere((c) => c.title == 'By status');
    expect(Map.fromIterables(byStatus.labels, byStatus.values), {'Open': 2, 'Closed': 1});
  });

  test('CSV quotes what needs it and keeps one block per page', () {
    final csv = toCsv(bundle);
    expect(csv, contains('"Leaf ""Ltd"""'));
    expect(csv.split('\r\n').where((l) => l == 'Purchase orders'), hasLength(2));
  });

  for (final f in ExportFormat.values) {
    test('${f.label} builds a file', () async {
      final bytes = await buildExport(bundle, f);
      expect(bytes, isNotEmpty);
      switch (f) {
        case ExportFormat.pdf:
          expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
        case ExportFormat.csv:
          expect(utf8.decode(bytes), contains('PO-1'));
        default:
          final zip = ZipDecoder().decodeBytes(bytes);
          final names = zip.files.map((x) => x.name).toSet();
          expect(names, contains('[Content_Types].xml'));
          final main = switch (f) { ExportFormat.xlsx => 'xl/worksheets/sheet2.xml', ExportFormat.docx => 'word/document.xml', _ => 'ppt/slides/slide2.xml' };
          expect(names, contains(main));
          // Every part is well-formed enough to be read back as text, with the record escaped.
          final text = utf8.decode(zip.files.firstWhere((x) => x.name == (f == ExportFormat.pptx ? 'ppt/slides/slide4.xml' : main.replaceAll('sheet2', 'sheet1'))).content as List<int>);
          if (f != ExportFormat.pptx) expect(text, contains('Acme &amp; Co'));
      }
    });
  }

  test('a section exports every sub page with records, and names the rest', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sec = navSections.firstWhere((s) => s.id == 'executive');
    final b = await sectionBundle(sec);
    expect(b.tables.map((t) => t.title), containsAll(['Priority Exceptions', 'Decisions & Approvals']));
    expect(b.skipped, containsAll(['Founder Overview', 'Competitor Comparison']));
    final spec = navPageSpecs['priority-exceptions']!;
    expect(b.tables.first.rows, hasLength(spec.rows));
  });

  test('a custom field keeps its suffix, and the menu page shows it after the value', () async {
    const f = CustomField(id: 'x1', label: 'Volume', type: CustomType.number, suffix: 'ml');
    expect(CustomField.fromJson(f.toJson())!.suffix, 'ml');
    await FieldStore.instance.add('nav:purchase-orders', f);
    final spec = specWithCustom('purchase-orders', navPageSpecs['purchase-orders']!);
    final t = navExportTable('PO', spec, [{...rowsFor('purchase-orders', spec).first, 'Volume': 500}]);
    expect(t.rows.first[t.columns.indexOf('Volume')], '500 ml');
    await FieldStore.instance.remove('nav:purchase-orders', 'x1');
  });

  test('competitor gaps list where PIAX trails, biggest first', () {
    final gaps = gapsFor(CompetitorStore.instance.brands);
    expect(gaps, isNotEmpty);
    expect(gaps.map((g) => g.metric.key), contains('cities'));
    for (var i = 1; i < gaps.length; i++) {
      expect(gaps[i - 1].behind, greaterThanOrEqualTo(gaps[i].behind));
    }
  });

  test('chart kinds fit the data: parts get pies and bars, time gets lines, too little gets nothing', () {
    const parts = ChartData(labels: ['A', 'B', 'C'], values: [3, 2, 1], looksLike: ChartKind.barH);
    expect(parts.kinds, [ChartKind.original, ChartKind.pie, ChartKind.donut, ChartKind.bar]);
    const weeks = ChartData(labels: ['W1', 'W2', 'W3', 'W4'], values: [5, 7, 4, 9], shape: ChartShape.series, looksLike: ChartKind.area);
    expect(weeks.kinds, [ChartKind.original, ChartKind.bar, ChartKind.line, ChartKind.scatter]);
    const funnel = ChartData(labels: ['Joined', 'Bought', 'Again'], values: [100, 40, 12], shape: ChartShape.stages, looksLike: ChartKind.bar);
    expect(funnel.kinds, [ChartKind.original, ChartKind.barH, ChartKind.line, ChartKind.area]);
    // One value, all zeros, or a single non-zero part: nothing to switch to, or no pie.
    expect(const ChartData(labels: ['A'], values: [3]).kinds, [ChartKind.original]);
    expect(const ChartData(labels: ['A', 'B'], values: [0, 0]).kinds, [ChartKind.original]);
    expect(const ChartData(labels: ['A', 'B'], values: [4, 0]).kinds, isNot(contains(ChartKind.pie)));
    expect(const ChartData(labels: ['A', 'B'], values: [4, -1]).kinds, isNot(contains(ChartKind.donut)));
    expect(ChartData(labels: List.generate(14, (i) => '$i'), values: List.generate(14, (i) => i + 1)).kinds, isNot(contains(ChartKind.pie)));
  });

  testWidgets('every chart kind draws in a row sized to its tallest card', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final slices = [Slice('Website', 1200, chartPalette[0]), Slice('Amazon', 800, chartPalette[1]), Slice('Store', 300, chartPalette[2])];
    for (final kind in ChartKind.values) {
      ChartPrefs.instance.set('Revenue by sales channel', kind);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: SmallCard(title: 'Revenue by sales channel', child: BarList(slices: slices))),
              const Expanded(child: SmallCard(title: 'Other', child: SizedBox(height: 120))),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: kind.name);
      expect(find.byType(ChartKindButton), findsOneWidget, reason: kind.name);
      // Parts of a whole: pie, donut and columns. Horizontal bars (how the list already looks) and lines aren't
      // offered, so the chart stays as designed.
      final offered = const [ChartKind.pie, ChartKind.donut, ChartKind.bar].contains(kind);
      expect(find.byType(AnyChart), offered ? findsOneWidget : findsNothing, reason: kind.name);
    }
    ChartPrefs.instance.set('Revenue by sales channel', ChartKind.original);
  });

  test('a custom colour makes a scheme of its shades, kept by its key', () {
    final p = ChartPalette.custom(const Color(0xFF1D4E89));
    expect(p.colors.first.toARGB32(), 0xFF1D4E89);
    expect(p.colors.toSet(), hasLength(p.colors.length));
    expect(ChartPalette.byKey(p.key)!.colors.map((c) => c.toARGB32()), p.colors.map((c) => c.toARGB32()));
    expect(ChartPalette.byKey('ocean')!.label, 'Ocean');
    expect(ChartPalette.byKey('nope'), isNull);
  });

  testWidgets('colours: picked in the chart menu, they recolour the chart as designed and every other kind', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final slices = [Slice('Website', 1200, chartPalette[0]), Slice('Amazon', 800, chartPalette[1]), Slice('Store', 300, chartPalette[2])];
    Widget page() => MaterialApp(home: Scaffold(body: SmallCard(title: 'Colour test', child: BarList(slices: slices))));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byType(AnyChart), findsNothing); // as designed, own colours

    await tester.tap(find.byType(ChartKindButton));
    await tester.pumpAndSettle();
    expect(find.text('COLOURS'), findsOneWidget);
    // Each scheme shows as a filled circle of its colours, not an empty outline.
    final swatches = find.byKey(const ValueKey('palette-swatch'));
    expect(swatches, findsNWidgets(chartPalettes.length));
    for (final e in swatches.evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)).width, greaterThan(20));
    }
    final ocean = tester.widget<DecoratedBox>(swatches.at(1)).decoration as BoxDecoration;
    expect((ocean.gradient! as SweepGradient).colors.first.toARGB32(), 0xFF1D4E89);
    await tester.tap(find.byTooltip('Ocean'));
    await tester.pumpAndSettle();
    expect(ChartPrefs.instance.paletteOf('Colour test')!.key, 'ocean');
    // Still horizontal bars, now drawn in the scheme's colours.
    final drawn = tester.widget<AnyChart>(find.byType(AnyChart));
    expect(drawn.kind, ChartKind.barH);
    expect(drawn.data.colors.first.toARGB32(), 0xFF1D4E89);

    ChartPrefs.instance.set('Colour test', ChartKind.pie);
    await tester.pumpAndSettle();
    expect(tester.widget<AnyChart>(find.byType(AnyChart)).kind, ChartKind.pie);
    expect(tester.takeException(), isNull);

    ChartPrefs.instance.setPalette('Colour test', null);
    ChartPrefs.instance.set('Colour test', ChartKind.original);
    await tester.pumpAndSettle();
    expect(find.byType(AnyChart), findsNothing);
  });
}
