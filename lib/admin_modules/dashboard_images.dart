import 'package:flutter/material.dart';

// Pictures for the admin dashboard, copied from the website (public/images): product packshots, PIAX Learn
// thumbnails, the PIAX AI robot and the brand leaf. Records without a matching picture just show their icon.

const _dir = 'assets/dashboard';
const heroLeaf = '$_dir/sprig.webp';
const heroLeafBroad = '$_dir/leaf-broad.webp';
const robotImage = '$_dir/robot-head.webp';

const _products = {'vera': 'vera', 'luma': 'luma', 'nocte': 'nocte', 'seren': 'seren', 'cycle': 'cycle'};

/// Words in a Learn article's title → its thumbnail.
const _learn = {
  'first period': 'preparing-for-your-first-period',
  'day pads': 'day-vs-night-pads',
  'sleeping': 'day-vs-night-pads',
  'change a pad': 'daily-menstrual-hygiene',
  'hygiene': 'daily-menstrual-hygiene',
  'phases': 'four-phases-of-the-menstrual-cycle',
  'cycle': 'four-phases-of-the-menstrual-cycle',
  'cramps': 'can-you-exercise-on-your-period',
  'exercise': 'can-you-exercise-on-your-period',
  'pad size': 'choosing-the-right-pad-size',
  'myth': 'period-myths-and-facts',
};

String? _learnImage(String title) {
  final t = title.toLowerCase();
  for (final e in _learn.entries) {
    if (t.contains(e.key)) return '$_dir/learn/${e.value}.webp';
  }
  return null;
}

/// The picture for one record, if it has one.
String? recordImage(String module, Map<String, dynamic> record) {
  switch (module) {
    case 'products':
      final name = '${record['name'] ?? ''}'.toLowerCase();
      for (final e in _products.entries) {
        if (name.contains(e.key)) return '$_dir/products/${e.value}.webp';
      }
      return null;
    case 'articles':
      return _learnImage('${record['title'] ?? ''}');
    case 'myths':
      return '$_dir/learn/period-myths-and-facts.webp';
    case 'healthBots':
      return robotImage;
    default:
      return null;
  }
}

/// A picture for a whole module (its summary card), if it has one.
String? moduleImage(String module) => switch (module) {
  'products' => '$_dir/products/luma.webp',
  'articles' => '$_dir/learn/four-phases-of-the-menstrual-cycle.webp',
  'myths' => '$_dir/learn/period-myths-and-facts.webp',
  'healthBots' => robotImage,
  _ => null,
};

/// A rounded picture on a soft background; nothing if the file is missing.
class AssetThumb extends StatelessWidget {
  const AssetThumb(this.path, {super.key, this.size = 44, this.radius = 12, this.fit = BoxFit.cover});
  final String path;
  final double size, radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Container(
      width: size,
      height: size,
      color: const Color(0xFFEFF5F3),
      child: Image.asset(path, fit: fit, errorBuilder: (_, _, _) => const SizedBox.shrink()),
    ),
  );
}

/// A product's packshot by its name ("PIAX LUMA"), if there is one.
String? productImageFor(String name) => recordImage('products', {'name': name});
