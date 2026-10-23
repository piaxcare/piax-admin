import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/attachments.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';

// File uploads on the pages that need documents (SOPs, certificates, contracts…): the form's upload field, the
// required check, and the files listed with each record.
void main() {
  final sops = navPageSpecs['sops-documents']!;

  Future<void> form(WidgetTester tester, {DemoRow? row}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DemoRowForm(spec: sops, row: row, pageKey: 'nav:sops-documents')));
    await tester.pumpAndSettle();
  }

  test('document pages have an upload column; the demo rows hold labelled demo files', () {
    for (final id in ['sops-documents', 'compliance-documents', 'lab-reports', 'batch-release', 'institutional-contracts', 'device-registry']) {
      expect(navPageSpecs[id]!.columns.where((c) => c.kind == ColKind.file), isNotEmpty, reason: id);
    }
    final rows = demoRows('sops-documents', sops);
    final files = [for (final r in rows) ...attachmentsOf(r['SOP document'])];
    expect(files, isNotEmpty);
    expect(files.every((f) => f.demo && f.extension == 'pdf'), isTrue);
    expect(attachmentsSummary(const []), '—');
  });

  test('modules that need documents have an upload field', () {
    for (final (module, key) in [('products', 'labReports'), ('doctors', 'credentials'), ('partners', 'kycDocuments'), ('stores', 'agreement')]) {
      final f = modules.firstWhere((m) => m.key == module).fields.firstWhere((f) => f.key == key);
      expect(f.type, FieldType.file, reason: module);
    }
  });

  testWidgets('a new SOP needs its document: the form says so on save', (tester) async {
    await form(tester);
    expect(find.text('SOP document *'), findsOneWidget);
    expect(find.text('Choose files to upload'), findsOneWidget);
    expect(find.textContaining('PDF, DOC, DOCX'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')));
    await tester.pumpAndSettle();
    expect(find.text('Upload the sop document.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing lists the record’s files, and one can be removed', (tester) async {
    final row = demoRows('sops-documents', sops).firstWhere((r) => attachmentsOf(r['SOP document']).isNotEmpty);
    final name = attachmentsOf(row['SOP document']).first.name;
    await form(tester, row: row);
    expect(find.text(name), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text(name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uploaded file can be downloaded; a demo file says there’s nothing to download', (tester) async {
    final uploaded = Attachment(name: 'SOP-QA-07.pdf', size: 3, addedAt: DateTime(2026, 10, 1), bytes: Uint8List.fromList([1, 2, 3]));
    final demo = Attachment(name: 'SOP-1001.pdf', addedAt: DateTime(2026, 9, 1), demo: true);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AttachmentList(files: [uploaded, demo]))));
    expect(find.byTooltip('Download SOP-QA-07.pdf'), findsOneWidget);
    expect(find.byTooltip('Demo file: nothing to download'), findsOneWidget);
    await tester.tap(find.byTooltip('Demo file: nothing to download'));
    await tester.pump();
    expect(find.textContaining('is a sample file'), findsOneWidget);
    expect(uploaded.mimeType, 'application/pdf');
  });
}
