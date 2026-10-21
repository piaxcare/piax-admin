import 'package:flutter/material.dart';

import '../format.dart';
import 'admin_search.dart';
import 'nav_config.dart';
import 'nav_pages.dart';

// The navigation pieces built from nav_config.dart: the section tree (sidebar and phone drawer), the folded icon rail,
// what opening an item does, and the demonstration page for items not built yet.

/// Opens [item]: inside the app frame the frame handles it (and highlights it); elsewhere the item's page or module
/// opens directly, and items not built yet open their demonstration page on [navigator].
void openNavItem(BuildContext context, AdminNav nav, NavItem item, {NavigatorState? navigator}) {
  if (nav.item != null) return nav.item!(item.id);
  final nav0 = navigator ?? Navigator.of(context);
  void demo() => nav0.push(MaterialPageRoute(settings: RouteSettings(name: 'nav:${item.id}'), builder: (_) => NavDemoPage(itemId: item.id)));
  switch (item.target) {
    case ModuleTarget(:final module, :final status):
      nav.module(module, status: status);
    case PageTarget(:final page):
      final go = switch (page) {
        AppPage.overview => nav.overview,
        AppPage.analytics => nav.analytics,
        AppPage.orders => nav.orders,
        AppPage.refunds => nav.refunds,
        AppPage.settings => nav.settings,
      };
      (go ?? demo)();
    case DemoTarget():
      demo();
  }
}

/// Colours for the dark (sidebar) and light (drawer) versions of the tree.
class _NavColors {
  const _NavColors.dark()
    : text = const Color(0xFFB9D6CF),
      strong = Colors.white,
      number = const Color(0xFF8DB8AE),
      activeBg = const Color(0x1FFFFFFF),
      activeFg = Colors.white,
      guide = const Color(0x33FFFFFF),
      focus = const Color(0x29FFFFFF);
  const _NavColors.light()
    : text = const Color(0xFF34443F),
      strong = const Color(0xFF0C1C19),
      number = const Color(0xFF8A9A96),
      activeBg = const Color(0xFFDDF3EC),
      activeFg = brand,
      guide = const Color(0xFFDCE6E3),
      focus = const Color(0x1A0B5B4E);
  final Color text, strong, number, activeBg, activeFg, guide, focus;
}

/// The 12 sections, each folding open to its items. Sections toggle independently; the section holding the current
/// page opens by itself, and the current item is highlighted.
class NavTree extends StatefulWidget {
  const NavTree({super.key, required this.nav, this.activeItemId, this.dark = true, this.beforeOpen});
  final AdminNav nav;
  final String? activeItemId;
  final bool dark;

  /// Runs before an item opens (the phone drawer closes itself).
  final VoidCallback? beforeOpen;

  @override
  State<NavTree> createState() => _NavTreeState();
}

class _NavTreeState extends State<NavTree> {
  final Set<String> _openSections = {};

  @override
  void initState() {
    super.initState();
    final activeSection = widget.activeItemId == null ? null : navSectionOf(widget.activeItemId!)?.id;
    if (activeSection != null) _openSections.add(activeSection);
  }

  @override
  void didUpdateWidget(NavTree old) {
    super.didUpdateWidget(old);
    if (widget.activeItemId != old.activeItemId && widget.activeItemId != null) {
      final section = navSectionOf(widget.activeItemId!)?.id;
      if (section != null) _openSections.add(section);
    }
  }

  void _openItem(NavItem item) {
    final navigator = Navigator.of(context);
    widget.beforeOpen?.call();
    openNavItem(context, widget.nav, item, navigator: navigator);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.dark ? const _NavColors.dark() : const _NavColors.light();
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);
    final activeSection = widget.activeItemId == null ? null : navSectionOf(widget.activeItemId!)?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in navSections) ...[
          Semantics(
            button: true,
            expanded: _openSections.contains(s.id),
            label: 'Section ${s.number}: ${s.label}',
            excludeSemantics: true,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                focusColor: c.focus,
                onTap: () => setState(() {
                  if (!_openSections.add(s.id)) _openSections.remove(s.id);
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text(s.numbered, style: TextStyle(color: c.number, fontSize: 11, fontWeight: FontWeight.w600))),
                    Icon(s.icon, size: 20, color: activeSection == s.id ? c.strong : c.text),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: activeSection == s.id ? c.strong : c.text, fontSize: 13.5, fontWeight: activeSection == s.id ? FontWeight.w600 : FontWeight.w600, height: 1.25),
                      ),
                    ),
                    AnimatedRotation(turns: _openSections.contains(s.id) ? 0.5 : 0, duration: motion, child: Icon(Icons.keyboard_arrow_down, size: 20, color: c.number)),
                  ]),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: motion,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_openSections.contains(s.id)
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(left: 30, bottom: 6),
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: c.guide))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in s.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Semantics(
                              selected: item.id == widget.activeItemId,
                              child: Material(
                                color: item.id == widget.activeItemId ? c.activeBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  focusColor: c.focus,
                                  onTap: () => _openItem(item),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                          item.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: item.id == widget.activeItemId ? c.activeFg : c.text,
                                            fontSize: 13,
                                            fontWeight: item.id == widget.activeItemId ? FontWeight.w600 : FontWeight.w500,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// The folded sidebar's sections: one icon each (its name on hover), opening a menu of the section's items.
class NavRail extends StatelessWidget {
  const NavRail({super.key, required this.nav, this.activeItemId});
  final AdminNav nav;
  final String? activeItemId;

  @override
  Widget build(BuildContext context) {
    final activeSection = activeItemId == null ? null : navSectionOf(activeItemId!)?.id;
    return Column(
      children: [
        for (final s in navSections)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PopupMenuButton<NavItem>(
              tooltip: '${s.numbered} ${s.label}',
              position: PopupMenuPosition.over,
              offset: const Offset(64, 0),
              onSelected: (item) => openNavItem(context, nav, item),
              itemBuilder: (_) => [
                PopupMenuItem<NavItem>(enabled: false, child: Text('${s.numbered}  ${s.label}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)))),
                for (final item in s.items)
                  PopupMenuItem<NavItem>(
                    value: item,
                    child: Text(item.label, style: TextStyle(fontWeight: item.id == activeItemId ? FontWeight.w600 : FontWeight.w500, color: item.id == activeItemId ? brand : null)),
                  ),
              ],
              child: Container(
                height: 44,
                decoration: BoxDecoration(color: activeSection == s.id ? Colors.white.withValues(alpha: .12) : null, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(s.icon, size: 21, color: activeSection == s.id ? Colors.white : const Color(0xFFB9D6CF)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The page for a menu item that isn't built yet: where it sits, what its section is for, and its sibling pages.
class NavDemoPage extends StatelessWidget {
  const NavDemoPage({super.key, required this.itemId, this.nav});
  final String itemId;

  /// For opening sibling items; without it they open directly.
  final AdminNav? nav;

  @override
  Widget build(BuildContext context) {
    final found = navItemById(itemId);
    if (found == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This page doesn’t exist.')));
    // Pages with a content spec (nav_pages.dart) show their full demo page.
    if (navPageSpecs[itemId] case final spec?) {
      return NavModulePage(itemId: itemId, spec: spec, onSibling: nav == null ? null : (other) => openNavItem(context, nav!, other));
    }
    final (section, item) = found;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Semantics(
                label: 'Breadcrumb',
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                  const Text('Admin', style: TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8A9A96)),
                  Text('${section.numbered} ${section.label}', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8A9A96)),
                  Text(item.label, style: const TextStyle(color: Color(0xFF0C1C19), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6EEEB))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: const Color(0xFFD8EEE3), borderRadius: BorderRadius.circular(14)),
                      child: Icon(section.icon, color: brand),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(item.label, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)))),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(999)),
                    child: const Text('Demonstration page: not built yet', style: TextStyle(color: Color(0xFF7F5300), fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This page belongs to ${section.label}, which ${section.purpose[0].toLowerCase()}${section.purpose.substring(1)} '
                    'It has no screen or data yet; nothing here is live.',
                    style: const TextStyle(color: Color(0xFF34443F), fontSize: 14, height: 1.45),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE6EEEB))),
                child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('In ${section.label}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final other in section.items)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      selected: other.id == item.id,
                      selectedColor: brand,
                      leading: Icon(other.target is DemoTarget ? Icons.science_outlined : Icons.check_circle_outline, size: 18),
                      title: Text(other.label),
                      subtitle: Text(other.target is DemoTarget ? 'Demonstration page' : 'Built: opens its screen', style: const TextStyle(fontSize: 12)),
                      onTap: other.id == item.id || nav == null ? null : () => openNavItem(context, nav!, other),
                    ),
                ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
