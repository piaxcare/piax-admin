import 'package:flutter/widgets.dart';

import '../api.dart';
import 'exporter.dart';
import 'field_store.dart' show withCustomFields;
import 'modules_screens.dart' show moduleExportTable;
import 'nav_config.dart';
import 'nav_pages.dart';
import 'repository.dart';
import 'schema.dart';
import 'package:piax_orders_admin/app_layout.dart';

// A main section's export: every sub page in it that has records (menu pages and admin modules), one after another.
// Pages without records of their own (the order desk, analytics, settings, the builder) are named as not included.

Future<ExportBundle> sectionBundle(NavSection sec) async {
  final repo = await ModuleRepository.open(AdminApi.demo());
  final title = AppLayout.instance.label(sec.id, sec.label);
  final tables = <ExportTable>[];
  final skipped = <String>[];
  for (final i in sec.items) {
    if (AppLayout.instance.hiddenPages.contains(i.id)) continue;
    final name = AppLayout.instance.label(i.id, i.label);
    switch (i.target) {
      case DemoTarget() when navPageSpecs.containsKey(i.id):
        final spec = specWithCustom(i.id, navPageSpecs[i.id]!);
        tables.add(navExportTable(name, spec, rowsFor(i.id, spec)));
      case ModuleTarget(:final module, :final status):
        final def = modules.where((m) => m.key == module).firstOrNull;
        if (def == null) {
          skipped.add(name);
          continue;
        }
        final m = withCustomFields(def);
        final records = [
          for (final r in repo.records(module))
            if (status == null || m.statusField == null || r[m.statusField] == status) r,
        ];
        tables.add(moduleExportTable(m, records, title: name));
      default:
        skipped.add(name);
    }
  }
  return ExportBundle(title: title, subtitle: sec.purpose, tables: tables, skipped: skipped);
}

/// Opens the export dialog for every sub page of [sec].
Future<void> exportSection(BuildContext context, NavSection sec) => showExportDialog(
  context,
  title: AppLayout.instance.label(sec.id, sec.label),
  build: ({required all}) => sectionBundle(sec),
);
