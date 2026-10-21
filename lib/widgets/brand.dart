import 'package:flutter/material.dart';

import '../format.dart';

/// Screen-size steps shared by every page: phones get one column, tablets more room, desktops side-by-side layouts.
class Breakpoints {
  static const tablet = 700.0;
  static const desktop = 1000.0;
  static const wide = 1600.0;
}

/// The deep PIAX green with soft light, behind sign-in and page headers.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.borderRadius});
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), brand, Color(0xFF073B33)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(top: -120, right: -80, child: _Glow(size: 340, color: Color(0x33FFFFFF))),
          const Positioned(bottom: -140, left: -100, child: _Glow(size: 380, color: Color(0x26BFE8D5))),
          Positioned.fill(child: child),
        ],
      ),
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

/// The white PIAX wordmark ("Feel different. Feel you.") for dark backgrounds.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 40});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/logo-white.webp',
    height: height,
    fit: BoxFit.contain,
    semanticLabel: 'PIAX',
    errorBuilder: (_, _, _) => Text(
      'PIAX',
      style: TextStyle(color: Colors.white, fontSize: height * .6, fontWeight: FontWeight.w600, letterSpacing: 3),
    ),
  );
}

/// A page body that stays readable on very wide screens: centred, at most [maxWidth] across.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.maxWidth = 1200});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
