import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/site_builder.dart';
import 'package:piax_orders_admin/admin_modules/site_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Site & app builder: a demo copy of the website's and app's pages, edited on a canvas.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LayoutStore.instance.reset();
  });

  test('the demo layout: website and app pages; products use validated claims only', () {
    final l = demoLayout();
    expect(l.pages[Surface.website]!.map((p) => p.name), containsAll(['Home', 'Shop', 'About', 'Learn', 'Careers']));
    expect(l.pages[Surface.app]!.map((p) => p.name), containsAll(['Home', 'Tracker', 'Shop', 'Learn', 'Profile']));
    const banned = ['organic', 'compostable', 'rash-free', 'leak-proof', 'leak-free', 'toxin-free', 'bpa-free', 'ultra-thin', 'odour'];
    final text = l.toJson().toString().toLowerCase();
    for (final b in banned) {
      expect(text.contains(b), isFalse, reason: b);
    }
    final round = SiteLayout.fromJson(l.toJson());
    expect(round.toJson().toString(), l.toJson().toString());
  });

  test('elements move within a section and across sections; undo and redo', () {
    final store = LayoutStore.instance;
    final home = store.pages(Surface.website).first;
    final tags = home.sections.firstWhere((s) => s.kind == SectionKind.tagRow);
    final hero = home.sections.firstWhere((s) => s.kind == SectionKind.hero);
    final first = tags.elements.first, third = tags.elements[2];
    store.moveElement(Surface.website, third.id, tags, before: first.id);
    expect(tags.elements.first.id, third.id);
    store.moveElement(Surface.website, first.id, hero);
    expect(hero.elements.last.id, first.id);
    expect(tags.elements.any((e) => e.id == first.id), isFalse);
    store.undo();
    final home2 = store.pages(Surface.website).first;
    expect(home2.sections.firstWhere((s) => s.kind == SectionKind.tagRow).elements.any((e) => e.title == first.title), isTrue);
    store.redo();
    expect(store.pages(Surface.website).first.sections.firstWhere((s) => s.kind == SectionKind.hero).elements.last.title, first.title);
  });

  testWidgets('the canvas: select, add a section from the library, hide it, delete an element, undo', (tester) async {
    tester.view.physicalSize = const Size(1700, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SiteBuilderScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Feel different. Feel you.'), findsWidgets);
    final home = LayoutStore.instance.pages(Surface.website).first;
    final before = home.sections.length;

    // Add a card grid at the top from the component library.
    await tester.tap(find.text('Section at top'));
    await tester.pumpAndSettle();
    expect(find.text('Add a section'), findsOneWidget); // the component library
    await tester.tap(find.text('Card grid'));
    await tester.pumpAndSettle();
    expect(LayoutStore.instance.pages(Surface.website).first.sections.length, before + 1);
    expect(LayoutStore.instance.pages(Surface.website).first.sections.first.kind, SectionKind.cardGrid);

    // Hide it from its bar, then undo.
    await tester.tap(find.byTooltip('Hide section').first);
    await tester.pumpAndSettle();
    expect(LayoutStore.instance.pages(Surface.website).first.sections.first.visible, isFalse);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(LayoutStore.instance.pages(Surface.website).first.sections.first.visible, isTrue);

    // Select the tags section: its elements are listed on the right; delete one.
    final tags = LayoutStore.instance.pages(Surface.website).first.sections.firstWhere((s) => s.kind == SectionKind.tagRow);
    await tester.tap(find.text('What do you need today?').first);
    await tester.pumpAndSettle();
    expect(find.text('ELEMENTS (5)'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete Light flow'));
    await tester.pumpAndSettle();
    expect(LayoutStore.instance.section(Surface.website, tags.id)!.$2.elements.length, 4);

    // The app's pages are edited the same way.
    await tester.tap(find.text('PIAX app'));
    await tester.pumpAndSettle();
    expect(find.text('Cycle tracker'), findsNothing); // Home first
    expect(find.text('PIAX APP PAGES (5)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a tag onto another moves it before that one', (tester) async {
    tester.view.physicalSize = const Size(1700, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SiteBuilderScreen()));
    await tester.pumpAndSettle();
    final from = find.text('Cycle Pack').first, to = find.text('Light flow').first;
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(from) + const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final tags = LayoutStore.instance.pages(Surface.website).first.sections.firstWhere((s) => s.kind == SectionKind.tagRow);
    expect(tags.elements.first.title, 'Cycle Pack');
    expect(tester.takeException(), isNull);
  });
}
