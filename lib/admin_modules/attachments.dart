import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';

// Files attached to a record: SOPs, certificates, contracts, invoices, lab reports and the like. The upload field in
// the add and edit forms picks them from the device (file_picker); the record keeps each file's name, size and type.
//
// Nothing is sent to a server: the admin modules and section pages run on demo data, and there's no upload endpoint
// yet. A file uploaded in this session is kept in memory with its record, so it can be downloaded (saved to the
// device; a normal download in the browser) or opened while the app is open. Demo files and files from an earlier
// session show their details only: there's no file behind them to download.

/// Document types most pages ask for.
const docTypes = ['pdf', 'doc', 'docx'];
const sheetTypes = ['xls', 'xlsx', 'csv'];
const imageTypes = ['jpg', 'jpeg', 'png'];

/// Largest file accepted, per file.
const maxUploadBytes = 10 * 1024 * 1024;

class Attachment {
  const Attachment({required this.name, this.size, required this.addedAt, this.uri, this.demo = false, this.bytes});

  final String name;
  final int? size;
  final DateTime addedAt;

  /// Where the picked file can be opened while the app is open; null for demo files.
  final String? uri;

  /// A made-up file in the demo data.
  final bool demo;

  /// The file itself, for downloading: kept in memory while the app is open (never saved with the record).
  final Uint8List? bytes;

  String get mimeType => switch (extension) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'csv' => 'text/csv',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  Map<String, dynamic> toJson() => {'name': name, 'size': size, 'addedAt': addedAt.toIso8601String(), if (demo) 'demo': true};

  static Attachment? fromJson(Object? j) {
    if (j is Attachment) return j;
    if (j is! Map) return null;
    final name = '${j['name'] ?? ''}';
    if (name.isEmpty) return null;
    return Attachment(name: name, size: (j['size'] as num?)?.toInt(), addedAt: DateTime.tryParse('${j['addedAt']}') ?? DateTime.now(), demo: j['demo'] == true);
  }
}

/// A record's files, whatever form they're stored in (attachments, or their JSON in module records).
List<Attachment> attachmentsOf(Object? value) => value is List ? [for (final v in value) ?Attachment.fromJson(v)] : const [];

String fileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// "PDF, DOC, DOCX · up to 10 MB each".
String acceptedLabel(List<String> types) => '${types.isEmpty ? 'Any file' : types.map((t) => t.toUpperCase()).join(', ')} · up to ${fileSize(maxUploadBytes)} each';

/// A short line for tables: "SOP-QA-07.pdf", "3 files", or "—".
String attachmentsSummary(Object? value) {
  final files = attachmentsOf(value);
  return switch (files.length) {
    0 => '—',
    1 => files.single.name,
    final n => '$n files',
  };
}

IconData fileIcon(String ext) => switch (ext) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'doc' || 'docx' || 'txt' => Icons.description_outlined,
  'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
  'jpg' || 'jpeg' || 'png' || 'webp' => Icons.image_outlined,
  'zip' => Icons.folder_zip_outlined,
  _ => Icons.insert_drive_file_outlined,
};

Color _fileTone(String ext) => switch (ext) {
  'pdf' => const Color(0xFFB3261E),
  'doc' || 'docx' => const Color(0xFF2D5F80),
  'xls' || 'xlsx' || 'csv' => const Color(0xFF0F766E),
  _ => const Color(0xFF5B3F73),
};

/// The upload field of a form: a dashed drop area with "Choose files", what it takes, then the files chosen, each
/// removable. Checks the type and size of each file and, when [mandatory], that there's at least one.
class AttachmentField extends FormField<List<Attachment>> {
  AttachmentField({
    super.key,
    required String label,
    required List<Attachment> initial,
    required ValueChanged<List<Attachment>> onChanged,
    List<String> types = docTypes,
    bool multiple = true,
    bool mandatory = false,
    String? help,
  }) : super(
         initialValue: initial,
         validator: (v) => mandatory && (v == null || v.isEmpty) ? 'Upload the ${label.toLowerCase()}.' : null,
         builder: (state) => _AttachmentEditor(
           label: label,
           files: state.value ?? const [],
           types: types,
           multiple: multiple,
           required: mandatory,
           help: help,
           error: state.errorText,
           onChanged: (files) {
             state.didChange(files);
             onChanged(files);
           },
         ),
       );
}

class _AttachmentEditor extends StatefulWidget {
  const _AttachmentEditor({required this.label, required this.files, required this.types, required this.multiple, required this.required, required this.onChanged, this.help, this.error});
  final String label;
  final List<Attachment> files;
  final List<String> types;
  final bool multiple, required;
  final String? help, error;
  final ValueChanged<List<Attachment>> onChanged;

  @override
  State<_AttachmentEditor> createState() => _AttachmentEditorState();
}

class _AttachmentEditorState extends State<_AttachmentEditor> {
  bool _busy = false;

  Future<void> _choose() async {
    setState(() => _busy = true);
    List<PlatformFile> picked = const [];
    try {
      picked = widget.multiple
          ? await FilePicker.pickFiles(type: widget.types.isEmpty ? FileType.any : FileType.custom, allowedExtensions: widget.types.isEmpty ? null : widget.types)
          : [?await FilePicker.pickFile(type: widget.types.isEmpty ? FileType.any : FileType.custom, allowedExtensions: widget.types.isEmpty ? null : widget.types)];
    } catch (_) {
      if (mounted) _say('Couldn’t open the file picker on this device.');
    }
    if (!mounted) return;
    final added = <Attachment>[];
    final refused = <String>[];
    for (final f in picked) {
      final ext = (f.extension ?? '').toLowerCase();
      final size = f.lengthSync() ?? await f.length();
      if (widget.types.isNotEmpty && !widget.types.contains(ext)) {
        refused.add('${f.name}: not a ${widget.types.map((t) => t.toUpperCase()).join('/')} file');
      } else if (size != null && size > maxUploadBytes) {
        refused.add('${f.name}: larger than ${fileSize(maxUploadBytes)}');
      } else {
        Uint8List? bytes;
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          // Not readable here: attached by name, but it can't be downloaded again.
        }
        added.add(Attachment(name: f.name, size: size ?? bytes?.length, addedAt: DateTime.now(), uri: f.uri.toString(), bytes: bytes));
      }
    }
    setState(() => _busy = false);
    if (added.isNotEmpty) widget.onChanged(widget.multiple ? [...widget.files, ...added] : [added.first]);
    if (refused.isNotEmpty) _say('Not added: ${refused.join('; ')}.');
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final border = error != null ? Theme.of(context).colorScheme.error : const Color(0xFFB9CCC6);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${widget.label}${widget.required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF26413B))),
      const SizedBox(height: 6),
      CustomPaint(
        painter: _DashedBorder(border),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : _choose,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE3F2EC), borderRadius: BorderRadius.circular(10)),
                child: _busy ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file, color: brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.files.isEmpty || widget.multiple ? (widget.multiple ? 'Choose files to upload' : 'Choose a file to upload') : 'Replace the file',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: brand)),
                  const SizedBox(height: 2),
                  Text(acceptedLabel(widget.types), style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
      if (widget.help != null) Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: Text(widget.help!, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
      if (widget.files.isNotEmpty) ...[
        const SizedBox(height: 8),
        AttachmentList(files: widget.files, onRemove: (f) => widget.onChanged([...widget.files]..remove(f))),
      ],
    ]);
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Saves [f] to the device: a download in the browser, a save dialog on desktop and phones. Says how it went.
Future<void> downloadAttachment(BuildContext context, Attachment f) async {
  final bytes = f.bytes;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (bytes == null) {
    messenger?.showSnackBar(SnackBar(content: Text(f.demo ? '${f.name} is a demo file: there’s no file to download.' : 'Upload ${f.name} again to download it (files are kept only while the app is open).')));
    return;
  }
  try {
    final saved = await FilePicker.saveFile(fileName: f.name, bytes: bytes, mimeType: f.mimeType, dialogTitle: 'Save ${f.name}');
    if (saved != null) messenger?.showSnackBar(SnackBar(content: Text('Downloaded ${f.name}.')));
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn’t download ${f.name} on this device.')));
  }
}

/// The files of a record, one per line: type icon, name, size and date; download and open (when the file is at
/// hand) and, in a form, remove. Several files can be downloaded together.
class AttachmentList extends StatelessWidget {
  const AttachmentList({super.key, required this.files, this.onRemove});
  final List<Attachment> files;
  final ValueChanged<Attachment>? onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const Text('No files yet.', style: TextStyle(color: Color(0xFF8A9A96), fontSize: 13));
    final date = DateFormat('d MMM yyyy');
    final ready = [for (final f in files) if (f.bytes != null) f];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final f in files)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(color: const Color(0xFFF7FAF9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE6EEEB))),
          child: Row(children: [
            Icon(fileIcon(f.extension), size: 22, color: _fileTone(f.extension)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  [if (f.size != null) fileSize(f.size), 'added ${date.format(f.addedAt)}', if (f.demo) 'demo file'].join(' · '),
                  style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 11.5),
                ),
              ]),
            ),
            IconButton(
              tooltip: f.bytes != null ? 'Download ${f.name}' : f.demo ? 'Demo file: nothing to download' : 'Upload again to download',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.download_outlined, size: 19, color: f.bytes != null ? brand : const Color(0xFFB4C2BE)),
              onPressed: () => downloadAttachment(context, f),
            ),
            if (f.uri != null && f.bytes != null)
              IconButton(
                tooltip: 'Open',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () => launchUrl(Uri.parse(f.uri!)),
              ),
            if (onRemove != null)
              IconButton(tooltip: 'Remove', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => onRemove!(f)),
          ]),
        ),
      if (ready.length > 1)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              for (final f in ready) {
                await downloadAttachment(context, f);
              }
            },
            icon: const Icon(Icons.download, size: 18),
            label: Text('Download all ${ready.length}'),
          ),
        ),
    ]);
  }
}
