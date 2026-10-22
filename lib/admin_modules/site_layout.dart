import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// The layout of the website and the PIAX app, as the Site & app builder edits it: pages, the sections on each page
// (hero, product grid, cards, tags, ads, FAQ…) and the elements inside them (cards, tags, buttons, stats…), each with
// its order, visibility, alignment and colour.
//
// A demo copy of the layout is kept on this device. Connected to the local website (`next dev` on this machine), the
// website's Home page is the real one: its own sections (moved and hidden here) and sections added here, sent to the
// site's /api/dev/site-layout as they change, and the running site follows within a couple of seconds. Other pages and
// the app stay demo copies. The live (deployed) website never reads it. Product copy uses validated claims only.

enum Surface {
  website('Website', Icons.language),
  app('PIAX app', Icons.phone_iphone);

  const Surface(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum Align3 {
  left('Left', Icons.format_align_left, TextAlign.left, CrossAxisAlignment.start, WrapAlignment.start),
  center('Centre', Icons.format_align_center, TextAlign.center, CrossAxisAlignment.center, WrapAlignment.center),
  right('Right', Icons.format_align_right, TextAlign.right, CrossAxisAlignment.end, WrapAlignment.end);

  const Align3(this.label, this.icon, this.text, this.cross, this.wrap);
  final String label;
  final IconData icon;
  final TextAlign text;
  final CrossAxisAlignment cross;
  final WrapAlignment wrap;
}

/// The brand's soft tones (the website's card tones), plus white and the brand green.
enum Tone {
  white('White', Color(0xFFFFFFFF), Color(0xFF0C1C19)),
  mist('Mist', Color(0xFFF8FAFC), Color(0xFF0C1C19)),
  mint('Mint', Color(0xFFDDF3EC), Color(0xFF0B5B4E)),
  sage('Sage', Color(0xFFE4EDE3), Color(0xFF3E5E3C)),
  lavender('Lavender', Color(0xFFEDE4F3), Color(0xFF5B3F73)),
  peach('Peach', Color(0xFFFBE9DF), Color(0xFF8E4A30)),
  navy('Navy', Color(0xFF2B3A5C), Color(0xFFFFFFFF)),
  brand('Brand green', Color(0xFF0B5B4E), Color(0xFFFFFFFF));

  const Tone(this.label, this.background, this.ink);
  final String label;
  final Color background, ink;
}

enum ElementKind {
  card('Card', Icons.crop_portrait),
  product('Product card', Icons.inventory_2_outlined),
  tag('Tag', Icons.sell_outlined),
  button('Button', Icons.smart_button_outlined),
  stat('Number', Icons.pin_outlined),
  faq('Question', Icons.help_outline),
  quote('Quote', Icons.format_quote),
  ad('Ad', Icons.campaign_outlined),
  link('Link', Icons.link),
  image('Image', Icons.image_outlined);

  const ElementKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The component library: every kind of section a page can have, what it's for, and what it holds.
enum SectionKind {
  hero('Hero', Icons.view_day_outlined, 'The big opening: headline, a line under it and buttons.', [ElementKind.button, ElementKind.tag], 1),
  announcement('Announcement strip', Icons.campaign, 'A thin strip with a short message and a link.', [ElementKind.link], 1),
  productGrid('Product grid', Icons.grid_view, 'Product cards with their tags and a button.', [ElementKind.product, ElementKind.tag], 4),
  cardGrid('Card grid', Icons.dashboard_outlined, 'Cards in columns: guides, team, reasons, categories.', [ElementKind.card, ElementKind.image], 3),
  featureList('Features', Icons.checklist, 'What’s inside or why choose: short points with a line each.', [ElementKind.card], 4),
  tagRow('Tags', Icons.sell_outlined, 'A row of tags or quick filters.', [ElementKind.tag], 1),
  banner('Ad banner', Icons.ad_units_outlined, 'A promotion: offer, launch or app download, with a button.', [ElementKind.ad, ElementKind.button], 1),
  cta('Call to action', Icons.ads_click, 'A heading, a line and buttons.', [ElementKind.button], 1),
  text('Text', Icons.notes, 'A heading and paragraphs.', [ElementKind.card], 1),
  stats('Numbers', Icons.insights, 'Key figures in a row.', [ElementKind.stat], 4),
  faq('FAQ', Icons.quiz_outlined, 'Questions and answers.', [ElementKind.faq], 1),
  testimonials('Quotes', Icons.format_quote, 'What customers say.', [ElementKind.quote], 3),
  newsletter('Newsletter', Icons.mark_email_unread_outlined, 'Sign-up box with a line about what people get.', [ElementKind.button], 1),
  appPromo('App promo', Icons.phone_iphone, 'Get the PIAX app: what it does, store buttons.', [ElementKind.button, ElementKind.tag], 1),
  links('Link list', Icons.list_alt, 'Links in columns (footer, help, policies).', [ElementKind.link], 3),

  /// One of the website's own designed sections (hero, FAQ…): moved and hidden here, its content edited in the site.
  builtin('Website section', Icons.web_asset, 'A section designed in the website itself.', [], 1);

  const SectionKind(this.label, this.icon, this.description, this.elements, this.columns);
  final String label, description;
  final IconData icon;

  /// The kinds of element it holds (the first is what "Add" adds).
  final List<ElementKind> elements;
  final int columns;
}

String newLayoutId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(46656).toRadixString(36)}';

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) => values.where((v) => v.name == name).firstOrNull ?? fallback;

class SiteElement {
  SiteElement({String? id, required this.kind, this.title = '', this.text = '', List<String>? tags, this.link = '', this.visible = true, this.tone = Tone.white, this.align = Align3.left})
    : id = id ?? newLayoutId(),
      tags = tags ?? [];
  final String id;
  ElementKind kind;
  String title, text, link;
  List<String> tags;
  bool visible;
  Tone tone;
  Align3 align;

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'title': title, 'text': text, 'tags': tags, 'link': link, 'visible': visible, 'tone': tone.name, 'align': align.name};

  factory SiteElement.fromJson(Map<String, dynamic> j) => SiteElement(
    id: '${j['id']}',
    kind: _enum(ElementKind.values, j['kind'], ElementKind.card),
    title: '${j['title'] ?? ''}',
    text: '${j['text'] ?? ''}',
    tags: [for (final t in (j['tags'] as List?) ?? const []) '$t'],
    link: '${j['link'] ?? ''}',
    visible: j['visible'] != false,
    tone: _enum(Tone.values, j['tone'], Tone.white),
    align: _enum(Align3.values, j['align'], Align3.left),
  );

  SiteElement copy() => SiteElement.fromJson(toJson()..['id'] = newLayoutId());
}

class SiteSection {
  SiteSection({String? id, required this.kind, this.title = '', this.subtitle = '', this.visible = true, this.align = Align3.left, this.tone = Tone.white, int? columns, List<SiteElement>? elements, this.ref})
    : id = id ?? newLayoutId(),
      columns = columns ?? kind.columns,
      elements = elements ?? [];
  final String id;
  SectionKind kind;
  String title, subtitle;
  bool visible;
  Align3 align;
  Tone tone;
  int columns;
  List<SiteElement> elements;

  /// For a [SectionKind.builtin] section: the website's id for it ("hero", "faq"…).
  final String? ref;

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind.name, 'title': title, 'subtitle': subtitle, 'visible': visible, 'align': align.name, 'tone': tone.name, 'columns': columns, 'ref': ?ref,
    'elements': [for (final e in elements) e.toJson()],
  };

  factory SiteSection.fromJson(Map<String, dynamic> j) => SiteSection(
    id: '${j['id']}',
    kind: _enum(SectionKind.values, j['kind'], SectionKind.text),
    title: '${j['title'] ?? ''}',
    subtitle: '${j['subtitle'] ?? ''}',
    visible: j['visible'] != false,
    align: _enum(Align3.values, j['align'], Align3.left),
    tone: _enum(Tone.values, j['tone'], Tone.white),
    columns: (j['columns'] as num?)?.toInt(),
    elements: [for (final e in (j['elements'] as List?) ?? const []) SiteElement.fromJson(e as Map<String, dynamic>)],
    ref: j['ref'] as String?,
  );

  SiteSection copy() => SiteSection.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>)
    ..elements = [for (final e in elements) e.copy()];
}

class SitePage {
  SitePage({String? id, required this.name, required this.path, this.visible = true, List<SiteSection>? sections}) : id = id ?? newLayoutId(), sections = sections ?? [];
  final String id;
  String name, path;
  bool visible;
  List<SiteSection> sections;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path, 'visible': visible, 'sections': [for (final s in sections) s.toJson()]};

  factory SitePage.fromJson(Map<String, dynamic> j) => SitePage(
    id: '${j['id']}',
    name: '${j['name'] ?? 'Page'}',
    path: '${j['path'] ?? '/'}',
    visible: j['visible'] != false,
    sections: [for (final s in (j['sections'] as List?) ?? const []) SiteSection.fromJson(s as Map<String, dynamic>)],
  );
}

class SiteLayout {
  SiteLayout(this.pages);
  final Map<Surface, List<SitePage>> pages;

  Map<String, dynamic> toJson() => {for (final e in pages.entries) e.key.name: [for (final p in e.value) p.toJson()]};

  factory SiteLayout.fromJson(Map<String, dynamic> j) => SiteLayout({
    for (final s in Surface.values) s: [for (final p in (j[s.name] as List?) ?? const []) SitePage.fromJson(p as Map<String, dynamic>)],
  });
}

/// A new section of [kind] with a few starter elements, ready to edit.
SiteSection starterSection(SectionKind kind) {
  SiteElement e(String title, [String text = '']) => SiteElement(kind: kind.elements.first, title: title, text: text);
  return SiteSection(
    kind: kind,
    title: switch (kind) {
      SectionKind.hero => 'A new headline',
      SectionKind.announcement => '',
      SectionKind.banner => 'A new offer',
      SectionKind.newsletter => 'Stay in the loop',
      SectionKind.appPromo => 'Get the PIAX app',
      _ => 'New ${kind.label.toLowerCase()}',
    },
    subtitle: kind == SectionKind.hero ? 'A line that says what this page is about.' : '',
    align: kind == SectionKind.hero || kind == SectionKind.cta || kind == SectionKind.newsletter ? Align3.center : Align3.left,
    tone: kind == SectionKind.banner ? Tone.mint : Tone.white,
    elements: switch (kind) {
      SectionKind.hero || SectionKind.cta || SectionKind.newsletter || SectionKind.appPromo => [e('Main button', '/')],
      SectionKind.announcement => [SiteElement(kind: ElementKind.link, title: 'A short message', link: '/')],
      SectionKind.banner => [SiteElement(kind: ElementKind.ad, title: 'Offer headline', text: 'One line about the offer.', link: '/shop', tone: Tone.mint)],
      SectionKind.tagRow => [e('First tag'), e('Second tag'), e('Third tag')],
      SectionKind.faq => [e('A question people ask', 'A short, plain answer.')],
      SectionKind.stats => [e('4', 'pad sizes'), e('1', 'cycle app')],
      SectionKind.text => [e('', 'Write the paragraph here.')],
      _ => [e('First card', 'A line about it.'), e('Second card', 'A line about it.'), e('Third card', 'A line about it.')],
    },
  );
}

// ---------------------------------------------------------------- the demo copy

const _claims = ['Winged design', 'Breathable backsheet', 'SAP core', 'Anion-infused design', 'Soft top sheet', 'Leak-management design'];

SiteLayout demoLayout() {
  SiteElement card(String t, String x, {List<String> tags = const [], String link = '', Tone tone = Tone.white, ElementKind kind = ElementKind.card}) =>
      SiteElement(kind: kind, title: t, text: x, tags: [...tags], link: link, tone: tone);
  SiteElement button(String t, String link) => SiteElement(kind: ElementKind.button, title: t, link: link);
  SiteElement tag(String t) => SiteElement(kind: ElementKind.tag, title: t);
  SiteElement q(String t, String a) => SiteElement(kind: ElementKind.faq, title: t, text: a);
  final products = [
    card('PIAX VERA', 'Lite · 240mm · light flow, day use', tags: [_claims[0], _claims[1]], link: '/shop/piax-vera', tone: Tone.sage, kind: ElementKind.product),
    card('PIAX LUMA', 'Everyday · 290mm · regular flow, day use', tags: [_claims[2], _claims[4]], link: '/shop/piax-luma', tone: Tone.lavender, kind: ElementKind.product),
    card('PIAX NOCTE', 'Night · 330mm · heavy flow, overnight', tags: [_claims[5], _claims[0]], link: '/shop/piax-nocte', tone: Tone.navy, kind: ElementKind.product),
    card('PIAX 360mm', 'Extra heavy · overnight', tags: [_claims[2], _claims[1]], link: '/shop/piax-360', tone: Tone.peach, kind: ElementKind.product),
  ];
  return SiteLayout({
    Surface.website: [
      SitePage(name: 'Home', path: '/', sections: [
        SiteSection(kind: SectionKind.announcement, tone: Tone.brand, align: Align3.center, elements: [SiteElement(kind: ElementKind.link, title: 'Build your own cycle box: 12 to 15 pads, your mix', link: '/build-your-box')]),
        SiteSection(kind: SectionKind.hero, title: 'Feel different. Feel you.', subtitle: 'Better periods. Brighter futures. Lab-tested pads, a cycle companion app and honest education.', align: Align3.center, tone: Tone.mint,
            elements: [button('Shop the range', '/shop'), button('Get the app', '/app')]),
        SiteSection(kind: SectionKind.tagRow, title: 'What do you need today?', align: Align3.center, elements: [tag('Light flow'), tag('Everyday'), tag('Overnight'), tag('Extra heavy'), tag('Cycle Pack')]),
        SiteSection(kind: SectionKind.productGrid, title: 'The PIAX range', subtitle: 'Four sizes for every day of your cycle.', elements: [for (final p in products) SiteElement.fromJson(p.toJson()..['id'] = newLayoutId())]),
        SiteSection(kind: SectionKind.featureList, title: 'What’s inside every pad', tone: Tone.mist, elements: [
          card('Soft top sheet', 'Gentle on skin, day and night.'),
          card('SAP layer', 'A superabsorbent polymer core.'),
          card('Anion-infused design', 'An anion strip in every pad.'),
          card('Breathable backsheet', 'Lets air through.'),
        ]),
        SiteSection(kind: SectionKind.banner, title: 'Build your own box', tone: Tone.lavender, elements: [SiteElement(kind: ElementKind.ad, title: 'Your cycle, your mix', text: 'Pick 12 to 15 pads across sizes. Delivered to your door.', link: '/build-your-box', tone: Tone.lavender)]),
        SiteSection(kind: SectionKind.appPromo, title: 'Track your cycle with the PIAX app', subtitle: 'Predictions, reminders and private notes. Your data stays yours.', tone: Tone.sage, elements: [button('App Store', '#'), button('Google Play', '#')]),
        SiteSection(kind: SectionKind.cardGrid, title: 'PIAX Learn', subtitle: 'Clear, non-clinical guides.', elements: [
          card('Your cycle, phase by phase', 'What happens across a typical cycle.', tags: ['Cycle'], link: '/learn/cycle'),
          card('Puberty: first periods', 'For first periods and the people helping.', tags: ['Puberty'], link: '/learn/puberty'),
          card('Choosing the right pad', 'Size, flow and day or night.', tags: ['Products'], link: '/learn/choosing-pads'),
        ]),
        SiteSection(kind: SectionKind.faq, title: 'Questions', elements: [
          q('Which size should I pick?', 'VERA for light days, LUMA for everyday, NOCTE for nights and 360mm for extra heavy flow.'),
          q('Is my cycle data private?', 'Yes. Cycle data logged on the web stays on your device unless you choose to sync it.'),
          q('Can I mix sizes?', 'Yes: the Cycle Pack and Build your own box let you choose.'),
        ]),
        SiteSection(kind: SectionKind.newsletter, title: 'Stay in the loop', subtitle: 'New guides and offers, now and then. Unsubscribe anytime.', align: Align3.center, tone: Tone.mist, elements: [button('Subscribe', '#')]),
      ]),
      SitePage(name: 'Shop', path: '/shop', sections: [
        SiteSection(kind: SectionKind.hero, title: 'Shop PIAX', subtitle: 'Lab-tested pads in four sizes.', tone: Tone.mint, elements: [button('Build your own box', '/build-your-box')]),
        SiteSection(kind: SectionKind.tagRow, title: 'Filter', elements: [tag('Day'), tag('Night'), tag('Packs')]),
        SiteSection(kind: SectionKind.productGrid, title: 'All products', elements: [for (final p in products) SiteElement.fromJson(p.toJson()..['id'] = newLayoutId())]),
        SiteSection(kind: SectionKind.banner, title: 'Offer', tone: Tone.peach, elements: [SiteElement(kind: ElementKind.ad, title: 'Cycle Pack', text: 'A month of pads across sizes in one box.', link: '/shop/cycle-pack', tone: Tone.peach)]),
      ]),
      SitePage(name: 'About', path: '/about', sections: [
        SiteSection(kind: SectionKind.hero, title: 'About PIAX', subtitle: 'Next-generation menstrual wellness from Ranipet, Tamil Nadu.', tone: Tone.sage),
        SiteSection(kind: SectionKind.text, title: 'Our story', elements: [card('', 'PIAX LIFE PRIVATE LIMITED makes transparent, lab-tested sanitary pads and the PIAX cycle companion app, with clear education for everyone.')]),
        SiteSection(kind: SectionKind.cardGrid, title: 'Leadership', columns: 2, elements: [card('Kamal Raj Poovannan', 'Founder'), card('Salaudin Ahmed Khan B', 'CEO')]),
      ]),
      SitePage(name: 'Learn', path: '/learn', sections: [
        SiteSection(kind: SectionKind.hero, title: 'PIAX Learn', subtitle: 'General education only, not medical advice.', tone: Tone.lavender),
        SiteSection(kind: SectionKind.cardGrid, title: 'Topics', elements: [card('Cycle', 'Phases, timing, tracking.'), card('Puberty', 'First periods.'), card('Health', 'When to see a professional.')]),
        SiteSection(kind: SectionKind.text, title: 'Medical note', tone: Tone.mist, elements: [card('', 'General education only, not medical advice. For diagnosis or treatment, consult a qualified healthcare professional.')]),
      ]),
      SitePage(name: 'Careers', path: '/careers', sections: [
        SiteSection(kind: SectionKind.hero, title: 'Work with PIAX', subtitle: 'Help build better periods.', tone: Tone.mint, elements: [button('See open roles', '/careers#roles')]),
        SiteSection(kind: SectionKind.featureList, title: 'Why join', elements: [card('Real impact', 'Products people use every month.'), card('Small team', 'Ownership from day one.'), card('Learning', 'Across product, ops and tech.')]),
      ]),
    ],
    Surface.app: [
      SitePage(name: 'Home', path: 'app://home', sections: [
        SiteSection(kind: SectionKind.hero, title: 'Hello', subtitle: 'Your cycle at a glance.', tone: Tone.mint, elements: [button('Log today', 'app://log')]),
        SiteSection(kind: SectionKind.stats, title: 'This cycle', elements: [card('Day 12', 'of your cycle', kind: ElementKind.stat), card('16', 'days to next period', kind: ElementKind.stat)]),
        SiteSection(kind: SectionKind.cardGrid, title: 'For you', columns: 2, elements: [card('Tip of the day', 'Change pads every 4 to 6 hours.'), card('From PIAX Learn', 'Your cycle, phase by phase.', link: '/learn/cycle')]),
        SiteSection(kind: SectionKind.banner, title: 'Shop strip', tone: Tone.lavender, elements: [SiteElement(kind: ElementKind.ad, title: 'Running low?', text: 'Reorder your usual box.', link: 'app://shop', tone: Tone.lavender)]),
      ]),
      SitePage(name: 'Tracker', path: 'app://tracker', sections: [
        SiteSection(kind: SectionKind.hero, title: 'Cycle tracker', subtitle: 'Predictions and history.', tone: Tone.sage),
        SiteSection(kind: SectionKind.tagRow, title: 'Log', elements: [tag('Flow'), tag('Mood'), tag('Symptoms'), tag('Notes')]),
      ]),
      SitePage(name: 'Shop', path: 'app://shop', sections: [
        SiteSection(kind: SectionKind.productGrid, title: 'Shop', columns: 2, elements: [for (final p in products) SiteElement.fromJson(p.toJson()..['id'] = newLayoutId())]),
      ]),
      SitePage(name: 'Learn', path: 'app://learn', sections: [
        SiteSection(kind: SectionKind.cardGrid, title: 'Learn', columns: 1, elements: [card('Cycle', 'Phases, timing, tracking.'), card('Puberty', 'First periods.')]),
      ]),
      SitePage(name: 'Profile', path: 'app://profile', sections: [
        SiteSection(kind: SectionKind.links, title: 'Account', columns: 1, elements: [
          SiteElement(kind: ElementKind.link, title: 'Orders', link: 'app://orders'),
          SiteElement(kind: ElementKind.link, title: 'Privacy & data', link: 'app://privacy'),
          SiteElement(kind: ElementKind.link, title: 'Help', link: 'app://help'),
        ]),
      ]),
    ],
  });
}

// ---------------------------------------------------------------- the local website

enum SiteLink { off, connecting, live, failed }

/// The website's home page in the shape the local website's /api/dev/site-layout takes (lib/siteLayout.ts there).
List<Map<String, dynamic>> homeForWebsite(SitePage home) => [
  for (final s in home.sections)
    if (s.kind == SectionKind.builtin)
      {'id': s.ref ?? s.id, 'builtin': true, 'visible': s.visible}
    else
      {
        'id': s.id, 'kind': s.kind.name, 'title': s.title, 'subtitle': s.subtitle, 'align': s.align.name, 'tone': s.tone.name, 'columns': s.columns, 'visible': s.visible,
        'elements': [for (final e in s.elements) e.toJson()],
      },
];

/// The local website's home layout as builder sections.
List<SiteSection> homeFromWebsite(List<dynamic> home) => [
  for (final raw in home.whereType<Map<String, dynamic>>())
    if (raw['builtin'] == true)
      SiteSection(id: 'site-${raw['id']}', kind: SectionKind.builtin, ref: '${raw['id']}', title: '${raw['label'] ?? raw['id']}', visible: raw['visible'] != false)
    else
      SiteSection.fromJson({...raw, 'kind': raw['kind'] ?? 'text'}),
];

// ---------------------------------------------------------------- the store

/// The layout being edited, with undo and redo, saved on this device after every change.
class LayoutStore extends ChangeNotifier {
  LayoutStore._();
  static final instance = LayoutStore._();

  static const _prefsKey = 'site_layout_demo';
  SiteLayout layout = demoLayout();
  final _undo = <String>[], _redo = <String>[];
  bool _loaded = false;

  /// Changes with the same key in quick succession (typing in a box) are one undo step.
  String? _lastKey;
  DateTime _lastAt = DateTime(2000);

  /// Bumped by undo, redo and reset, so open forms reload their values.
  int revision = 0;

  /// The local website (`next dev` on this machine) the website's Home page is sent to as it's edited.
  String siteUrl = 'http://localhost:3000';
  SiteLink link = SiteLink.off;
  String? linkProblem;
  Timer? _push;

  /// Connects to the local website: its home page replaces the demo Home, and every change after is sent to it.
  /// Without a local website (or in a release build) the builder stays on the demo copy.
  Future<void> connect([String? url]) async {
    if (url != null) siteUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    link = SiteLink.connecting;
    linkProblem = null;
    notifyListeners();
    try {
      final res = await http.get(Uri.parse('$siteUrl/api/dev/site-layout')).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) throw Exception(res.statusCode == 404 ? 'The website isn’t running in development (next dev) here.' : 'The website answered ${res.statusCode}.');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final home = homeFromWebsite(data['home'] as List? ?? const []);
      final pages = this.pages(Surface.website);
      final page = pages.where((p) => p.path == '/').firstOrNull;
      if (page == null) {
        pages.insert(0, SitePage(name: 'Home', path: '/', sections: home));
      } else {
        page.sections = home;
      }
      link = SiteLink.live;
      revision++;
      try {
        (await SharedPreferences.getInstance()).setString('site_builder_url', siteUrl);
      } catch (_) {}
      await _save();
    } catch (e) {
      link = SiteLink.failed;
      linkProblem = e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Couldn’t reach $siteUrl.';
      if (linkProblem!.contains('Failed host lookup') || linkProblem!.contains('Connection') || linkProblem!.contains('XMLHttpRequest') || linkProblem!.contains('TimeoutException')) {
        linkProblem = 'Couldn’t reach $siteUrl. Is the website running (npm run dev)?';
      }
      notifyListeners();
    }
  }

  void disconnect() {
    link = SiteLink.off;
    _push?.cancel();
    notifyListeners();
  }

  /// Sends the website's Home page to the local website, a moment after the last change.
  void _schedulePush() {
    if (link != SiteLink.live) return;
    _push?.cancel();
    _push = Timer(const Duration(milliseconds: 250), () async {
      final home = pages(Surface.website).where((p) => p.path == '/').firstOrNull;
      if (home == null) return;
      try {
        final res = await http
            .put(Uri.parse('$siteUrl/api/dev/site-layout'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'home': homeForWebsite(home)}))
            .timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) throw Exception('The website answered ${res.statusCode}.');
      } catch (e) {
        link = SiteLink.failed;
        linkProblem = 'Lost the local website: changes are kept here. Reconnect to send them.';
        notifyListeners();
      }
    });
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) layout = SiteLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      siteUrl = prefs.getString('site_builder_url') ?? siteUrl;
      notifyListeners();
    } catch (_) {
      // Unreadable: the demo copy.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    _schedulePush();
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(layout.toJson()));
    } catch (_) {
      // Not saved on this device; the change holds until the app closes.
    }
  }

  String get _snapshot => jsonEncode(layout.toJson());

  /// Applies [change] as one undoable step (merged with the last one when [key] repeats within a couple of seconds).
  void edit(void Function(SiteLayout l) change, {String? key}) {
    final now = DateTime.now();
    final merge = key != null && key == _lastKey && now.difference(_lastAt) < const Duration(seconds: 2);
    if (!merge) {
      _undo.add(_snapshot);
      if (_undo.length > 60) _undo.removeAt(0);
    }
    _redo.clear();
    _lastKey = key;
    _lastAt = now;
    change(layout);
    _save();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_snapshot);
    layout = SiteLayout.fromJson(jsonDecode(_undo.removeLast()) as Map<String, dynamic>);
    _lastKey = null;
    revision++;
    _save();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_snapshot);
    layout = SiteLayout.fromJson(jsonDecode(_redo.removeLast()) as Map<String, dynamic>);
    _lastKey = null;
    revision++;
    _save();
  }

  /// Back to the demo copy (undoable). Connected, the local website's home goes back to its built-in layout too.
  Future<void> reset() async {
    edit((_) {});
    final wasLive = link == SiteLink.live;
    link = SiteLink.off;
    layout = demoLayout();
    revision++;
    await _save();
    if (wasLive) {
      try {
        await http.delete(Uri.parse('$siteUrl/api/dev/site-layout')).timeout(const Duration(seconds: 4));
      } catch (_) {}
      await connect();
    }
  }

  // Lookups.
  List<SitePage> pages(Surface s) => layout.pages[s] ?? (layout.pages[s] = []);
  SitePage? page(Surface s, String? id) => pages(s).where((p) => p.id == id).firstOrNull;
  (SitePage, SiteSection)? section(Surface s, String? id) {
    for (final p in pages(s)) {
      for (final x in p.sections) {
        if (x.id == id) return (p, x);
      }
    }
    return null;
  }

  (SiteSection, SiteElement)? element(Surface s, String? id) {
    for (final p in pages(s)) {
      for (final x in p.sections) {
        for (final e in x.elements) {
          if (e.id == id) return (x, e);
        }
      }
    }
    return null;
  }

  /// Moves element [id] into [to] before element [before] (at the end when null): within a section or across.
  void moveElement(Surface s, String id, SiteSection to, {String? before}) => edit((_) {
    final found = element(s, id);
    if (found == null || found.$2.id == before) return;
    final (from, e) = found;
    from.elements.remove(e);
    final i = before == null ? -1 : to.elements.indexWhere((x) => x.id == before);
    i < 0 ? to.elements.add(e) : to.elements.insert(i, e);
  });
}
