import 'package:flutter/painting.dart';

/// A colour from the light design that follows the app's theme: in dark mode it is redrawn as its dark counterpart
/// (light backgrounds and borders turn dark, dark text turns light, mid tones lighten), so every screen's fixed colours
/// work in both themes without a second palette. Brand fills (buttons with white text) stay plain [Color]s.
class TColor extends Color {
  const TColor(super.value);

  /// Set by the app when the theme changes (main.dart); every TColor reads it when painted.
  static bool dark = false;
  static final _cache = <int, Color>{};

  // Keyed by the light colour's own value, read from the fields (not the theme-aware getters).
  int get _key => (super.a * 255).round() << 24 | (super.r * 255).round() << 16 | (super.g * 255).round() << 8 | (super.b * 255).round();
  Color get _dark => _cache.putIfAbsent(_key, () => _toDark(super.a, super.r, super.g, super.b));

  @override
  double get a => dark ? _dark.a : super.a;
  @override
  double get r => dark ? _dark.r : super.r;
  @override
  double get g => dark ? _dark.g : super.g;
  @override
  double get b => dark ? _dark.b : super.b;

  /// Brand greens: a mid teal in dark mode, readable as text on dark surfaces and still carrying white text on buttons.
  static const _fixed = {0xFF0B5B4E: Color(0xFF2BAA8F), 0xFF0F766E: Color(0xFF27A99A), 0xFF083F37: Color(0xFF17806B)};

  static Color _toDark(double a, double r, double g, double b) {
    final light = Color.from(alpha: a, red: r, green: g, blue: b);
    if (_fixed[light.toARGB32()] case final c?) return c;
    if (a < 1) return light; // overlays and shadows keep their tint
    final hsl = HSLColor.fromColor(light);
    final l = hsl.lightness;
    final double dl;
    if (l >= .985) {
      dl = .13; // white cards and panels
    } else if (l >= .93) {
      dl = .085; // page backgrounds and soft fills
    } else if (l >= .6) {
      dl = .12 + (.93 - l) * .6; // tinted chips, borders and dividers
    } else if (l >= .3) {
      dl = (l + .25).clamp(0, .9); // muted text and mid tones
    } else {
      dl = .92 - l * .5; // ink: dark text turns light
    }
    return hsl.withLightness(dl.clamp(0, 1).toDouble()).toColor();
  }
}
