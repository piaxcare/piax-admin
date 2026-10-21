import 'package:flutter/material.dart';

/// The Admin modules mock-up: the modules of the PIAX backend admin panel (api.piax.co.in/admin), described as data so
/// one set of screens (list, details, form) shows them all. Records are dummy data (assets/mock/admin_modules.json,
/// made by the website's scripts/generate-admin-mock.mjs).
///
/// Each field says what it's for ([FieldDef.help]) and which part of the form it belongs to ([FieldDef.section]), so
/// an "Add" form collects everything the live website and app need (for a product: description, features, pricing
/// and tax, stock, photos, shipping, search listing…) and explains each box in plain words.

enum FieldType { text, longText, integer, decimal, money, boolean, dateTime, choice, email, phone, url, image, list }

class FieldDef {
  const FieldDef(
    this.key,
    this.label,
    this.type, {
    this.options = const [],
    this.required = false,
    this.readOnly = false,
    this.help,
    this.section = 'Details',
    this.hint,
    this.maxLength,
    this.pattern,
    this.patternMessage,
  });
  final String key;
  final String label;
  final FieldType type;

  /// The choices of a [FieldType.choice] field.
  final List<String> options;
  final bool required;

  /// Shown, but not editable in the form (counts, timestamps the system keeps).
  final bool readOnly;

  /// What the field is for, where it shows and any rules, under the box in the form and on the details page.
  final String? help;

  /// The form card it sits in ("Basics", "Pricing & tax", "Search listing"…).
  final String section;

  /// Example text inside the empty box.
  final String? hint;

  /// Most characters allowed (search titles and descriptions get cut off past a length).
  final int? maxLength;

  /// A pattern the value must match (a web address slug, a pincode…), and what to say when it doesn't.
  final String? pattern;
  final String? patternMessage;

  /// Takes the full width of a two-column form.
  bool get wide => type == FieldType.longText || type == FieldType.list || type == FieldType.image || type == FieldType.boolean;
}

/// A one-tap action on a record: sets [field] (the status, by default) to [to]. Offered only while the record's
/// status is one of [from] (any status when empty).
class ActionDef {
  const ActionDef(this.label, this.icon, this.to, {this.from = const [], this.field, this.danger = false});
  final String label;
  final IconData icon;
  final String to;
  final List<String> from;
  final String? field;
  final bool danger;

  bool appliesTo(Map<String, dynamic> record, String? statusField) {
    final key = field ?? statusField;
    if (key == null) return false;
    final current = '${record[key] ?? ''}';
    return current != to && (from.isEmpty || from.contains(current));
  }
}

class ModuleDef {
  const ModuleDef({
    required this.key,
    required this.title,
    required this.singular,
    required this.group,
    required this.icon,
    required this.description,
    required this.fields,
    required this.titleField,
    this.subtitleFields = const [],
    this.statusField,
    this.actions = const [],
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.sensitive = false,
    this.formIntro,
  });
  final String key;
  final String title;
  final String singular;
  final String group;
  final IconData icon;
  final String description;
  final List<FieldDef> fields;
  final String titleField;
  final List<String> subtitleFields;
  final String? statusField;
  final List<ActionDef> actions;
  final bool canCreate, canEdit, canDelete;

  /// Health data: shown anonymised and read-only.
  final bool sensitive;

  /// A line at the top of the add / edit form: what the record is used for and what happens when it's saved.
  final String? formIntro;

  FieldDef? field(String key) => fields.where((f) => f.key == key).firstOrNull;
  List<String> get statuses => field(statusField ?? '')?.options ?? const [];
  bool get readOnly => !canCreate && !canEdit && !canDelete;

  /// The form's sections, in the order their first field appears.
  List<String> get sections => [for (final f in fields) f.section].fold<List<String>>([], (list, s) => list.contains(s) ? list : [...list, s]);
}

/// The module groups, in the order the backend admin lists them.
const moduleGroups = ['Website', 'Content', 'Care', 'Deliveries', 'Orders & members', 'Chat', 'Health data (sensitive)', 'System'];

const _publish = [
  ActionDef('Publish', Icons.public, 'Published', from: ['Draft']),
  ActionDef('Unpublish', Icons.visibility_off_outlined, 'Draft', from: ['Published']),
];

const _slug = r'^[a-z0-9]+(-[a-z0-9]+)*$';
const _slugMessage = 'Use small letters, numbers and dashes only, like piax-luma-12.';
const _pincode = r'^\d{6}$';

/// Claims the PIAX lab policy allows on products, and the ones it never allows.
const _claimsHelp =
    'One feature per line, shown as bullet points on the product page. Use only validated claims: breathable backsheet, '
    'superabsorbent polymer core (SAP layer), soft top sheet, anion-infused design, winged design, leak-management design. '
    'Never write “organic”, “rash-free”, “100% leak-proof”, “toxin-free”, “ultra-thin” or millilitre absorption numbers.';

const _seoTitleHelp = 'The blue headline in Google results and the browser tab. Up to 60 characters; end with “| PIAX”.';
const _seoDescHelp = 'The grey text under the headline in Google. One or two plain sentences, up to 160 characters.';
const _imageHelp = 'Paste an image link (https://…) or a path on the website, like /images/products/piax-luma-12.webp. WebP, at least 1200 px wide.';

const modules = <ModuleDef>[
  // ---------------------------------------------------------------- Website
  ModuleDef(
    key: 'pages', title: 'Website pages', singular: 'Page', group: 'Website', icon: Icons.web_outlined,
    description: 'Every page of piax.co.in: whether it’s live, its main button, and how it shows in Google and when shared.',
    formIntro: 'A page on piax.co.in. What you fill in here sets its main button and how it looks in Google and in shared links.',
    titleField: 'title', subtitleFields: ['path', 'ctaLabel', 'views30d'], statusField: 'status',
    fields: [
      FieldDef('title', 'Page name', FieldType.text, required: true, section: 'Page', help: 'The name in the menu and the admin. Short: “Shop”, “Cycle Pack”.'),
      FieldDef('path', 'Address', FieldType.text, required: true, section: 'Page', hint: '/cycle-pack', pattern: r'^/[a-z0-9\-/#]*$', patternMessage: 'Start with / and use small letters, numbers and dashes.', help: 'Where the page lives on piax.co.in, starting with /.'),
      FieldDef('summary', 'What the page is for', FieldType.longText, section: 'Page', help: 'One or two sentences for the team: who the page is for and what it should get them to do.'),
      FieldDef('showInMenu', 'Show in the website menu', FieldType.boolean, section: 'Page', help: 'On: listed in the top menu and the footer. Off: reachable only by its link.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Live', 'Maintenance', 'Hidden'], section: 'Page', help: 'Live: open to everyone. Maintenance: shows an “under maintenance” note. Hidden: not reachable.'),
      FieldDef('ctaLabel', 'Main button text', FieldType.text, section: 'Main button', hint: 'Shop pads', maxLength: 24, help: 'The most important button on the page. A short action: “Shop pads”, “Build your mix”.'),
      FieldDef('ctaTarget', 'Main button opens', FieldType.text, section: 'Main button', hint: '/shop', help: 'The page or link the button opens.'),
      FieldDef('heroImage', 'Top image', FieldType.image, section: 'Main button', help: _imageHelp),
      FieldDef('seoTitle', 'Title in Google', FieldType.text, section: 'Search & sharing', maxLength: 60, help: _seoTitleHelp),
      FieldDef('seoDescription', 'Description in Google', FieldType.longText, section: 'Search & sharing', maxLength: 160, help: _seoDescHelp),
      FieldDef('shareImage', 'Image when shared', FieldType.image, section: 'Search & sharing', help: 'The picture WhatsApp, Instagram and others show with the link. 1200 × 630 px.'),
      FieldDef('views30d', 'Views (last 30 days)', FieldType.integer, readOnly: true, section: 'Activity'),
      FieldDef('editedBy', 'Last edited by', FieldType.text, readOnly: true, section: 'Activity'),
      FieldDef('lastEdited', 'Last edited', FieldType.dateTime, readOnly: true, section: 'Activity'),
    ],
    actions: [
      ActionDef('Show “under maintenance”', Icons.construction_outlined, 'Maintenance', from: ['Live'], danger: true),
      ActionDef('Hide page', Icons.visibility_off_outlined, 'Hidden', from: ['Live'], danger: true),
      ActionDef('Put back live', Icons.public, 'Live', from: ['Maintenance', 'Hidden']),
    ],
  ),
  ModuleDef(
    key: 'products', title: 'Products & pads', singular: 'Product', group: 'Website', icon: Icons.inventory_2_outlined,
    description: 'The pads and packs sold on the website and in the app: details, price, stock, photos and search listing.',
    formIntro: 'Everything the shop needs to sell this product: what customers read, the price and tax, stock, photos, shipping and how it shows in Google. Saved products go live in the shop when their status is Active.',
    titleField: 'name', subtitleFields: ['variant', 'size', 'price'], statusField: 'status',
    fields: [
      FieldDef('name', 'Product name', FieldType.text, required: true, section: 'Basics', hint: 'PIAX LUMA', help: 'The name on the product page, in the cart and on the invoice.'),
      FieldDef('variant', 'Variant', FieldType.text, section: 'Basics', hint: 'Everyday', help: 'What sets it apart in the range: Lite, Everyday, Overnight…'),
      FieldDef('category', 'Category', FieldType.choice, options: ['Day pads', 'Night pads', 'Extra heavy', 'Packs'], required: true, section: 'Basics', help: 'The shop filter it appears under.'),
      FieldDef('tagline', 'Short description', FieldType.text, section: 'Basics', maxLength: 90, hint: 'Everyday comfort for regular flow', help: 'One line under the name on product cards and in search.'),
      FieldDef('description', 'Full description', FieldType.longText, required: true, section: 'Basics', help: 'The main text on the product page: who it’s for, the flow it suits and how it feels. Honest and plain; no medical claims.'),
      FieldDef('features', 'Key features', FieldType.list, section: 'Product details', help: _claimsHelp),
      FieldDef('layers', 'Layers & materials', FieldType.list, section: 'Product details', help: 'Each layer from top to bottom, one per line: soft top sheet, SAP core, anion strip, breathable backsheet.'),
      FieldDef('howToUse', 'How to use', FieldType.longText, section: 'Product details', help: 'Short steps shown in the “How to use” tab: change every 4–6 hours, wrap and dispose in the bin.'),
      FieldDef('size', 'Size', FieldType.text, required: true, section: 'Product details', hint: 'XL · 290mm', help: 'Size letter and length, as printed on the box.'),
      FieldDef('pads', 'Pads per box', FieldType.integer, required: true, section: 'Product details'),
      FieldDef('colour', 'Pack colour', FieldType.text, section: 'Product details', help: 'The brand colour of the box, used on the product card: Soft Sage Green, Muted Lavender…'),
      FieldDef('price', 'Selling price', FieldType.money, required: true, section: 'Pricing & tax', help: 'What the customer pays, including GST.'),
      FieldDef('mrp', 'MRP', FieldType.money, required: true, section: 'Pricing & tax', help: 'Maximum retail price printed on the box. Shown struck through when higher than the selling price.'),
      FieldDef('gstRate', 'GST rate', FieldType.choice, options: ['0%', '5%', '12%', '18%'], section: 'Pricing & tax', help: 'The GST slab on the invoice. Sanitary pads are 0% at present; check with accounts before changing.'),
      FieldDef('hsnCode', 'HSN code', FieldType.text, section: 'Pricing & tax', hint: '96190010', pattern: r'^\d{4,8}$', patternMessage: 'HSN codes are 4 to 8 digits.', help: 'The tax code printed on invoices.'),
      FieldDef('sku', 'SKU', FieldType.text, required: true, section: 'Stock', hint: 'PX-LUMA-12', help: 'The stock code on the box and in the warehouse. Unique per product.'),
      FieldDef('stock', 'Boxes in stock', FieldType.integer, required: true, section: 'Stock', help: 'Boxes ready to ship. At 0 the shop shows “Out of stock”.'),
      FieldDef('lowStockAt', 'Low-stock alert at', FieldType.integer, section: 'Stock', hint: '200', help: 'The dashboard flags the product when stock falls below this.'),
      FieldDef('image', 'Main photo', FieldType.image, required: true, section: 'Photos', help: _imageHelp),
      FieldDef('gallery', 'More photos', FieldType.list, section: 'Photos', help: 'One image link per line: the box from other sides, the pad, size compared with others.'),
      FieldDef('weightGrams', 'Shipping weight (g)', FieldType.integer, section: 'Shipping', help: 'The packed box, in grams. Used to work out delivery charges.'),
      FieldDef('dimensions', 'Box size (cm)', FieldType.text, section: 'Shipping', hint: '20 × 12 × 8', help: 'Length × width × height of the packed box.'),
      FieldDef('slug', 'Web address', FieldType.text, required: true, section: 'Search listing', hint: 'piax-luma-12', pattern: _slug, patternMessage: _slugMessage, help: 'The end of the product link: piax.co.in/shop/<this>. Don’t change it once live: old links would break.'),
      FieldDef('seoTitle', 'Title in Google', FieldType.text, section: 'Search listing', maxLength: 60, help: _seoTitleHelp),
      FieldDef('seoDescription', 'Description in Google', FieldType.longText, section: 'Search listing', maxLength: 160, help: _seoDescHelp),
      FieldDef('featured', 'Feature on the home page', FieldType.boolean, section: 'Visibility', help: 'On: shown in “What do you need today?” on the home page.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Hidden'], section: 'Visibility', help: 'Active: on sale in the shop and the app. Hidden: kept here but not sold.'),
      FieldDef('updatedAt', 'Last updated', FieldType.dateTime, readOnly: true, section: 'Visibility'),
    ],
    actions: [
      ActionDef('Hide from shop', Icons.visibility_off_outlined, 'Hidden', from: ['Active']),
      ActionDef('Show in shop', Icons.visibility_outlined, 'Active', from: ['Hidden']),
    ],
  ),
  ModuleDef(
    key: 'stores', title: 'Store locations', singular: 'Store', group: 'Website', icon: Icons.storefront_outlined,
    description: 'Partner stores that hold stock for quick delivery, and appear on the store finder.',
    formIntro: 'A partner store: where it is, how to reach it and whether it fulfils quick deliveries. Open stores show on the website’s store finder.',
    titleField: 'name', subtitleFields: ['city', 'pincode', 'hours'], statusField: 'status',
    fields: [
      FieldDef('name', 'Store name', FieldType.text, required: true, section: 'Store'),
      FieldDef('contactPerson', 'Contact person', FieldType.text, section: 'Store', help: 'Who to call about stock and pickups.'),
      FieldDef('phone', 'Phone', FieldType.phone, required: true, section: 'Store'),
      FieldDef('email', 'Email', FieldType.email, section: 'Store'),
      FieldDef('address', 'Address', FieldType.longText, required: true, section: 'Location', help: 'Shop number, street and area, as on the store finder.'),
      FieldDef('city', 'City', FieldType.text, required: true, section: 'Location'),
      FieldDef('pincode', 'Pincode', FieldType.text, required: true, section: 'Location', pattern: _pincode, patternMessage: 'A pincode is 6 digits.'),
      FieldDef('mapsLink', 'Google Maps link', FieldType.url, section: 'Location', help: 'Opens directions from the store finder.'),
      FieldDef('hours', 'Opening hours', FieldType.text, section: 'Delivery', hint: '8 am – 10 pm'),
      FieldDef('radiusKm', 'Delivery radius (km)', FieldType.integer, section: 'Delivery', help: 'How far quick deliveries go from this store.'),
      FieldDef('quickDelivery', 'Quick delivery from this store', FieldType.boolean, section: 'Delivery', help: 'On: riders pick up nearby orders here for delivery within the hour.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Open', 'Closed'], section: 'Delivery'),
    ],
    actions: [
      ActionDef('Close store', Icons.store_mall_directory_outlined, 'Closed', from: ['Open'], danger: true),
      ActionDef('Reopen', Icons.storefront_outlined, 'Open', from: ['Closed']),
    ],
  ),
  ModuleDef(
    key: 'plans', title: 'Subscription plans', singular: 'Plan', group: 'Website', icon: Icons.event_repeat,
    description: 'Monthly, quarterly and yearly pad subscriptions offered on the website and in the app.',
    formIntro: 'A subscription customers can choose. Active plans show on the subscriptions page; changes apply from each member’s next renewal.',
    titleField: 'name', subtitleFields: ['interval', 'price', 'members'], statusField: 'status',
    fields: [
      FieldDef('name', 'Plan name', FieldType.text, required: true, section: 'Plan'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Draft'], section: 'Plan'),
      FieldDef('description', 'Description', FieldType.longText, section: 'Plan', help: 'Who it suits and what arrives, in two sentences.'),
      FieldDef('includes', 'What’s included', FieldType.list, section: 'Plan', help: 'One item per line, shown as ticks on the plan card: “12 PIAX LUMA + 6 NOCTE”, “Free delivery”.'),
      FieldDef('interval', 'Billing', FieldType.choice, options: ['Monthly', 'Every 3 months', 'Yearly'], required: true, section: 'Price'),
      FieldDef('price', 'Price per billing', FieldType.money, required: true, section: 'Price', help: 'Charged each billing period, including GST.'),
      FieldDef('discount', 'Saving shown (%)', FieldType.integer, section: 'Price', help: 'The “Save 10%” badge, against buying the same packs one by one.'),
      FieldDef('trialDays', 'Free trial (days)', FieldType.integer, section: 'Price', help: '0 for no trial.'),
      FieldDef('members', 'Members', FieldType.integer, readOnly: true, section: 'Price'),
    ],
    actions: [
      ActionDef('Activate', Icons.check_circle_outline, 'Active', from: ['Draft']),
      ActionDef('Move to draft', Icons.edit_note, 'Draft', from: ['Active']),
    ],
  ),
  ModuleDef(
    key: 'articles', title: 'Blog articles', singular: 'Article', group: 'Website', icon: Icons.article_outlined,
    description: 'PIAX Learn guides on the website: the text, cover, author, review and search listing.',
    formIntro: 'A PIAX Learn guide. Write for a curious reader, in plain words; general education only, never a diagnosis. Published articles appear on /learn.',
    titleField: 'title', subtitleFields: ['category', 'views'], statusField: 'status',
    fields: [
      FieldDef('title', 'Title', FieldType.text, required: true, section: 'Article', maxLength: 80),
      FieldDef('category', 'Topic', FieldType.choice, options: ['First period', 'Menstrual cycle', 'Period care', 'Flow & products'], required: true, section: 'Article'),
      FieldDef('excerpt', 'Summary', FieldType.longText, required: true, section: 'Article', maxLength: 200, help: 'Two sentences on the article card and at the top of the page.'),
      FieldDef('body', 'Article text', FieldType.longText, required: true, section: 'Article', help: 'The full article. Short paragraphs and headings. The medical disclaimer is added at the end automatically.'),
      FieldDef('tags', 'Tags', FieldType.list, section: 'Article', help: 'One per line: cramps, first period, sleep… Used for “Related reads”.'),
      FieldDef('coverImage', 'Cover image', FieldType.image, section: 'Article', help: _imageHelp),
      FieldDef('status', 'Status', FieldType.choice, options: ['Published', 'Draft'], section: 'Article', help: 'Draft: only admins see it. Published: live on /learn.'),
      FieldDef('author', 'Author', FieldType.text, section: 'People', hint: 'PIAX Learn team'),
      FieldDef('reviewedBy', 'Reviewed by', FieldType.text, section: 'People', help: 'The doctor or expert who checked the facts, shown as “Reviewed by …”. Leave empty if not reviewed.'),
      FieldDef('readMinutes', 'Reading time (minutes)', FieldType.integer, section: 'People'),
      FieldDef('slug', 'Web address', FieldType.text, required: true, section: 'Search listing', hint: 'first-period-what-to-expect', pattern: _slug, patternMessage: _slugMessage, help: 'piax.co.in/learn/<this>. Don’t change it once published.'),
      FieldDef('publishedAt', 'Published', FieldType.dateTime, section: 'Search listing'),
      FieldDef('seoTitle', 'Title in Google', FieldType.text, section: 'Search listing', maxLength: 60, help: _seoTitleHelp),
      FieldDef('seoDescription', 'Description in Google', FieldType.longText, section: 'Search listing', maxLength: 160, help: _seoDescHelp),
      FieldDef('views', 'Views', FieldType.integer, readOnly: true, section: 'Search listing'),
    ],
    actions: _publish,
  ),
  ModuleDef(
    key: 'myths', title: 'Myth busters', singular: 'Myth buster', group: 'Website', icon: Icons.help_outline,
    description: 'Period myths and the facts, shown on the website and in the app.',
    formIntro: 'A common belief and the evidence-based answer, shown as a flip card on the website and in the app.',
    titleField: 'myth', subtitleFields: ['fact'], statusField: 'status',
    fields: [
      FieldDef('myth', 'Myth', FieldType.longText, required: true, maxLength: 120, help: 'The belief as people say it: “You can’t exercise on your period.”'),
      FieldDef('fact', 'Fact', FieldType.longText, required: true, maxLength: 160, help: 'The short answer on the back of the card.'),
      FieldDef('explanation', 'Explanation', FieldType.longText, help: 'A few sentences for “Read more”: why the myth is wrong, in plain words.'),
      FieldDef('source', 'Source', FieldType.url, help: 'A trusted link backing the fact (WHO, NHS, a medical journal).'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Published', 'Draft']),
    ],
    actions: _publish,
  ),
  ModuleDef(
    key: 'banners', title: 'Website & app banners', singular: 'Banner', group: 'Website', icon: Icons.campaign_outlined,
    description: 'Promotions on the website and the app home screen, with their dates and audience.',
    formIntro: 'A promotion. It goes live by itself at the start time and comes down at the end time.',
    titleField: 'title', subtitleFields: ['placement', 'cta'], statusField: 'status',
    fields: [
      FieldDef('title', 'Headline', FieldType.text, required: true, section: 'Message', maxLength: 50),
      FieldDef('subtitle', 'Supporting line', FieldType.text, section: 'Message', maxLength: 90),
      FieldDef('cta', 'Button text', FieldType.text, section: 'Message', maxLength: 20, hint: 'Shop now'),
      FieldDef('ctaLink', 'Button opens', FieldType.text, section: 'Message', hint: '/cycle-pack', help: 'A page on the website (starting with /) or a full link.'),
      FieldDef('image', 'Banner image', FieldType.image, section: 'Message', help: 'Website hero: 1600 × 600 px. Strip: 1600 × 120 px. App home: 1080 × 540 px.'),
      FieldDef('placement', 'Where', FieldType.choice, options: ['Website hero', 'Website strip', 'App home'], required: true, section: 'Where & when'),
      FieldDef('audience', 'Who sees it', FieldType.choice, options: ['Everyone', 'New visitors', 'Members', 'Subscribers'], section: 'Where & when'),
      FieldDef('priority', 'Priority', FieldType.integer, section: 'Where & when', help: 'When two banners share a spot, the higher number shows first.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Live', 'Scheduled', 'Ended'], section: 'Where & when'),
      FieldDef('startsAt', 'Starts', FieldType.dateTime, section: 'Where & when'),
      FieldDef('endsAt', 'Ends', FieldType.dateTime, section: 'Where & when'),
    ],
    actions: [
      ActionDef('Go live now', Icons.play_circle_outline, 'Live', from: ['Scheduled']),
      ActionDef('End now', Icons.stop_circle_outlined, 'Ended', from: ['Live', 'Scheduled'], danger: true),
    ],
  ),

  // ---------------------------------------------------------------- Content
  ModuleDef(
    key: 'healthBots', title: 'AI health bots', singular: 'Health bot', group: 'Content', icon: Icons.smart_toy_outlined,
    description: 'The PIAX AI specialist assistants: what each helps with and how it greets people.',
    formIntro: 'A PIAX AI assistant. It gives general information only and always points people to a doctor for anything medical.',
    titleField: 'name', subtitleFields: ['specialty', 'chats'], statusField: 'status',
    fields: [
      FieldDef('name', 'Name', FieldType.text, required: true, section: 'Assistant'),
      FieldDef('specialty', 'Helps with', FieldType.text, required: true, section: 'Assistant', hint: 'Cramps and comfort'),
      FieldDef('description', 'Description', FieldType.longText, section: 'Assistant', help: 'Shown on the assistant’s card in the app.'),
      FieldDef('greeting', 'First message', FieldType.longText, section: 'Assistant', help: 'What it says when a chat starts.'),
      FieldDef('topics', 'Suggested questions', FieldType.list, section: 'Assistant', help: 'One per line, shown as tap-to-ask chips.'),
      FieldDef('avatar', 'Avatar', FieldType.image, section: 'Assistant'),
      FieldDef('chats', 'Chats', FieldType.integer, readOnly: true, section: 'Assistant'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Paused'], section: 'Assistant'),
    ],
    actions: [
      ActionDef('Pause', Icons.pause_circle_outline, 'Paused', from: ['Active']),
      ActionDef('Resume', Icons.play_circle_outline, 'Active', from: ['Paused']),
    ],
  ),
  ModuleDef(
    key: 'media', title: 'Media library', singular: 'Image', group: 'Content', icon: Icons.photo_library_outlined,
    description: 'Images used across the website and app, with their alt text.',
    formIntro: 'A file for the website or app. Alt text is read aloud to people using screen readers, so describe what the picture shows.',
    titleField: 'fileName', subtitleFields: ['sizeKb', 'uploadedBy'], canEdit: false,
    fields: [
      FieldDef('fileName', 'File name', FieldType.text, required: true, hint: 'piax-luma-12.webp'),
      FieldDef('type', 'Type', FieldType.choice, options: ['Image', 'Video', 'PDF']),
      FieldDef('url', 'Link', FieldType.image, help: _imageHelp),
      FieldDef('altText', 'Alt text', FieldType.text, maxLength: 125, help: 'What the image shows, in one sentence: “PIAX LUMA box of 12 pads in lavender.”'),
      FieldDef('sizeKb', 'Size (KB)', FieldType.integer, help: 'Keep images under 300 KB so pages load fast on mobile data.'),
      FieldDef('uploadedBy', 'Uploaded by', FieldType.text),
      FieldDef('uploadedAt', 'Uploaded', FieldType.dateTime, readOnly: true),
    ],
  ),

  // ---------------------------------------------------------------- Care
  ModuleDef(
    key: 'doctors', title: 'Doctors', singular: 'Doctor', group: 'Care', icon: Icons.medical_services_outlined,
    description: 'Doctors offering consultations in the app: qualifications, registration, fees and availability.',
    formIntro: 'A doctor members can book. New doctors stay “Pending verification” until their registration number is checked.',
    titleField: 'name', subtitleFields: ['specialty', 'city', 'fee'], statusField: 'status',
    fields: [
      FieldDef('name', 'Name', FieldType.text, required: true, section: 'Profile', hint: 'Dr. Lakshmi Nair'),
      FieldDef('specialty', 'Specialty', FieldType.choice, options: ['Gynaecologist', 'Obstetrician', 'Endocrinologist', 'Dietitian'], required: true, section: 'Profile'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Available', 'On leave', 'Pending verification'], section: 'Profile'),
      FieldDef('bio', 'About', FieldType.longText, section: 'Profile', help: 'Two or three sentences members read before booking.'),
      FieldDef('languages', 'Languages', FieldType.list, section: 'Profile', help: 'One per line: English, Tamil, Hindi…'),
      FieldDef('photo', 'Photo', FieldType.image, section: 'Profile'),
      FieldDef('qualification', 'Qualification', FieldType.text, required: true, section: 'Credentials', hint: 'MBBS, MS (OBG)'),
      FieldDef('registrationNo', 'Medical registration no.', FieldType.text, required: true, section: 'Credentials', help: 'State or National Medical Council number. Checked before the doctor goes live.'),
      FieldDef('experienceYears', 'Experience (years)', FieldType.integer, section: 'Credentials'),
      FieldDef('rating', 'Rating', FieldType.decimal, readOnly: true, section: 'Credentials'),
      FieldDef('fee', 'Consultation fee', FieldType.money, required: true, section: 'Consultations'),
      FieldDef('availability', 'Available', FieldType.text, section: 'Consultations', hint: 'Mon–Sat, 10 am – 1 pm'),
      FieldDef('city', 'City', FieldType.text, section: 'Consultations'),
      FieldDef('modes', 'Consultation types', FieldType.list, section: 'Consultations', help: 'One per line: Video call, Clinic visit.'),
      FieldDef('clinicAddress', 'Clinic address', FieldType.longText, section: 'Consultations'),
    ],
    actions: [
      ActionDef('Verify', Icons.verified_outlined, 'Available', from: ['Pending verification']),
      ActionDef('Mark on leave', Icons.beach_access_outlined, 'On leave', from: ['Available']),
      ActionDef('Back from leave', Icons.event_available_outlined, 'Available', from: ['On leave']),
    ],
  ),
  ModuleDef(
    key: 'careTips', title: 'Care tips', singular: 'Care tip', group: 'Care', icon: Icons.lightbulb_outline,
    description: 'Short tips shown in the app for each phase of the cycle.',
    formIntro: 'A short, practical tip shown in the app during one phase of the cycle.',
    titleField: 'title', subtitleFields: ['phase'], statusField: 'status',
    fields: [
      FieldDef('title', 'Tip', FieldType.text, required: true, maxLength: 60),
      FieldDef('phase', 'Cycle phase', FieldType.choice, options: ['Menstrual', 'Follicular', 'Ovulation', 'Luteal'], required: true, help: 'The phase it shows in.'),
      FieldDef('body', 'More detail', FieldType.longText, maxLength: 280, help: 'One or two sentences shown when the tip is tapped.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Published', 'Draft']),
    ],
    actions: _publish,
  ),
  ModuleDef(
    key: 'appointments', title: 'Appointments', singular: 'Appointment', group: 'Care', icon: Icons.event_available_outlined,
    description: 'Consultations booked with doctors.',
    titleField: 'patient', subtitleFields: ['doctor', 'at', 'mode'], statusField: 'status',
    fields: [
      FieldDef('patient', 'Patient', FieldType.text, required: true),
      FieldDef('doctor', 'Doctor', FieldType.text, required: true),
      FieldDef('at', 'When', FieldType.dateTime, help: 'Changing this reschedules the appointment; the member is told by SMS.'),
      FieldDef('mode', 'Type', FieldType.choice, options: ['Video call', 'Clinic visit']),
      FieldDef('fee', 'Fee', FieldType.money),
      FieldDef('status', 'Status', FieldType.choice, options: ['Booked', 'Completed', 'Cancelled', 'No-show']),
    ],
    actions: [
      ActionDef('Mark completed', Icons.task_alt, 'Completed', from: ['Booked']),
      ActionDef('Mark no-show', Icons.person_off_outlined, 'No-show', from: ['Booked']),
      ActionDef('Cancel', Icons.cancel_outlined, 'Cancelled', from: ['Booked'], danger: true),
    ],
  ),

  // ---------------------------------------------------------------- Deliveries
  ModuleDef(
    key: 'partners', title: 'Partner accounts', singular: 'Delivery partner', group: 'Deliveries', icon: Icons.delivery_dining_outlined,
    description: 'Riders who deliver quick orders from partner stores, with their vehicle and KYC.',
    formIntro: 'A delivery rider. They can take orders once KYC is approved.',
    titleField: 'name', subtitleFields: ['area', 'vehicle', 'deliveries'], statusField: 'status',
    fields: [
      FieldDef('name', 'Name', FieldType.text, required: true, section: 'Rider'),
      FieldDef('phone', 'Phone', FieldType.phone, required: true, section: 'Rider', help: 'They sign in to the partner app with this number.'),
      FieldDef('area', 'Area', FieldType.text, required: true, section: 'Rider'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Online', 'Offline', 'Suspended', 'Pending KYC'], section: 'Rider'),
      FieldDef('vehicle', 'Vehicle', FieldType.choice, options: ['Scooter', 'Bike', 'E-bike'], section: 'Vehicle & KYC'),
      FieldDef('vehicleNumber', 'Vehicle number', FieldType.text, section: 'Vehicle & KYC', hint: 'TN 23 AB 1234'),
      FieldDef('licenceNo', 'Driving licence no.', FieldType.text, section: 'Vehicle & KYC', help: 'Checked during KYC.'),
      FieldDef('deliveries', 'Deliveries', FieldType.integer, readOnly: true, section: 'Vehicle & KYC'),
      FieldDef('rating', 'Rating', FieldType.decimal, readOnly: true, section: 'Vehicle & KYC'),
    ],
    actions: [
      ActionDef('Approve KYC', Icons.verified_user_outlined, 'Offline', from: ['Pending KYC']),
      ActionDef('Suspend', Icons.block, 'Suspended', from: ['Online', 'Offline'], danger: true),
      ActionDef('Reinstate', Icons.restart_alt, 'Offline', from: ['Suspended']),
    ],
  ),

  // ---------------------------------------------------------------- Orders & members
  ModuleDef(
    key: 'members', title: 'Members', singular: 'Member', group: 'Orders & members', icon: Icons.people_outline,
    description: 'People with a PIAX account: contact details, how their orders went, what they spend and whether they subscribe.',
    titleField: 'name', subtitleFields: ['email', 'city', 'orders'], statusField: 'status', canDelete: false,
    fields: [
      FieldDef('name', 'Name', FieldType.text, required: true, section: 'Profile'),
      FieldDef('email', 'Email', FieldType.email, section: 'Profile', help: 'Order emails and receipts go here.'),
      FieldDef('phone', 'Phone', FieldType.phone, section: 'Profile', help: 'Used to sign in with a one-time code.'),
      FieldDef('phoneVerified', 'Phone verified', FieldType.boolean, readOnly: true, section: 'Profile', help: 'Verified numbers can sign in; unverified ones can be claimed by their real owner.'),
      FieldDef('address', 'Delivery address', FieldType.longText, section: 'Profile'),
      FieldDef('city', 'City', FieldType.text, section: 'Profile'),
      FieldDef('pincode', 'Pincode', FieldType.text, section: 'Profile', pattern: r'^\d{6}$', patternMessage: 'A pincode is 6 digits.'),
      FieldDef('joinedAt', 'Joined', FieldType.dateTime, readOnly: true, section: 'Profile'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Blocked'], section: 'Profile', help: 'Blocked members can’t sign in or order.'),
      FieldDef('orders', 'Orders placed', FieldType.integer, readOnly: true, section: 'Orders'),
      FieldDef('delivered', 'Delivered', FieldType.integer, readOnly: true, section: 'Orders'),
      FieldDef('inProgress', 'On the way', FieldType.integer, readOnly: true, section: 'Orders'),
      FieldDef('cancelled', 'Cancelled', FieldType.integer, readOnly: true, section: 'Orders'),
      FieldDef('refunded', 'Refunded', FieldType.integer, readOnly: true, section: 'Orders', help: 'Cancelled orders whose money has been sent back.'),
      FieldDef('totalSpent', 'Total spent', FieldType.money, readOnly: true, section: 'Orders', help: 'Delivered orders only.'),
      FieldDef('lastOrderAt', 'Last order', FieldType.dateTime, readOnly: true, section: 'Orders'),
      FieldDef('favouriteProduct', 'Buys most', FieldType.text, readOnly: true, section: 'Orders'),
      FieldDef('paymentMethod', 'Usually pays by', FieldType.text, readOnly: true, section: 'Orders'),
      FieldDef('plan', 'Subscription plan', FieldType.text, readOnly: true, section: 'Subscription & preferences'),
      FieldDef('marketingOptIn', 'Offers by email & WhatsApp', FieldType.boolean, section: 'Subscription & preferences', help: 'Only switch on if the member asked for offers.'),
    ],
    actions: [
      ActionDef('Block', Icons.block, 'Blocked', from: ['Active'], danger: true),
      ActionDef('Unblock', Icons.lock_open_outlined, 'Active', from: ['Blocked']),
    ],
  ),
  ModuleDef(
    key: 'subscriptions', title: 'Member subscriptions', singular: 'Subscription', group: 'Orders & members', icon: Icons.card_membership_outlined,
    description: 'Who is subscribed to which plan, and when it renews.',
    titleField: 'member', subtitleFields: ['plan', 'amount', 'renewsAt'], statusField: 'status',
    fields: [
      FieldDef('member', 'Member', FieldType.text, required: true),
      FieldDef('plan', 'Plan', FieldType.text, required: true),
      FieldDef('startedAt', 'Started', FieldType.dateTime),
      FieldDef('renewsAt', 'Renews', FieldType.dateTime, help: 'The next charge and delivery.'),
      FieldDef('amount', 'Amount', FieldType.money, required: true),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Paused', 'Cancelled']),
    ],
    actions: [
      ActionDef('Pause', Icons.pause_circle_outline, 'Paused', from: ['Active']),
      ActionDef('Resume', Icons.play_circle_outline, 'Active', from: ['Paused']),
      ActionDef('Cancel', Icons.cancel_outlined, 'Cancelled', from: ['Active', 'Paused'], danger: true),
    ],
  ),
  ModuleDef(
    key: 'ratings', title: 'App ratings', singular: 'Rating', group: 'Orders & members', icon: Icons.star_half_outlined,
    description: 'Star ratings and comments from the app.',
    titleField: 'comment', subtitleFields: ['member', 'stars', 'platform'], statusField: 'status', canCreate: false, canEdit: false,
    fields: [
      FieldDef('member', 'Member', FieldType.text),
      FieldDef('stars', 'Stars', FieldType.integer),
      FieldDef('comment', 'Comment', FieldType.longText),
      FieldDef('platform', 'Platform', FieldType.choice, options: ['Android', 'iOS']),
      FieldDef('at', 'Rated', FieldType.dateTime),
      FieldDef('status', 'Status', FieldType.choice, options: ['Visible', 'Hidden']),
    ],
    actions: [
      ActionDef('Hide', Icons.visibility_off_outlined, 'Hidden', from: ['Visible']),
      ActionDef('Show', Icons.visibility_outlined, 'Visible', from: ['Hidden']),
    ],
  ),

  // ---------------------------------------------------------------- Chat
  ModuleDef(
    key: 'conversations', title: 'Conversations', singular: 'Conversation', group: 'Chat', icon: Icons.forum_outlined,
    description: 'Member-to-member chats (contents are private).',
    titleField: 'participants', subtitleFields: ['messages', 'updatedAt'], statusField: 'status', canCreate: false, canEdit: false,
    fields: [
      FieldDef('participants', 'Between', FieldType.text),
      FieldDef('lastMessage', 'Last message', FieldType.text),
      FieldDef('messages', 'Messages', FieldType.integer),
      FieldDef('updatedAt', 'Last active', FieldType.dateTime),
      FieldDef('status', 'Status', FieldType.choice, options: ['Open', 'Closed', 'Reported']),
    ],
    actions: [
      ActionDef('Close', Icons.lock_outline, 'Closed', from: ['Open', 'Reported'], danger: true),
      ActionDef('Reopen', Icons.lock_open_outlined, 'Open', from: ['Closed']),
      ActionDef('Mark reviewed', Icons.fact_check_outlined, 'Open', from: ['Reported']),
    ],
  ),
  ModuleDef(
    key: 'blocks', title: 'Blocks', singular: 'Block', group: 'Chat', icon: Icons.block,
    description: 'Members who blocked someone in chat.',
    titleField: 'blocker', subtitleFields: ['blocked', 'reason'], canCreate: false, canEdit: false,
    fields: [
      FieldDef('blocker', 'Blocked by', FieldType.text),
      FieldDef('blocked', 'Blocked member', FieldType.text),
      FieldDef('reason', 'Reason', FieldType.choice, options: ['Spam', 'Unwanted messages', 'Harassment', 'Other']),
      FieldDef('at', 'When', FieldType.dateTime),
    ],
  ),

  // ---------------------------------------------------------------- Health data
  ModuleDef(
    key: 'cycles', title: 'Cycles', singular: 'Cycle', group: 'Health data (sensitive)', icon: Icons.water_drop_outlined,
    description: 'Anonymised cycle records. Read-only: health data is never edited here.',
    titleField: 'member', subtitleFields: ['cycleLength', 'periodLength'], canCreate: false, canEdit: false, canDelete: false, sensitive: true,
    fields: [
      FieldDef('member', 'Member', FieldType.text),
      FieldDef('cycleLength', 'Cycle length (days)', FieldType.integer),
      FieldDef('periodLength', 'Period length (days)', FieldType.integer),
      FieldDef('lastPeriod', 'Last period', FieldType.dateTime),
      FieldDef('predictedNext', 'Predicted next', FieldType.dateTime),
    ],
  ),

  // ---------------------------------------------------------------- System
  ModuleDef(
    key: 'settings', title: 'App settings', singular: 'Setting', group: 'System', icon: Icons.tune,
    description: 'Values the website and app read at runtime.',
    titleField: 'key', subtitleFields: ['value', 'description'], canCreate: false, canDelete: false,
    fields: [
      FieldDef('key', 'Setting', FieldType.text, readOnly: true),
      FieldDef('value', 'Value', FieldType.text, required: true, help: 'Takes effect on the website and in the app within a minute.'),
      FieldDef('description', 'What it does', FieldType.longText, readOnly: true),
      FieldDef('updatedAt', 'Last changed', FieldType.dateTime, readOnly: true),
    ],
  ),
  ModuleDef(
    key: 'credentials', title: 'Credentials & integrations', singular: 'Credential', group: 'System', icon: Icons.key_outlined,
    description: 'The services PIAX runs on (payments, sign-in, WhatsApp, email, app stores…). Keys are masked: only a hint of the last characters is ever shown.',
    formIntro: 'A service PIAX depends on. Never paste a secret key here: keys live in the server’s environment settings. This records who owns it and when it expires.',
    titleField: 'service', subtitleFields: ['usedBy', 'environment', 'expiresAt'], statusField: 'status',
    fields: [
      FieldDef('service', 'Service', FieldType.text, required: true, section: 'Service', hint: 'Razorpay payments'),
      FieldDef('usedBy', 'Used by', FieldType.choice, options: ['Website', 'App', 'Website + app', 'Backend'], section: 'Service'),
      FieldDef('purpose', 'What it’s for', FieldType.longText, required: true, section: 'Service', help: 'What stops working if this breaks: payments, sign-in, order alerts…'),
      FieldDef('environment', 'Mode', FieldType.choice, options: ['Live', 'Test'], section: 'Service', help: 'Test keys never take real money or send real messages.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Connected', 'Expiring soon', 'Error', 'Disabled'], section: 'Service'),
      FieldDef('dashboardLink', 'Provider dashboard', FieldType.url, section: 'Service', help: 'Where the keys are managed (Razorpay, Google Cloud, Meta…).'),
      FieldDef('envName', 'Server setting name', FieldType.text, section: 'Key', hint: 'RAZORPAY_KEY_SECRET', help: 'The environment variable that holds the key on the server.'),
      FieldDef('keyHint', 'Key (masked)', FieldType.text, readOnly: true, section: 'Key'),
      FieldDef('owner', 'Owner', FieldType.text, required: true, section: 'Key', help: 'Who renews it and gets the expiry reminder.'),
      FieldDef('expiresAt', 'Expires', FieldType.dateTime, section: 'Key', help: 'The dashboard warns 14 days before.'),
      FieldDef('lastRotated', 'Key last changed', FieldType.dateTime, readOnly: true, section: 'Key'),
    ],
    actions: [
      ActionDef('Mark key renewed', Icons.autorenew, 'Connected', from: ['Expiring soon', 'Error']),
      ActionDef('Disable', Icons.link_off, 'Disabled', from: ['Connected', 'Expiring soon', 'Error'], danger: true),
      ActionDef('Enable', Icons.link, 'Connected', from: ['Disabled']),
    ],
  ),
  ModuleDef(
    key: 'appUpdates', title: 'App updates', singular: 'App update', group: 'System', icon: Icons.system_update_outlined,
    description: 'App releases and the minimum version people must update to.',
    formIntro: 'A release of the PIAX app. Raising the minimum version asks everyone below it to update before they continue.',
    titleField: 'version', subtitleFields: ['platform', 'minimumVersion', 'notes'], statusField: 'status',
    fields: [
      FieldDef('version', 'Version', FieldType.text, required: true, hint: '2.5.0', pattern: r'^\d+\.\d+\.\d+$', patternMessage: 'Use three numbers, like 2.5.0.'),
      FieldDef('platform', 'Platform', FieldType.choice, options: ['Android', 'iOS'], required: true),
      FieldDef('minimumVersion', 'Minimum version', FieldType.text, pattern: r'^\d+\.\d+\.\d+$', patternMessage: 'Use three numbers, like 2.2.0.', help: 'Anyone on an older version must update.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Draft', 'Rollout', 'Live'], help: 'Rollout: a share of people get it first. Live: everyone.'),
      FieldDef('notes', 'What’s new', FieldType.longText, required: true, help: 'Shown in the update prompt and the store listing.'),
      FieldDef('storeLink', 'Store link', FieldType.url),
      FieldDef('releasedAt', 'Released', FieldType.dateTime),
    ],
    actions: [
      ActionDef('Start rollout', Icons.rocket_launch_outlined, 'Rollout', from: ['Draft']),
      ActionDef('Release to all', Icons.public, 'Live', from: ['Rollout']),
    ],
  ),
  ModuleDef(
    key: 'staff', title: 'Staff accounts', singular: 'Staff member', group: 'System', icon: Icons.admin_panel_settings_outlined,
    description: 'Who can sign in to the admin panel, and their role.',
    formIntro: 'An invite to the admin panel. They get an email to set a password and turn on two-step sign-in.',
    titleField: 'name', subtitleFields: ['role', 'email'], statusField: 'status',
    fields: [
      FieldDef('name', 'Name', FieldType.text, required: true),
      FieldDef('email', 'Work email', FieldType.email, required: true, help: 'Use a @piax.co.in address.'),
      FieldDef('role', 'Role', FieldType.choice, options: ['Owner', 'Admin', 'Support', 'Viewer'], required: true, help: 'Owner: everything. Admin: everything but staff and credentials. Support: orders and members. Viewer: read-only.'),
      FieldDef('status', 'Status', FieldType.choice, options: ['Active', 'Invited', 'Disabled']),
      FieldDef('lastActive', 'Last active', FieldType.dateTime, readOnly: true),
    ],
    actions: [
      ActionDef('Disable', Icons.person_off_outlined, 'Disabled', from: ['Active', 'Invited'], danger: true),
      ActionDef('Enable', Icons.person_outline, 'Active', from: ['Disabled']),
    ],
  ),
  ModuleDef(
    key: 'audit', title: 'Audit log', singular: 'Audit entry', group: 'System', icon: Icons.history,
    description: 'Every change made in the admin panel. Read-only.',
    titleField: 'action', subtitleFields: ['actor', 'target', 'at'], canCreate: false, canEdit: false, canDelete: false,
    fields: [
      FieldDef('actor', 'Who', FieldType.text),
      FieldDef('action', 'What', FieldType.text),
      FieldDef('target', 'On', FieldType.text),
      FieldDef('at', 'When', FieldType.dateTime),
    ],
  ),
];

/// Colours for a status chip: green for live/good, amber for waiting/draft, red for stopped/blocked, grey otherwise.
(Color, Color) statusTone(String status) {
  const good = {'Connected', 'Active', 'Live', 'Published', 'Available', 'Online', 'Open', 'Visible', 'Completed', 'Booked'};
  const waiting = {'Expiring soon', 'Maintenance', 'Draft', 'Scheduled', 'Paused', 'Pending verification', 'Pending KYC', 'Rollout', 'Invited', 'On leave', 'Offline', 'Reported'};
  const stopped = {'Error', 'Hidden', 'Closed', 'Ended', 'Suspended', 'Blocked', 'Cancelled', 'No-show', 'Disabled'};
  if (good.contains(status)) return (const Color(0xFFDDF3EC), const Color(0xFF0B5B4E));
  if (waiting.contains(status)) return (const Color(0xFFFFF4D6), const Color(0xFF8A5A00));
  if (stopped.contains(status)) return (const Color(0xFFF3E3E3), const Color(0xFF8B2E2E));
  return (const Color(0xFFEEF2F1), const Color(0xFF475569));
}
