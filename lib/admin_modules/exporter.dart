import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart' show brand;
import 'package:piax_orders_admin/palette.dart';

// Exports a page's records as PDF, PowerPoint, Word, Excel or CSV: a sub page (its records, with the fields picked) or
// a main section (every sub page in it, one after another). PDF, PowerPoint and Word can carry charts of the records
// (counts by status or choice, totals of an amount); Excel has a sheet per page and CSV a block per page.
//
// Every format is built here from the same [ExportBundle], with no service involved, and saved through the browser's
// download or the device's save dialog.

/// A chart of a page's records: a value per label.
class ExportChart {
  const ExportChart(this.title, this.labels, this.values);
  final String title;
  final List<String> labels;
  final List<num> values;
}

/// One page's records as text, ready to print: its columns, a row per record, and charts of them.
class ExportTable {
  ExportTable({required this.title, this.note, required this.columns, required this.rows, List<ExportChart>? charts})
    : charts = charts ?? chartsFor(columns, rows);
  final String title;
  final String? note;
  final List<String> columns;
  final List<List<String>> rows;
  final List<ExportChart> charts;

  /// Only the columns in [keep] (in this table's order).
  ExportTable only(Set<String> keep) {
    final at = [for (final (i, c) in columns.indexed) if (keep.contains(c)) i];
    return ExportTable(
      title: title,
      note: note,
      columns: [for (final i in at) columns[i]],
      rows: [for (final r in rows) [for (final i in at) i < r.length ? r[i] : '']],
      charts: charts,
    );
  }
}

/// What's exported: a title, and one or more pages' tables.
class ExportBundle {
  const ExportBundle({required this.title, this.subtitle, required this.tables, this.skipped = const []});
  final String title;
  final String? subtitle;
  final List<ExportTable> tables;

  /// Pages of a section that have nothing to export (the order desk, settings…), named in the file.
  final List<String> skipped;
}

enum ExportFormat {
  pdf('PDF', 'pdf', 'application/pdf', Icons.picture_as_pdf_outlined, true),
  pptx('PowerPoint', 'pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', Icons.slideshow_outlined, true),
  docx('Word', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', Icons.description_outlined, true),
  xlsx('Excel', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', Icons.grid_on_outlined, false),
  csv('CSV', 'csv', 'text/csv', Icons.table_rows_outlined, false);

  const ExportFormat(this.label, this.extension, this.mime, this.icon, this.charts);
  final String label, extension, mime;
  final IconData icon;

  /// Whether the format can carry charts.
  final bool charts;
}

// ---------------------------------------------------------------- charts from the records

/// A number in a cell ("₹1,200", "45 units", "98%"), or null when the cell isn't a plain figure.
num? numberIn(String cell) {
  final t = cell.replaceAll(RegExp(r'[₹,%\s]'), '');
  final m = RegExp(r'^-?\d+(\.\d+)?').firstMatch(t);
  if (m == null || m.end < t.length && !RegExp(r'^[a-zA-Z★]+$').hasMatch(t.substring(m.end))) return null;
  return num.tryParse(m.group(0)!);
}

/// Up to four charts for a table: counts by each column with a handful of values (status, type, city…), and the
/// total of the first amount column by the first of those.
List<ExportChart> chartsFor(List<String> columns, List<List<String>> rows) {
  if (rows.length < 2) return const [];
  final charts = <ExportChart>[];
  int? groupCol;
  for (final (i, c) in columns.indexed) {
    final values = [for (final r in rows) if (i < r.length && r[i] != '—' && r[i].isNotEmpty) r[i]];
    if (values.isEmpty || values.every((v) => numberIn(v) != null)) continue;
    final counts = <String, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.length < 2 || counts.length > 10 || counts.length == values.length) continue;
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    charts.add(ExportChart('By ${c.toLowerCase()}', [for (final e in sorted) e.key], [for (final e in sorted) e.value]));
    groupCol ??= i;
    if (charts.length == 3) break;
  }
  if (groupCol != null) {
    for (final (i, c) in columns.indexed) {
      final cells = [for (final r in rows) i < r.length ? r[i] : ''];
      if (!cells.any((v) => v.contains('₹')) || cells.any((v) => v.isNotEmpty && v != '—' && numberIn(v) == null)) continue;
      final sums = <String, num>{};
      for (final r in rows) {
        final n = numberIn(r[i]);
        if (n != null) sums[r[groupCol]] = (sums[r[groupCol]] ?? 0) + n;
      }
      final sorted = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      charts.add(ExportChart('$c by ${columns[groupCol].toLowerCase()}', [for (final e in sorted) e.key], [for (final e in sorted) e.value]));
      break;
    }
  }
  return charts;
}

String _figure(num v) => v == v.roundToDouble() ? NumberFormat.decimalPattern('en_IN').format(v) : NumberFormat('#,##0.##', 'en_IN').format(v);

// ---------------------------------------------------------------- building each format

Future<Uint8List> buildExport(ExportBundle b, ExportFormat f, {bool charts = true}) async => switch (f) {
  ExportFormat.pdf => _pdf(b, charts: charts),
  ExportFormat.pptx => Uint8List.fromList(_pptx(b, charts: charts)),
  ExportFormat.docx => Uint8List.fromList(_docx(b, charts: charts)),
  ExportFormat.xlsx => Uint8List.fromList(_xlsx(b)),
  ExportFormat.csv => Uint8List.fromList(utf8.encode('﻿${toCsv(b)}')), // the BOM lets Excel read ₹ and accents
};

const _palette = [0x0F8A6F, 0x5B3F73, 0xE0A33A, 0x3C7DC4, 0xC8553D, 0x6BBF9F, 0x9A7BB8, 0x2F4858, 0xB8860B, 0x7A8C88];
final _stamp = DateFormat('d MMM yyyy, h:mm a');

String _csvCell(String s) => RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

String toCsv(ExportBundle b) {
  final out = StringBuffer();
  final several = b.tables.length > 1;
  for (final (n, t) in b.tables.indexed) {
    if (several) {
      if (n > 0) out.write('\r\n');
      out.write('${_csvCell(t.title)}\r\n');
    }
    out.write('${t.columns.map(_csvCell).join(',')}\r\n');
    for (final r in t.rows) {
      out.write('${r.map(_csvCell).join(',')}\r\n');
    }
  }
  return out.toString();
}

// PDF ---------------------------------------------------------------

Future<Uint8List> _pdf(ExportBundle b, {required bool charts}) async {
  final doc = pw.Document(title: b.title, author: 'PIAX Admin');
  final green = PdfColor.fromInt(0xFF0B5B4E);
  final muted = PdfColor.fromInt(0xFF5A6C68);
  pw.Widget chart(ExportChart c) {
    final top = c.values.fold<num>(0, math.max);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromInt(0xFFE1E8E6)), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(c.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 6),
        for (final (i, l) in c.labels.take(12).indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(children: [
              pw.SizedBox(width: 120, child: pw.Text(l, maxLines: 1, style: const pw.TextStyle(fontSize: 9))),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (context, box) => pw.Row(children: [
                    pw.Container(
                      width: math.max(2, (box?.maxWidth ?? 200) * (top == 0 ? 0 : c.values[i] / top)),
                      height: 9,
                      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF000000 | _palette[i % _palette.length]), borderRadius: pw.BorderRadius.circular(2)),
                    ),
                  ]),
                ),
              ),
              pw.SizedBox(width: 70, child: pw.Text(_figure(c.values[i]), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ]),
          ),
      ]),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: green, width: 1.5))),
        child: pw.Row(children: [
          pw.Text('PIAX Admin', style: pw.TextStyle(color: green, fontWeight: pw.FontWeight.bold)),
          pw.Spacer(),
          pw.Text(b.title, style: pw.TextStyle(color: muted, fontSize: 10)),
        ]),
      ),
      footer: (context) => pw.Row(children: [
        pw.Text('Exported ${_stamp.format(DateTime.now())}', style: pw.TextStyle(color: muted, fontSize: 8)),
        pw.Spacer(),
        pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(color: muted, fontSize: 8)),
      ]),
      build: (context) => [
        pw.Text(b.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: green)),
        if (b.subtitle != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(b.subtitle!, style: pw.TextStyle(color: muted, fontSize: 10))),
        pw.SizedBox(height: 14),
        for (final t in b.tables) ...[
          if (b.tables.length > 1) pw.Header(level: 1, text: t.title, textStyle: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: green)),
          if (t.note != null) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: pw.Text(t.note!, style: pw.TextStyle(color: muted, fontSize: 9.5))),
          if (charts && t.charts.isNotEmpty)
            pw.Wrap(spacing: 12, children: [for (final c in t.charts) pw.SizedBox(width: 370, child: chart(c))]),
          if (t.rows.isEmpty)
            pw.Text('No records.', style: pw.TextStyle(color: muted))
          else
            pw.TableHelper.fromTextArray(
              headers: t.columns,
              data: t.rows,
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
              headerDecoration: pw.BoxDecoration(color: green),
              cellStyle: const pw.TextStyle(fontSize: 8),
              oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F6F5)),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              border: null,
            ),
          pw.SizedBox(height: 18),
        ],
        if (b.skipped.isNotEmpty) pw.Text('Not included (no records to export): ${b.skipped.join(', ')}.', style: pw.TextStyle(color: muted, fontSize: 9)),
      ],
    ),
  );
  return doc.save();
}

// Office files ------------------------------------------------------

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

const _xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

List<int> _zip(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(a);
}

String _rels(List<(String id, String type, String target)> rels) =>
    '$_xml<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${rels.map((r) => '<Relationship Id="${r.$1}" Type="${r.$2}" Target="${r.$3}"/>').join()}</Relationships>';

const _officeDoc = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';
const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

// Excel: a sheet per page, the header row in bold and frozen; figures as numbers.

List<int> _xlsx(ExportBundle b) {
  final names = <String>[];
  for (final t in b.tables) {
    var n = t.title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (n.isEmpty) n = 'Sheet';
    if (n.length > 28) n = n.substring(0, 28);
    var name = n;
    for (var k = 2; names.any((x) => x.toLowerCase() == name.toLowerCase()); k++) {
      name = '$n $k';
    }
    names.add(name);
  }
  if (names.isEmpty) names.add('Sheet1');
  String col(int i) => i < 26 ? String.fromCharCode(65 + i) : '${col(i ~/ 26 - 1)}${String.fromCharCode(65 + i % 26)}';
  String cell(int r, int c, String v, {bool head = false}) {
    final ref = '${col(c)}${r + 1}';
    final n = head ? null : numberIn(v);
    final plain = n != null && RegExp(r'^-?[\d,]+(\.\d+)?$').hasMatch(v.trim());
    if (plain) return '<c r="$ref"><v>$n</v></c>';
    return '<c r="$ref" t="inlineStr"${head ? ' s="1"' : ''}><is><t xml:space="preserve">${_x(v)}</t></is></c>';
  }

  String sheet(ExportTable? t) {
    final rows = t == null ? <List<String>>[] : [t.columns, ...t.rows];
    final widths = t == null
        ? ''
        : '<cols>${[for (var i = 0; i < t.columns.length; i++) '<col min="${i + 1}" max="${i + 1}" width="${math.min(50, math.max(10, [for (final r in rows) i < r.length ? r[i].length : 0].fold(0, math.max) + 2))}" customWidth="1"/>'].join()}</cols>';
    return '$_xml<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '$widths<sheetData>'
        '${[for (final (ri, r) in rows.indexed) '<row r="${ri + 1}">${[for (final (ci, v) in r.indexed) cell(ri, ci, v, head: ri == 0)].join()}</row>'].join()}'
        '</sheetData></worksheet>';
  }

  final files = <String, String>{
    '[Content_Types].xml':
        '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= names.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
    '_rels/.rels': _rels([('rId1', _officeDoc, 'xl/workbook.xml')]),
    'xl/workbook.xml':
        '$_xml<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="$_r"><sheets>'
        '${[for (final (i, n) in names.indexed) '<sheet name="${_x(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': _rels([
      for (var i = 1; i <= names.length; i++) ('rId$i', '$_r/worksheet', 'worksheets/sheet$i.xml'),
      ('rId${names.length + 1}', '$_r/styles', 'styles.xml'),
    ]),
    'xl/styles.xml':
        '$_xml<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF0B5B4E"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
        '</styleSheet>',
  };
  for (var i = 0; i < names.length; i++) {
    files['xl/worksheets/sheet${i + 1}.xml'] = sheet(i < b.tables.length ? b.tables[i] : null);
  }
  return _zip(files);
}

// Word: a heading, then each page's charts (shaded bars) and table.

List<int> _docx(ExportBundle b, {required bool charts}) {
  String run(String t, {bool bold = false, int size = 20, String? color}) =>
      '<w:r><w:rPr>${bold ? '<w:b/>' : ''}${color != null ? '<w:color w:val="$color"/>' : ''}<w:sz w:val="$size"/></w:rPr><w:t xml:space="preserve">${_x(t)}</w:t></w:r>';
  String para(String runs, {int after = 120}) => '<w:p><w:pPr><w:spacing w:after="$after"/></w:pPr>$runs</w:p>';
  String tc(String content, {int? width, String? fill, bool bold = false, String? color}) =>
      '<w:tc><w:tcPr>${width != null ? '<w:tcW w:w="$width" w:type="dxa"/>' : ''}${fill != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>' : ''}</w:tcPr>'
      '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>${content.isEmpty ? '' : run(content, bold: bold, size: 16, color: color)}</w:p></w:tc>';
  const borders = '<w:tblBorders><w:top w:val="single" w:sz="4" w:color="D3DDDA"/><w:bottom w:val="single" w:sz="4" w:color="D3DDDA"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="E6ECEA"/></w:tblBorders>';
  // Landscape A4 is 15840 twips wide less margins: 14400 for the content.
  const width = 14400;

  String chart(ExportChart c) {
    final top = c.values.fold<num>(0, math.max);
    const barMax = 9000;
    final rows = [
      for (final (i, l) in c.labels.take(12).indexed)
        () {
          final w = math.max(60, (barMax * (top == 0 ? 0 : c.values[i] / top)).round());
          final hex = _palette[i % _palette.length].toRadixString(16).padLeft(6, '0').toUpperCase();
          // The bar: a nested one-row table, its first cell shaded to the value's share of the largest.
          final bar = '<w:tbl><w:tblPr><w:tblW w:w="$barMax" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr>'
              '<w:tblGrid><w:gridCol w:w="$w"/>${w < barMax ? '<w:gridCol w:w="${barMax - w}"/>' : ''}</w:tblGrid><w:tr>'
              '${tc('', width: w, fill: hex)}${w < barMax ? tc('', width: barMax - w) : ''}</w:tr></w:tbl><w:p/>';
          return '<w:tr>${tc(l, width: 3000)}<w:tc><w:tcPr><w:tcW w:w="$barMax" w:type="dxa"/></w:tcPr>$bar</w:tc>'
              '${tc(_figure(c.values[i]), width: 2400, bold: true)}</w:tr>';
        }(),
    ];
    return '${para(run(c.title, bold: true, size: 20), after: 60)}'
        '<w:tbl><w:tblPr><w:tblW w:w="$width" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="$barMax"/><w:gridCol w:w="2400"/></w:tblGrid>${rows.join()}</w:tbl>'
        '${para('', after: 120)}';
  }

  String table(ExportTable t) {
    final cw = (width / math.max(1, t.columns.length)).floor();
    return '<w:tbl><w:tblPr><w:tblW w:w="$width" w:type="dxa"/>$borders<w:tblLayout w:type="fixed"/></w:tblPr>'
        '<w:tblGrid>${[for (final _ in t.columns) '<w:gridCol w:w="$cw"/>'].join()}</w:tblGrid>'
        '<w:tr><w:trPr><w:tblHeader/></w:trPr>${[for (final c in t.columns) tc(c, width: cw, fill: '0B5B4E', bold: true, color: 'FFFFFF')].join()}</w:tr>'
        '${[for (final (i, r) in t.rows.indexed) '<w:tr>${[for (final c in r) tc(c, width: cw, fill: i.isOdd ? 'F2F6F5' : null)].join()}</w:tr>'].join()}'
        '</w:tbl>';
  }

  final body = StringBuffer()
    ..write(para(run(b.title, bold: true, size: 36, color: '0B5B4E'), after: 60))
    ..write(para(run([?b.subtitle, 'Exported ${_stamp.format(DateTime.now())}'].join(' · '), size: 18, color: '5A6C68'), after: 240));
  for (final t in b.tables) {
    if (b.tables.length > 1) body.write(para(run(t.title, bold: true, size: 28, color: '0B5B4E'), after: 80));
    if (t.note != null) body.write(para(run(t.note!, size: 18, color: '5A6C68')));
    if (charts) {
      for (final c in t.charts) {
        body.write(chart(c));
      }
    }
    body.write(t.rows.isEmpty ? para(run('No records.', color: '5A6C68')) : table(t));
    body.write(para('', after: 240));
  }
  if (b.skipped.isNotEmpty) body.write(para(run('Not included (no records to export): ${b.skipped.join(', ')}.', size: 18, color: '5A6C68')));

  return _zip({
    '[Content_Types].xml':
        '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>',
    '_rels/.rels': _rels([('rId1', _officeDoc, 'word/document.xml')]),
    'word/document.xml':
        '$_xml<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="$_r"><w:body>$body'
        '<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/><w:pgMar w:top="1000" w:right="1200" w:bottom="1000" w:left="1200" w:header="500" w:footer="500" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>',
  });
}

// PowerPoint: a title slide, then per page a chart slide each (bars drawn as shapes) and its records, 12 rows and up
// to 8 columns a slide.

List<int> _pptx(ExportBundle b, {required bool charts}) {
  const sw = 12192000, sh = 6858000; // 16:9, in EMU
  var shapeId = 2;
  String text(String t, int x, int y, int w, int h, {int size = 1400, bool bold = false, String color = '0C1C19', String align = 'l'}) =>
      '<p:sp><p:nvSpPr><p:cNvPr id="${shapeId++}" name="Text"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
      '<p:txBody><a:bodyPr wrap="square" lIns="0" rIns="0" tIns="0" bIns="0" anchor="ctr"><a:normAutofit/></a:bodyPr><a:lstStyle/>'
      '<a:p><a:pPr algn="$align"/><a:r><a:rPr lang="en-IN" sz="$size" b="${bold ? 1 : 0}" dirty="0"><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr>'
      '<a:t>${_x(t)}</a:t></a:r></a:p></p:txBody></p:sp>';
  String rect(int x, int y, int w, int h, String fill) =>
      '<p:sp><p:nvSpPr><p:cNvPr id="${shapeId++}" name="Bar"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="roundRect"><a:avLst/></a:prstGeom>'
      '<a:solidFill><a:srgbClr val="$fill"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>';
  String slide(String shapes) {
    shapeId = 2;
    return '$_xml<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$_r" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '$shapes</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
  }

  const m = 457200; // a half-inch margin
  String heading(String title, String? sub) =>
      rect(0, 0, sw, 76200, '0B5B4E') +
      text(title, m, 260000, sw - 2 * m, 520000, size: 2600, bold: true, color: '0B5B4E') +
      (sub == null ? '' : text(sub, m, 780000, sw - 2 * m, 300000, size: 1200, color: '5A6C68'));

  final slides = <String>[];
  slides.add(slide(
    '${rect(0, 0, sw, sh, '0B5B4E')}${text(b.title, m * 2, 2300000, sw - 4 * m, 1000000, size: 4000, bold: true, color: 'FFFFFF')}'
    '${text([?b.subtitle, 'PIAX Admin · exported ${_stamp.format(DateTime.now())}'].join(' · '), m * 2, 3400000, sw - 4 * m, 500000, size: 1600, color: 'CFE7DF')}',
  ));

  for (final t in b.tables) {
    final prefix = b.tables.length > 1 ? '${t.title} · ' : '';
    if (charts) {
      for (final c in t.charts) {
        final labels = c.labels.take(10).toList();
        final top = c.values.fold<num>(0, math.max);
        final rowH = math.min(420000, (sh - 1500000) ~/ math.max(1, labels.length));
        const labelW = 2800000, valueW = 1600000;
        final barMax = sw - 2 * m - labelW - valueW - 200000;
        final shapes = StringBuffer(heading('$prefix${c.title}', t.note));
        for (final (i, l) in labels.indexed) {
          final y = 1250000 + i * rowH;
          final hex = _palette[i % _palette.length].toRadixString(16).padLeft(6, '0').toUpperCase();
          shapes
            ..write(text(l, m, y, labelW - 100000, rowH, size: 1200))
            ..write(rect(m + labelW, y + rowH ~/ 5, math.max(20000, (barMax * (top == 0 ? 0 : c.values[i] / top)).round()), rowH * 3 ~/ 5, hex))
            ..write(text(_figure(c.values[i]), sw - m - valueW, y, valueW, rowH, size: 1200, bold: true, align: 'r'));
        }
        slides.add(slide('$shapes'));
      }
    }
    final cols = t.columns.take(8).toList();
    final more = t.columns.length - cols.length;
    final pages = math.max(1, (t.rows.length / 12).ceil());
    for (var p = 0; p < pages; p++) {
      final rows = t.rows.skip(p * 12).take(12).toList();
      final cw = (sw - 2 * m) ~/ math.max(1, cols.length);
      const rh = 370840;
      String cell(String v, {bool head = false, bool shade = false}) =>
          '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-IN" sz="1000" b="${head ? 1 : 0}" dirty="0">'
          '<a:solidFill><a:srgbClr val="${head ? 'FFFFFF' : '0C1C19'}"/></a:solidFill></a:rPr><a:t>${_x(v)}</a:t></a:r></a:p></a:txBody>'
          '<a:tcPr marL="60000" marR="60000" marT="30000" marB="30000" anchor="ctr">'
          '${head ? '<a:solidFill><a:srgbClr val="0B5B4E"/></a:solidFill>' : shade ? '<a:solidFill><a:srgbClr val="F2F6F5"/></a:solidFill>' : '<a:noFill/>'}</a:tcPr></a:tc>';
      final tbl = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="${shapeId++}" name="Table"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
          '<p:xfrm><a:off x="$m" y="1250000"/><a:ext cx="${cw * cols.length}" cy="${rh * (rows.length + 1)}"/></p:xfrm>'
          '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1"/>'
          '<a:tblGrid>${[for (final _ in cols) '<a:gridCol w="$cw"/>'].join()}</a:tblGrid>'
          '<a:tr h="$rh">${[for (final c in cols) cell(c, head: true)].join()}</a:tr>'
          '${[for (final (i, r) in rows.indexed) '<a:tr h="$rh">${[for (var c = 0; c < cols.length; c++) cell(c < r.length ? r[c] : '', shade: i.isOdd)].join()}</a:tr>'].join()}'
          '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
      final sub = [
        if (pages > 1) 'Records ${p * 12 + 1}–${p * 12 + rows.length} of ${t.rows.length}' else '${t.rows.length} records',
        if (more > 0) '$more more fields in the Excel or PDF export',
      ].join(' · ');
      slides.add(slide('${heading('$prefix${b.tables.length > 1 ? 'Records' : t.title}', sub)}${rows.isEmpty ? text('No records.', m, 1300000, sw - 2 * m, 400000) : tbl}'));
    }
  }

  const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="$_r" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
  const emptyTree = '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>';
  String fill(String c) => '<a:solidFill><a:srgbClr val="$c"/></a:solidFill>';
  final theme = '$_xml<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="PIAX"><a:themeElements>'
      '<a:clrScheme name="PIAX"><a:dk1><a:srgbClr val="0C1C19"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="0B5B4E"/></a:dk2>'
      '<a:lt2><a:srgbClr val="F2F6F5"/></a:lt2><a:accent1><a:srgbClr val="0F8A6F"/></a:accent1><a:accent2><a:srgbClr val="5B3F73"/></a:accent2>'
      '<a:accent3><a:srgbClr val="E0A33A"/></a:accent3><a:accent4><a:srgbClr val="3C7DC4"/></a:accent4><a:accent5><a:srgbClr val="C8553D"/></a:accent5>'
      '<a:accent6><a:srgbClr val="6BBF9F"/></a:accent6><a:hlink><a:srgbClr val="0B5B4E"/></a:hlink><a:folHlink><a:srgbClr val="5B3F73"/></a:folHlink></a:clrScheme>'
      '<a:fontScheme name="PIAX"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
      '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
      '<a:fmtScheme name="PIAX"><a:fillStyleLst>${fill('FFFFFF') * 3}</a:fillStyleLst>'
      '<a:lnStyleLst>${'<a:ln w="9525">${fill('D3DDDA')}</a:ln>' * 3}</a:lnStyleLst>'
      '<a:effectStyleLst>${'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst>'
      '<a:bgFillStyleLst>${fill('FFFFFF') * 3}</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';

  final files = <String, String>{
    '[Content_Types].xml':
        '$_xml<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '${[for (var i = 1; i <= slides.length; i++) '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'].join()}'
        '</Types>',
    '_rels/.rels': _rels([('rId1', _officeDoc, 'ppt/presentation.xml')]),
    'ppt/presentation.xml':
        '$_xml<p:presentation $ns><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>${[for (var i = 0; i < slides.length; i++) '<p:sldId id="${256 + i}" r:id="rId${i + 3}"/>'].join()}</p:sldIdLst>'
        '<p:sldSz cx="$sw" cy="$sh"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>',
    'ppt/_rels/presentation.xml.rels': _rels([
      ('rId1', '$_r/slideMaster', 'slideMasters/slideMaster1.xml'),
      ('rId2', '$_r/theme', 'theme/theme1.xml'),
      for (var i = 0; i < slides.length; i++) ('rId${i + 3}', '$_r/slide', 'slides/slide${i + 1}.xml'),
    ]),
    'ppt/slideMasters/slideMaster1.xml':
        '$_xml<p:sldMaster $ns>$emptyTree'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>',
    'ppt/slideMasters/_rels/slideMaster1.xml.rels': _rels([('rId1', '$_r/slideLayout', '../slideLayouts/slideLayout1.xml'), ('rId2', '$_r/theme', '../theme/theme1.xml')]),
    'ppt/slideLayouts/slideLayout1.xml': '$_xml<p:sldLayout $ns type="blank" preserve="1">$emptyTree<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>',
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _rels([('rId1', '$_r/slideMaster', '../slideMasters/slideMaster1.xml')]),
    'ppt/theme/theme1.xml': theme,
  };
  for (final (i, s) in slides.indexed) {
    files['ppt/slides/slide${i + 1}.xml'] = s;
    files['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _rels([('rId1', '$_r/slideLayout', '../slideLayouts/slideLayout1.xml')]);
  }
  return _zip(files);
}

// ---------------------------------------------------------------- the dialog

/// Asks what to export (format, fields, which records, charts) and saves the file. [build] gives the records:
/// all of them ([all] true) or only those shown with the page's search and filters.
Future<void> showExportDialog(
  BuildContext context, {
  required String title,
  required Future<ExportBundle> Function({required bool all}) build,
  List<String> fields = const [],
  bool canFilter = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ExportDialog(title: title, build: build, fields: fields, canFilter: canFilter),
);

/// The page's top-bar button that opens [showExportDialog].
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width >= 700
      ? Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(onPressed: onPressed, icon: const Icon(Icons.file_download_outlined, size: 18), label: const Text('Export')),
        )
      : IconButton.filled(tooltip: 'Export', onPressed: onPressed, icon: const Icon(Icons.file_download_outlined));
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.title, required this.build, required this.fields, required this.canFilter});
  final String title;
  final Future<ExportBundle> Function({required bool all}) build;
  final List<String> fields;
  final bool canFilter;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportFormat _format = ExportFormat.pdf;
  bool _charts = true, _all = false, _busy = false;
  late final Set<String> _fields = {...widget.fields};

  Future<void> _go() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    try {
      var bundle = await widget.build(all: !widget.canFilter || _all);
      if (widget.fields.isNotEmpty) {
        bundle = ExportBundle(title: bundle.title, subtitle: bundle.subtitle, skipped: bundle.skipped, tables: [for (final t in bundle.tables) t.only(_fields)]);
      }
      final bytes = await buildExport(bundle, _format, charts: _charts && _format.charts);
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final name = '${widget.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '')}-$stamp.${_format.extension}';
      // In the browser this downloads the file (and returns nothing); elsewhere it asks where to save it.
      await FilePicker.saveFile(fileName: name, bytes: bytes, dialogTitle: 'Save $name');
      nav.pop();
      messenger?.showSnackBar(SnackBar(content: Text('Exported $name.')));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger?.showSnackBar(SnackBar(content: Text('Couldn’t export: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: Text('Export ${widget.title}'),
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      content: SizedBox(
        width: 520,
        child: ListView(shrinkWrap: true, children: [
          const Text('Format', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in ExportFormat.values)
              ChoiceChip(
                avatar: Icon(f.icon, size: 18, color: f == _format ? brand : const TColor(0xFF5A6C68)),
                label: Text(f.label),
                selected: f == _format,
                onSelected: (_) => setState(() => _format = f),
              ),
          ]),
          if (_format.charts)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include charts'),
              subtitle: const Text('Counts by status and choices, and amount totals.'),
              value: _charts,
              onChanged: (v) => setState(() => _charts = v),
            ),
          if (widget.canFilter) ...[
            const SizedBox(height: 8),
            const Text('Records', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioGroup<bool>(
              groupValue: _all,
              onChanged: (v) => setState(() => _all = v ?? _all),
              child: const Column(children: [
                RadioListTile(contentPadding: EdgeInsets.zero, value: false, title: Text('As shown (with the page’s search and filters)')),
                RadioListTile(contentPadding: EdgeInsets.zero, value: true, title: Text('All records')),
              ]),
            ),
          ],
          if (widget.fields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Text('Fields', style: TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                onPressed: () => setState(() => _fields.length == widget.fields.length ? _fields.clear() : _fields.addAll(widget.fields)),
                child: Text(_fields.length == widget.fields.length ? 'None' : 'All'),
              ),
            ]),
            for (final f in widget.fields)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(f),
                value: _fields.contains(f),
                onChanged: (v) => setState(() => v == true ? _fields.add(f) : _fields.remove(f)),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy || (widget.fields.isNotEmpty && _fields.isEmpty) ? null : _go,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_download_outlined),
          label: Text(_busy ? 'Exporting…' : 'Export ${_format.label}'),
        ),
      ],
    );
  }
}
