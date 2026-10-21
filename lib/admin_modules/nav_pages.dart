import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'admin_search.dart' show globalSearchActions;
import 'charts.dart';
import 'dashboard_widgets.dart';
import 'insights.dart' show Slice, Delta, HeadlineCard, chartPalette;
import 'nav_config.dart';
import 'option_store.dart';
import 'record_filter.dart';
import 'revenue_section.dart' show ComboChart;

// The content of the console's menu pages that have no screen of their own yet: one page template, filled from a
// short spec per page (what it tracks, its columns and the range of each), with dummy rows made from the page's id so
// they stay the same every time. Every page shows: a header with its place in the menu, number cards with the change
// against the previous 30 days, written highlights, a large weekly chart, a status ring and a breakdown, then a
// searchable, filterable, sortable table. All of it is labelled demo data.

// ================================================================ Specs

enum ColKind { id, pick, status, money, number, percent, date, person }

class Col {
  const Col._(this.label, this.kind, {this.pool = const [], this.min = 0, this.max = 0, this.unit = '', this.back = 0, this.ahead = 0});
  final String label;
  final ColKind kind;
  final List<String> pool;
  final num min, max;
  final String unit;

  /// Dates: how many days back and ahead of today they fall.
  final int back, ahead;
}

Col _id(String prefix) => Col._('ID', ColKind.id, pool: [prefix]);
Col _pick(String label, List<String> pool) => Col._(label, ColKind.pick, pool: pool);
Col _status(List<String> pool, [String label = 'Status']) => Col._(label, ColKind.status, pool: pool);
Col _money(String label, num min, num max) => Col._(label, ColKind.money, min: min, max: max);
Col _num(String label, num min, num max, [String unit = '']) => Col._(label, ColKind.number, min: min, max: max, unit: unit);
Col _pct(String label, num min, num max) => Col._(label, ColKind.percent, min: min, max: max);
Col _date(String label, {int back = 60, int ahead = 0}) => Col._(label, ColKind.date, back: back, ahead: ahead);
Col _person(String label) => Col._(label, ColKind.person);

class PageSpec {
  const PageSpec(this.entity, this.plural, this.about, this.columns, {this.rows = 32});

  /// One record and many: "Purchase order", "purchase orders".
  final String entity, plural;

  /// What the page is for, in a sentence.
  final String about;
  final List<Col> columns;
  final int rows;

  Col? first(ColKind kind) => columns.where((c) => c.kind == kind).firstOrNull;
}

const _products = ['PIAX VERA', 'PIAX LUMA', 'PIAX NOCTE', 'PIAX SEREN', 'PIAX Cycle Pack'];
const _materials = ['Non-woven top sheet', 'SAP granules', 'Fluff pulp', 'Breathable PE film', 'Release paper', 'Hot-melt adhesive', 'Anion strip', 'Printed cartons'];
const _suppliers = ['Sri Lakshmi Nonwovens', 'Apex Polymers', 'GreenCore SAP', 'PackRight Cartons', 'Shree Adhesives', 'Nova Release Papers', 'Kaveri Pulp Mills'];
const _oems = ['Ranipet Hygiene Works', 'Southern Converters', 'Precision Pads Pvt Ltd'];
const _warehouses = ['Ranipet main', 'Chennai hub', 'Bengaluru hub', 'Vellore store', 'Kochi hub'];
const _cities = ['Chennai', 'Vellore', 'Ranipet', 'Bengaluru', 'Coimbatore', 'Madurai', 'Hyderabad', 'Kochi', 'Pune'];
const _channels = ['Website', 'App', 'Amazon', 'Flipkart', 'B2B', 'Vending', 'Retail'];
const _sites = ['Anna University, Chennai', 'VIT Vellore', 'Tidel Park', 'Phoenix Mall, Chennai', 'SIPCOT Ranipet', 'KMC Hospital', 'Brigade Tech Park', 'Infopark Kochi'];
const _machines = ['VM-CHN-01', 'VM-CHN-02', 'VM-CHN-03', 'VM-VLR-01', 'VM-RPT-01', 'VM-BLR-01', 'VM-BLR-02', 'VM-KOC-01'];
const _accounts = ['Apollo Clinics', 'Infosys Chennai', 'SRM University', 'Sri Ramachandra Hospital', 'TCS Siruseri', 'Saveetha College', 'Zoho Estancia', 'CMC Vellore'];
const _severity = ['Critical', 'High', 'Medium', 'Low'];
const _people = ['Kamal Raj', 'Salaudin Ahmed', 'Prakash', 'Pranav N', 'Henna Thabasum', 'Jones Rinaldin', 'Visanth S', 'Kavinaya D'];

/// The team names offered for person columns (their dropdown menus start from these).
const demoPeople = _people;
const _reportFreq = ['Daily', 'Weekly', 'Monthly'];
const _reportStatus = ['Ready', 'Running', 'Failed'];

/// The page spec for every menu item without a screen of its own, by item id (nav_config.dart).
final navPageSpecs = <String, PageSpec>{
  // 01 Executive Command Centre
  'priority-exceptions': PageSpec('Exception', 'exceptions', 'Problems across the business that need a decision or an owner now, most severe first.', [
    _id('EX'), _pick('Area', ['Procurement', 'Quality', 'Inventory', 'Vending', 'Sales', 'Finance', 'Technology']),
    _pick('Exception', ['Batch on quarantine', 'Machine offline > 1 day', 'Supplier delivery late', 'Refunds overdue', 'Stock below cover', 'Settlement mismatch']),
    _pick('Severity', _severity), _person('Owner'), _date('Raised', back: 30), _status(['Open', 'Investigating', 'Resolved']),
  ]),
  'decisions-approvals': PageSpec('Approval', 'approvals', 'Requests waiting for a yes or no from the founders and leads, with their amount and who asked.', [
    _id('AP'), _pick('Type', ['Purchase order', 'Price change', 'New supplier', 'Budget increase', 'Machine deployment', 'Large refund']),
    _money('Amount', 5000, 900000), _person('Requested by'), _date('Requested', back: 30), _status(['Pending approval', 'Approved', 'Rejected']),
  ]),
  'targets-forecasts': PageSpec('Target', 'targets', 'Business targets for the period and how far along each one is.', [
    _id('TG'), _pick('Metric', ['Revenue', 'Orders', 'New members', 'Vending sales', 'B2B revenue', 'Gross margin']),
    _money('Target', 200000, 5000000), _pct('Achieved', 40, 115), _pick('Period', ['Oct 2026', 'Q3 FY27', 'Q4 FY27']), _date('Review', back: 10, ahead: 60),
    _status(['On track', 'At risk', 'Behind', 'Achieved']),
  ], rows: 18),

  // 02 Product & Master Data
  'sku-variants': PageSpec('SKU', 'SKUs', 'Every sellable pack: product, pack size, price and stock.', [
    _id('SKU'), _pick('Product', _products), _pick('Pack size', ['6 pads', '12 pads', '15 pads', '30 pads']), _money('MRP', 99, 599),
    _num('Stock', 0, 4000, 'boxes'), _date('Updated', back: 90), _status(['Active', 'Draft', 'Discontinued']),
  ], rows: 20),
  'bom-packaging': PageSpec('BOM', 'BOMs', 'Bills of materials and pack formats: what goes into each box and what it costs.', [
    _id('BOM'), _pick('Product', _products), _num('Components', 6, 14), _money('Material cost / box', 22, 78), _pick('Pack type', ['Carton', 'Pouch', 'Shrink pack']),
    _date('Revised', back: 180), _status(['Approved', 'Draft', 'Under review']),
  ], rows: 16),
  'product-specs': PageSpec('Specification', 'specifications', 'Product specifications and their revisions, with what changed in each.', [
    _id('SPEC'), _pick('Product', _products), _pick('Revision', ['Rev A', 'Rev B', 'Rev C', 'Rev D']),
    _pick('Change', ['Top sheet GSM 18 → 20', 'Wing adhesive width', 'Core length +10 mm', 'Carton artwork', 'Anion strip supplier']),
    _person('Owner'), _date('Effective', back: 240), _status(['Released', 'Under review', 'Draft']),
  ], rows: 20),
  'pricing-tax': PageSpec('Price rule', 'price rules', 'Prices by product and channel, with the GST slab and when each applies.', [
    _id('PRC'), _pick('Product', _products), _pick('Channel', _channels), _money('Price', 89, 599), _pick('GST', ['0%', '5%', '12%']),
    _date('From', back: 120, ahead: 30), _status(['Active', 'Scheduled', 'Expired']),
  ]),
  'suppliers-partners': PageSpec('Supplier', 'suppliers', 'Approved suppliers and partners, what they supply and how reliably.', [
    _id('SUP'), _pick('Name', _suppliers), _pick('Supplies', _materials), _pick('City', _cities), _pct('On-time delivery', 72, 99),
    _num('Lead time', 5, 35, 'days'), _date('Last order', back: 90), _status(['Approved', 'Under review', 'Blocked']),
  ], rows: 20),
  'warehouses-locations': PageSpec('Location', 'locations', 'Warehouses, hubs and packing units: capacity and how full they are.', [
    _id('WH'), _pick('Name', _warehouses), _pick('Type', ['Warehouse', 'Dark store', 'Packing unit', 'Partner store']), _pick('City', _cities),
    _num('Capacity', 2000, 40000, 'boxes'), _pct('Used', 20, 96), _date('Last audit', back: 120), _status(['Active', 'Planned', 'Closed']),
  ], rows: 14),

  // 03 Procurement, OEM & Packaging
  'purchase-requests': PageSpec('Purchase request', 'purchase requests', 'Requests from teams to buy materials, on their way to quotes and purchase orders.', [
    _id('PR'), _pick('Material', _materials), _num('Quantity', 500, 20000, 'kg'), _money('Estimated cost', 20000, 600000), _person('Requested by'),
    _date('Raised', back: 60), _status(['Draft', 'Pending approval', 'Approved', 'Rejected', 'Converted to PO']),
  ]),
  'supplier-quotations': PageSpec('Quotation', 'quotations', 'Quotes from suppliers, compared on price and lead time.', [
    _id('QT'), _pick('Supplier', _suppliers), _pick('Material', _materials), _money('Quoted price', 18000, 520000), _num('Lead time', 5, 30, 'days'),
    _date('Received', back: 45), _status(['Received', 'Shortlisted', 'Accepted', 'Rejected']),
  ]),
  'purchase-orders': PageSpec('Purchase order', 'purchase orders', 'Orders placed with suppliers, their value and when goods are due.', [
    _id('PO'), _pick('Supplier', _suppliers), _pick('Material', _materials), _money('Value', 25000, 900000), _date('Expected', back: 20, ahead: 25),
    _status(['Draft', 'Sent', 'Partially received', 'Received', 'Cancelled']),
  ]),
  'oem-planning': PageSpec('Production plan', 'production plans', 'Planned production runs at OEM partners and how much capacity is booked.', [
    _id('PP'), _pick('Product', _products), _pick('OEM', _oems), _num('Planned quantity', 5000, 80000, 'pads'), _pct('Capacity booked', 40, 100),
    _date('Starts', back: 10, ahead: 40), _status(['Planned', 'Confirmed', 'At risk']),
  ], rows: 22),
  'oem-orders': PageSpec('OEM order', 'OEM orders', 'Production orders running at OEM partners, from start to receipt.', [
    _id('OEM'), _pick('OEM', _oems), _pick('Product', _products), _num('Quantity', 10000, 120000, 'pads'), _money('Value', 150000, 1800000),
    _date('Due', back: 15, ahead: 30), _status(['In production', 'Quality check', 'Dispatched', 'Received', 'Delayed']),
  ]),
  'goods-receipt': PageSpec('Goods receipt', 'goods receipts', 'Materials received against purchase orders, and how much passed inspection.', [
    _id('GRN'), _pick('Supplier', _suppliers), _pick('Material', _materials), _num('Quantity', 500, 20000, 'units'), _pct('Accepted', 85, 100),
    _date('Received', back: 45), _status(['Received', 'Partially received', 'Rejected']),
  ]),
  'packaging-materials': PageSpec('Packaging item', 'packaging items', 'Cartons, films and seals: stock, cost and reorder levels by vendor.', [
    _id('PKG'), _pick('Item', ['Printed carton (12)', 'Printed carton (6)', 'Pouch film', 'Shrink film', 'Tamper seal', 'Leaflet']),
    _pick('Vendor', ['PackRight Cartons', 'Sri Murugan Printers', 'FlexiPack Films']), _num('In stock', 500, 60000, 'pcs'), _money('Unit cost', 1, 18),
    _num('Reorder at', 2000, 10000, 'pcs'), _date('Last received', back: 60), _status(['In stock', 'Low stock', 'Out of stock']),
  ], rows: 18),
  'packing-work-orders': PageSpec('Work order', 'work orders', 'Packing jobs on the lines: boxes planned and how far along each is.', [
    _id('WO'), _pick('Product', _products), _num('Boxes', 200, 6000, 'boxes'), _pick('Line', ['Line 1', 'Line 2', 'Line 3']), _pct('Done', 0, 100),
    _date('Planned', back: 10, ahead: 10), _status(['Planned', 'In progress', 'Completed', 'On hold']),
  ]),
  'material-consumption': PageSpec('Consumption entry', 'consumption entries', 'Materials used in production against the standard quantity.', [
    _id('MC'), _pick('Material', _materials), _pick('Product', _products), _num('Used', 50, 4000, 'kg'), _pct('Against standard', 88, 112),
    _date('Date', back: 30), _status(['Within standard', 'Over standard']),
  ]),
  'wastage-rework': PageSpec('Wastage record', 'wastage records', 'Pads scrapped or reworked, where it happened and what it cost.', [
    _id('WR'), _pick('Stage', ['Cutting', 'Bonding', 'Folding', 'Packing', 'QC rejection']), _pick('Product', _products), _num('Quantity', 20, 1800, 'pads'),
    _money('Cost', 500, 40000), _date('Date', back: 45), _status(['Scrapped', 'Reworked', 'Under review']),
  ]),

  // 04 Quality & Product Governance
  'incoming-qc': PageSpec('Inspection', 'inspections', 'Incoming materials checked before they reach production.', [
    _id('IQC'), _pick('Material', _materials), _pick('Supplier', _suppliers), _num('Samples', 5, 50), _pct('Pass rate', 82, 100),
    _date('Inspected', back: 45), _status(['Passed', 'Failed', 'On hold']),
  ]),
  'in-process-qc': PageSpec('Line check', 'line checks', 'Checks on the production line: length, core weight, adhesion and seals.', [
    _id('IPQC'), _pick('Line', ['Line 1', 'Line 2', 'Line 3']), _pick('Check', ['Pad length', 'Core weight', 'Wing adhesion', 'Seal strength', 'Fold accuracy']),
    _num('Samples', 10, 80), _pct('Within spec', 85, 100), _date('Checked', back: 20), _status(['Passed', 'Failed', 'Investigating']),
  ]),
  'finished-goods-qc': PageSpec('Finished-goods test', 'finished-goods tests', 'Packed boxes tested before release.', [
    _id('FQC'), _pick('Product', _products), _num('Boxes tested', 5, 40), _pct('Pass rate', 90, 100), _pick('Inspector', _people),
    _date('Tested', back: 30), _status(['Passed', 'Failed', 'Retest']),
  ]),
  'batch-release': PageSpec('Batch', 'batches', 'Batches waiting for release, released for sale, or held in quarantine.', [
    _id('B26'), _pick('Product', _products), _num('Boxes', 500, 8000, 'boxes'), _pick('Warehouse', _warehouses), _date('Made', back: 60),
    _status(['Released', 'Pending release', 'Quarantined']),
  ]),
  'lab-reports': PageSpec('Lab report', 'lab reports', 'Laboratory test results by product and lab.', [
    _id('LAB'), _pick('Test', ['Absorbency (lab method)', 'Top sheet pH', 'Skin patch test', 'Microbial count', 'Wing adhesion', 'Leakage (lab simulation)']),
    _pick('Lab', ['NABL lab, Chennai', 'In-house lab', 'SITRA, Coimbatore']), _pick('Product', _products), _date('Reported', back: 120),
    _status(['Passed', 'Failed', 'Awaiting results']),
  ]),
  'claims-evidence': PageSpec('Claim', 'claims', 'Every marketing claim and the evidence behind it. Only validated claims may be used.', [
    _id('CLM'), _pick('Claim', ['Breathable backsheet', 'Superabsorbent polymer core (SAP layer)', 'Soft top sheet', 'Anion-infused design', 'Winged design', 'Leak-management design']),
    _pick('Evidence', ['Lab report', 'Supplier certificate', 'Design specification', 'Test video']), _pick('Product', _products), _date('Reviewed', back: 180),
    _status(['Validated', 'Under review', 'Not allowed']),
  ], rows: 20),
  'incidents-capa': PageSpec('Incident', 'incidents', 'Quality incidents and the corrective actions taken.', [
    _id('CAPA'), _pick('Issue', ['Weak wing adhesive', 'Carton print smudge', 'Leakage complaint', 'Short count in box', 'Seal opening in transit']),
    _pick('Severity', _severity), _person('Owner'), _date('Raised', back: 90), _status(['Open', 'Investigating', 'Corrective action', 'Closed']),
  ], rows: 24),
  'change-control': PageSpec('Change request', 'change requests', 'Proposed changes to product, packaging, suppliers or process, and their approval.', [
    _id('CC'), _pick('Change', ['Top sheet GSM', 'New SAP supplier', 'Carton size', 'Line speed', 'Adhesive grade']),
    _pick('Impact', ['Product', 'Packaging', 'Supplier', 'Process']), _person('Raised by'), _date('Raised', back: 150),
    _status(['Draft', 'Under review', 'Approved', 'Rejected', 'Implemented']),
  ], rows: 22),

  // 05 Inventory & Logistics
  'stock-overview': PageSpec('Stock line', 'stock lines', 'Stock of each product at each location, what is reserved and how many days it covers.', [
    _id('STK'), _pick('Product', _products), _pick('Location', _warehouses), _num('On hand', 0, 9000, 'boxes'), _num('Reserved', 0, 800, 'boxes'),
    _num('Days of cover', 2, 75, 'days'), _status(['In stock', 'Low stock', 'Out of stock']),
  ], rows: 25),
  'batch-ledger': PageSpec('Ledger entry', 'ledger entries', 'Every stock movement by batch and location.', [
    _id('LED'), _pick('Movement', ['Received', 'Picked', 'Transferred', 'Adjusted', 'Returned']), _pick('Product', _products), _num('Quantity', 10, 2000, 'boxes'),
    _pick('Location', _warehouses), _date('When', back: 30), _status(['Posted', 'Pending']),
  ], rows: 40),
  'stock-reservations': PageSpec('Reservation', 'reservations', 'Stock held for orders, refills and subscriptions until it ships.', [
    _id('RSV'), _pick('For', ['Website order', 'B2B order', 'Vending refill', 'Subscription', 'Marketplace']), _pick('Product', _products), _num('Boxes', 1, 600, 'boxes'),
    _date('Until', back: 5, ahead: 20), _status(['Reserved', 'Released', 'Expired']),
  ]),
  'transfers-counts': PageSpec('Transfer or count', 'transfers and counts', 'Stock moved between locations and cycle counts with their variances.', [
    _id('TRF'), _pick('Type', ['Transfer', 'Cycle count']), _pick('From', _warehouses), _pick('To', _warehouses), _num('Boxes', 20, 3000, 'boxes'),
    _date('Date', back: 45), _status(['Completed', 'In transit', 'Variance found']),
  ]),
  'reorder-planning': PageSpec('Reorder line', 'reorder lines', 'What to reorder, how much, and by when, from stock and lead times.', [
    _id('RO'), _pick('Item', [..._products, ..._materials.take(4)]), _num('On hand', 0, 6000), _num('Reorder point', 800, 4000), _num('Suggested quantity', 1000, 20000),
    _date('Order by', back: 3, ahead: 30), _status(['Reorder now', 'Due soon', 'OK']),
  ], rows: 22),

  // 06 Vending Machine Operations
  'vending-command': PageSpec('Machine', 'machines', 'Every vending machine right now: online, stocked, selling.', [
    _id('VM'), _pick('Location', _sites), _pct('Stock level', 5, 100), _num('Vends today', 0, 60), _money('Sales today', 0, 3000), _date('Last refill', back: 10),
    _status(['Online', 'Low stock', 'Offline', 'Needs service']),
  ], rows: 24),
  'machine-register': PageSpec('Machine', 'machines', 'The asset passport of every machine: model, owner, site and value.', [
    _id('VM'), _pick('Model', ['PIAX V1 (12 slots)', 'PIAX V2 (24 slots)', 'Compact wall unit']), _pick('Location', _sites), _pick('Owner', ['PIAX', 'Partner', 'Leased']),
    _money('Asset value', 45000, 160000), _date('Installed', back: 400), _status(['Active', 'In storage', 'Under repair', 'Retired']),
  ], rows: 24),
  'vending-oem': PageSpec('Machine order', 'machine orders', 'Machines ordered from OEMs, through production to delivery.', [
    _id('VPO'), _pick('OEM', ['Kiosk Systems Pvt Ltd', 'VendTech India', 'SmartBox Automation']), _num('Machines', 2, 40), _money('Value', 100000, 4500000),
    _date('Expected', back: 20, ahead: 60), _status(['Ordered', 'In production', 'Ready for FAT', 'Delivered']),
  ], rows: 14),
  'vending-fat': PageSpec('FAT test', 'FAT tests', 'Factory acceptance tests run on machines before they ship.', [
    _id('FAT'), _pick('Check', ['UPI payment', 'Dispense accuracy', 'Door lock', 'Display', 'Connectivity', 'Power-cut recovery']), _num('Units tested', 2, 20),
    _pct('Pass rate', 70, 100), _date('Tested', back: 90), _status(['Passed', 'Failed', 'Retest']),
  ], rows: 24),
  'vending-deployment': PageSpec('Installation', 'installations', 'Machines being installed at sites, from survey to go-live.', [
    _id('INS'), _pick('Location', _sites), _pick('Machine', _machines), _person('Engineer'), _date('Scheduled', back: 15, ahead: 30),
    _status(['Planned', 'Site survey', 'Installed', 'Delayed']),
  ], rows: 20),
  'vending-connectivity': PageSpec('Device', 'devices', 'Each machine’s network, signal and uptime.', [
    _id('VM'), _pick('Network', ['4G', 'Wi-Fi', '4G + Wi-Fi']), _pick('Location', _sites), _pct('Uptime (30 days)', 80, 100), _num('Signal', 1, 5, 'bars'),
    _date('Last seen', back: 2), _status(['Online', 'Weak signal', 'Offline']),
  ], rows: 24),
  'vending-firmware': PageSpec('Configuration', 'configurations', 'Firmware, price profile and payment modes on each machine.', [
    _id('VM'), _pick('Firmware', ['v2.3.1', 'v2.4.0', 'v2.4.2']), _pick('Price profile', ['Campus', 'Corporate', 'Hospital', 'Mall']),
    _pick('Payments', ['UPI', 'UPI + card', 'UPI + coins']), _date('Updated', back: 120), _status(['Up to date', 'Update available', 'Update failed']),
  ], rows: 24),
  'vending-slots': PageSpec('Slot', 'slots', 'What each slot holds and how many pads are left.', [
    _id('SL'), _pick('Machine', _machines), _pick('Product', _products), _num('Pads left', 0, 24), _num('Capacity', 12, 24), _date('Refilled', back: 14),
    _status(['Full', 'Low', 'Empty']),
  ], rows: 40),
  'vending-transactions': PageSpec('Vend', 'vends', 'Every vend: machine, product, amount and payment.', [
    _id('TXN'), _pick('Machine', _machines), _pick('Product', _products), _money('Amount', 10, 60), _pick('Payment', ['UPI', 'Card', 'Coins']),
    _date('When', back: 14), _status(['Dispensed', 'Refunded', 'Failed']),
  ], rows: 60),
  'vending-payments': PageSpec('Settlement', 'settlements', 'Money collected by the payment providers and paid out to PIAX.', [
    _id('VST'), _pick('Provider', ['Razorpay UPI', 'Paytm', 'PhonePe']), _num('Vends', 40, 900), _money('Amount', 800, 45000), _date('Settled', back: 45),
    _status(['Settled', 'Pending', 'Mismatch']),
  ], rows: 24),
  'vending-refill': PageSpec('Refill run', 'refill runs', 'Refill routes: machines visited and boxes loaded.', [
    _id('RUN'), _pick('Route', ['Chennai south', 'Chennai OMR', 'Vellore campus', 'Bengaluru east']), _num('Machines', 3, 14), _num('Boxes loaded', 10, 120),
    _person('Driver'), _date('Date', back: 10, ahead: 7), _status(['Planned', 'In progress', 'Completed', 'Missed']),
  ], rows: 24),
  'vending-service': PageSpec('Service ticket', 'service tickets', 'Faults reported on machines and the engineers fixing them.', [
    _id('SRV'), _pick('Machine', _machines), _pick('Issue', ['Coin jam', 'Display blank', 'Not dispensing', 'Door sensor', 'Payment failing']),
    _person('Engineer'), _num('Hours open', 1, 96, 'hrs'), _date('Opened', back: 30), _status(['Open', 'In progress', 'Resolved']),
  ], rows: 26),
  'vending-alerts': PageSpec('Alert', 'alerts', 'Alerts raised by machines and their incident log.', [
    _id('ALR'), _pick('Machine', _machines), _pick('Alert', ['Low stock', 'Offline 30 min+', 'Temperature high', 'Tamper detected', 'Payment error']),
    _pick('Severity', _severity), _date('Raised', back: 14), _status(['Open', 'Acknowledged', 'Resolved']),
  ], rows: 36),
  'vending-locations': PageSpec('Site', 'sites', 'Host locations and partners, the machines there and the revenue share agreed.', [
    _id('SITE'), _pick('Location', _sites), _pick('Partner type', ['College', 'Corporate', 'Hospital', 'Mall', 'Government office']), _num('Machines', 1, 6),
    _pct('Revenue share', 5, 25), _person('Contact'), _status(['Active', 'Negotiation', 'Ended']),
  ], rows: 16),
  'vending-revenue-share': PageSpec('Payout', 'payouts', 'Monthly sales per site and the partner’s share paid or due.', [
    _id('RS'), _pick('Partner', _sites), _money('Sales', 5000, 120000), _pct('Share', 5, 25), _money('Payout', 500, 20000), _date('Month', back: 120),
    _status(['Paid', 'Due', 'Disputed']),
  ], rows: 24),
  'vending-profitability': PageSpec('Machine P&L', 'machine P&Ls', 'Revenue, cost and margin of each machine over the last 30 days.', [
    _id('VM'), _pick('Location', _sites), _money('Revenue (30 days)', 2000, 60000), _money('Costs (30 days)', 1500, 30000), _pct('Margin', -10, 55),
    _num('Payback', 4, 30, 'months'), _status(['Profitable', 'Break-even', 'Loss-making']),
  ], rows: 24),
  'vending-warranty': PageSpec('Contract', 'contracts', 'Warranties and maintenance contracts on each machine.', [
    _id('AMC'), _pick('Machine', _machines), _pick('Type', ['Warranty', 'AMC', 'Extended warranty']), _pick('Provider', ['Kiosk Systems Pvt Ltd', 'VendTech India']),
    _money('Annual fee', 0, 18000), _date('Expires', back: 30, ahead: 365), _status(['Active', 'Expiring soon', 'Expired']),
  ], rows: 20),
  'vending-retirement': PageSpec('Asset move', 'asset moves', 'Machines moved to better sites, refurbished or retired, and why.', [
    _id('MOV'), _pick('Machine', _machines), _pick('From', _sites), _pick('Action', ['Redeploy', 'Retire', 'Refurbish']), _pick('Reason', ['Low sales', 'Site closed', 'Damage', 'Upgrade']),
    _date('Date', back: 180, ahead: 30), _status(['Planned', 'Completed']),
  ], rows: 14),

  // 07 Sales & Business Growth
  'crm-pipeline': PageSpec('Deal', 'deals', 'Open deals by stage, value and the next step.', [
    _id('DL'), _pick('Account', _accounts), _money('Value', 20000, 2500000), _pct('Probability', 10, 90), _person('Owner'), _date('Next step', back: 5, ahead: 30),
    _status(['Lead', 'Qualified', 'Proposal', 'Negotiation', 'Won', 'Lost'], 'Stage'),
  ]),
  'b2b-sales': PageSpec('B2B order', 'B2B orders', 'Orders from companies, colleges and hospitals.', [
    _id('B2B'), _pick('Customer', _accounts), _num('Boxes', 100, 6000, 'boxes'), _money('Value', 20000, 900000), _date('Ordered', back: 90),
    _status(['Quoted', 'Confirmed', 'Dispatched', 'Delivered', 'Paid']),
  ]),
  'b2g-tenders': PageSpec('Tender', 'tenders', 'Government tenders being prepared, submitted and decided.', [
    _id('TND'), _pick('Department', ['TN Health Dept', 'Greater Chennai Corp', 'Kerala Women’s Development Corp', 'Karnataka Education Dept', 'NHM Tamil Nadu']),
    _money('Value', 500000, 25000000), _person('Owner'), _date('Closes', back: 20, ahead: 45), _status(['Preparing', 'Submitted', 'Technical evaluation', 'Won', 'Lost']),
  ], rows: 18),
  'marketplace-sales': PageSpec('Listing', 'listings', 'Sales on each marketplace by product, with return rates.', [
    _id('MP'), _pick('Marketplace', ['Amazon', 'Flipkart', 'Nykaa', 'Meesho', 'BigBasket']), _pick('Product', _products), _num('Units', 20, 1800),
    _money('Sales', 2000, 200000), _pct('Return rate', 0, 9), _date('Updated', back: 7), _status(['Active', 'Suppressed', 'Out of stock']),
  ]),
  'franchisees': PageSpec('Franchisee', 'franchisees', 'Franchise partners, their outlets and monthly sales.', [
    _id('FR'), _pick('City', _cities), _num('Outlets', 1, 5), _money('Monthly sales', 20000, 400000), _person('Account manager'), _date('Joined', back: 600),
    _status(['Active', 'Onboarding', 'Paused']),
  ], rows: 18),
  'institutional-contracts': PageSpec('Contract', 'contracts', 'Supply contracts with institutions: monthly volume, value and renewal.', [
    _id('IC'), _pick('Institution', _accounts), _num('Boxes / month', 100, 5000, 'boxes'), _money('Annual value', 100000, 6000000), _date('Renews', back: 10, ahead: 300),
    _status(['Active', 'Renewal due', 'Expired']),
  ], rows: 16),

  // 08 Finance & Unit Economics
  'revenue-reconciliation': PageSpec('Reconciliation', 'reconciliations', 'Revenue recorded against money received, by channel and period.', [
    _id('RR'), _pick('Channel', _channels), _money('Recorded', 50000, 2000000), _money('Received', 50000, 2000000), _date('Period', back: 120),
    _status(['Matched', 'Mismatch', 'In review']),
  ], rows: 24),
  'receivables': PageSpec('Invoice', 'invoices', 'Money customers owe PIAX, and how overdue it is.', [
    _id('INV'), _pick('Customer', _accounts), _money('Amount', 5000, 900000), _num('Days overdue', 0, 75, 'days'), _date('Due', back: 30, ahead: 30),
    _status(['Paid', 'Due', 'Overdue']),
  ]),
  'payables': PageSpec('Bill', 'bills', 'Supplier bills to pay, and when.', [
    _id('BILL'), _pick('Supplier', _suppliers), _money('Amount', 8000, 700000), _date('Due', back: 20, ahead: 30), _status(['Paid', 'Due', 'Overdue', 'On hold']),
  ]),
  'gateway-settlements': PageSpec('Settlement', 'settlements', 'Razorpay settlements: payments, gross, fees and what landed.', [
    _id('STL'), _num('Payments', 20, 800), _money('Gross', 5000, 300000), _money('Fees', 100, 6000), _date('Settled', back: 60), _status(['Settled', 'Pending', 'Mismatch']),
  ]),
  'marketplace-settlements': PageSpec('Settlement', 'settlements', 'Marketplace payouts after commission.', [
    _id('MPS'), _pick('Marketplace', ['Amazon', 'Flipkart', 'Nykaa', 'Meesho']), _money('Sales', 20000, 800000), _money('Commission', 2000, 120000),
    _date('Settled', back: 90), _status(['Settled', 'Pending', 'Disputed']),
  ], rows: 24),
  'vending-settlements': PageSpec('Settlement', 'settlements', 'Money collected from machines and the partner share.', [
    _id('VS'), _pick('Location', _sites), _money('Collected', 1000, 60000), _money('Partner share', 100, 12000), _date('Settled', back: 90), _status(['Settled', 'Pending']),
  ], rows: 24),
  'product-costing': PageSpec('Cost sheet', 'cost sheets', 'What each box costs to make and land, and the margin left.', [
    _id('CST'), _pick('Product', _products), _money('Material', 20, 90), _money('Conversion', 5, 25), _money('Packaging', 4, 16), _pct('Gross margin', 25, 62),
    _date('Updated', back: 120), _status(['Approved', 'Draft']),
  ], rows: 15),
  'channel-contribution': PageSpec('Channel line', 'channel lines', 'Revenue, variable cost and contribution by channel and machine.', [
    _id('CH'), _pick('Channel', _channels), _money('Revenue', 100000, 4000000), _money('Variable costs', 40000, 1800000), _pct('Contribution margin', 8, 48),
    _date('Month', back: 150), _status(['Healthy', 'Watch', 'Negative']),
  ], rows: 21),
  'expenses-budgets': PageSpec('Budget line', 'budget lines', 'Budget against spend by department.', [
    _id('BUD'), _pick('Department', ['Marketing', 'Operations', 'Technology', 'People', 'Quality', 'Vending']), _money('Budget', 100000, 2500000),
    _money('Spent', 50000, 2600000), _pct('Used', 30, 110), _date('Month', back: 150), _status(['On track', 'At risk', 'Over budget']),
  ], rows: 24),
  'cash-flow': PageSpec('Cash-flow week', 'cash-flow weeks', 'Money in and out week by week, and the balance left.', [
    _id('CF'), _money('Inflows', 200000, 2500000), _money('Outflows', 150000, 2300000), _money('Closing balance', 500000, 6000000), _date('Week starting', back: 30, ahead: 84),
    _status(['Comfortable', 'Tight', 'Shortfall']),
  ], rows: 16),
  'inventory-valuation': PageSpec('Valuation line', 'valuation lines', 'What the stock on hand is worth, by item and location.', [
    _id('VAL'), _pick('Item', [..._products, ..._materials.take(4)]), _pick('Location', _warehouses), _num('Quantity', 100, 40000), _money('Value', 10000, 1800000),
    _pick('Method', ['FIFO', 'Weighted average']), _status(['Counted', 'Pending count']),
  ]),
  'compliance-documents': PageSpec('Document', 'documents', 'Tax filings, licences and certificates, with their due and renewal dates.', [
    _id('DOC'), _pick('Document', ['GSTR-3B', 'TDS return', 'BIS certificate', 'Trade licence', 'Pollution consent', 'OEM factory licence']), _person('Owner'),
    _date('Due / renews', back: 30, ahead: 180), _status(['Filed', 'Valid', 'Due soon', 'Overdue']),
  ], rows: 18),

  // 10 Marketing & Customer Experience
  'campaign-calendar': PageSpec('Campaign', 'campaigns', 'Campaigns planned, live and finished, with their budget.', [
    _id('CMP'), _pick('Campaign', ['Diwali care box', 'Back to campus', 'Menstrual Hygiene Day', 'Cycle Pack launch', 'Subscribe & save', 'Women’s Day']),
    _pick('Channel', ['Instagram', 'WhatsApp', 'Email', 'Google Ads', 'Offline']), _money('Budget', 10000, 400000), _date('Starts', back: 30, ahead: 60),
    _status(['Planned', 'Live', 'Completed']),
  ], rows: 22),
  'social-creators': PageSpec('Creator post', 'creator posts', 'Creator and social posts: reach, engagement and payment.', [
    _id('SOC'), _pick('Creator', ['@periodtalks', '@chennaimoms', '@campuslife', '@wellnesswithdiya', '@fitwithkavya']), _pick('Platform', ['Instagram', 'YouTube', 'Moj']),
    _num('Reach', 2000, 400000), _pct('Engagement', 1, 12), _money('Fee', 2000, 60000), _date('Posted', back: 60), _status(['Briefed', 'Posted', 'Paid']),
  ]),
  'acquisition-conversion': PageSpec('Source week', 'source weeks', 'Visitors, conversion and cost per order by traffic source.', [
    _id('ACQ'), _pick('Source', ['Google search', 'Instagram ads', 'WhatsApp', 'Referral', 'Direct']), _num('Visitors', 500, 40000), _pct('Conversion', 1, 6),
    _money('Cost per order', 40, 450), _date('Week', back: 84), _status(['Above target', 'On target', 'Below target']),
  ], rows: 36),
  'campaign-attribution': PageSpec('Attribution', 'attributions', 'Orders and revenue credited to each campaign against its spend.', [
    _id('ATR'), _pick('Campaign', ['Diwali care box', 'Back to campus', 'Cycle Pack launch', 'Subscribe & save']), _num('Orders', 5, 900), _money('Revenue', 2000, 600000),
    _money('Spend', 1000, 200000), _date('Week', back: 84), _status(['Profitable', 'Break-even', 'Unprofitable']),
  ]),
  'customer-support': PageSpec('Ticket', 'tickets', 'Support tickets by topic and channel, and how fast they were answered.', [
    _id('TKT'), _pick('Topic', ['Delivery delay', 'Wrong item', 'Refund status', 'Subscription change', 'Product question', 'App sign-in']),
    _pick('Channel', ['WhatsApp', 'Email', 'Phone', 'App chat']), _person('Agent'), _num('First reply', 1, 48, 'hrs'), _date('Opened', back: 30),
    _status(['Open', 'Waiting on customer', 'Resolved']),
  ], rows: 40),
  'complaints-feedback': PageSpec('Complaint', 'complaints', 'Complaints and feedback by category and product.', [
    _id('CMPL'), _pick('Category', ['Product quality', 'Packaging', 'Delivery', 'Payment', 'Website or app']), _pick('Product', _products), _pick('Severity', _severity),
    _date('Received', back: 60), _status(['New', 'Investigating', 'Resolved']),
  ]),
  'retention': PageSpec('Cohort', 'cohorts', 'Members by the month they joined: how many bought again and what they spend.', [
    _id('COH'), _num('Members', 40, 900), _pct('Repeat in 60 days', 15, 62), _money('Average spend', 250, 1400), _date('Joined (month)', back: 300),
    _status(['Strong', 'Average', 'Weak']),
  ], rows: 12),

  // 11 People, Governance & Reports
  'roles-permissions': PageSpec('Role', 'roles', 'Roles in the admin console, who holds them and when they were last reviewed.', [
    _id('ROLE'), _pick('Role', ['Owner', 'Admin', 'Operations', 'Quality', 'Finance', 'Support', 'Viewer']), _num('People', 1, 12), _num('Permissions', 6, 90),
    _date('Reviewed', back: 180), _status(['Active', 'Review due']),
  ], rows: 12),
  'approval-policies': PageSpec('Policy', 'policies', 'Who approves what, above which amount.', [
    _id('POL'), _pick('Applies to', ['Purchase orders', 'Refunds', 'Price changes', 'Budgets', 'New suppliers', 'Machine deployment']), _money('Threshold', 5000, 500000),
    _pick('Approver', ['Founder', 'CEO', 'Finance lead', 'Operations lead']), _date('Updated', back: 300), _status(['Active', 'Draft']),
  ], rows: 14),
  'sops-documents': PageSpec('SOP', 'SOPs', 'Standard operating procedures and documents, with their review dates.', [
    _id('SOP'), _pick('Area', ['QC', 'Packing', 'Dispatch', 'Vending refill', 'Support', 'Finance close']), _pick('Version', ['v1.0', 'v1.2', 'v2.0', 'v2.1']),
    _person('Owner'), _date('Reviewed', back: 365), _status(['Approved', 'Under review', 'Review due']),
  ], rows: 20),
  'kpi-catalogue': PageSpec('KPI', 'KPIs', 'Every KPI, its owner, how often it’s measured and how it’s doing.', [
    _id('KPI'), _pick('KPI', ['Revenue', 'Gross margin', 'On-time dispatch', 'QC pass rate', 'Vending uptime', 'Repeat purchase rate', 'Cost per order', 'Cash runway']),
    _pick('Team', ['Founders', 'Operations', 'Quality', 'Sales', 'Finance', 'Technology']), _pick('Measured', _reportFreq), _pct('Achievement', 60, 115),
    _date('Updated', back: 30), _status(['On track', 'At risk', 'Behind']),
  ], rows: 16),
  'executive-reports': PageSpec('Report', 'reports', 'Reports for the founders and board.', [
    _id('RPT'), _pick('Report', ['Weekly business review', 'Board pack', 'Cash and runway', 'Vending roll-out', 'Top exceptions']), _pick('Frequency', _reportFreq),
    _person('Prepared by'), _date('Last run', back: 30), _status(_reportStatus),
  ], rows: 14),
  'operations-reports': PageSpec('Report', 'reports', 'Operations and quality reports.', [
    _id('RPT'), _pick('Report', ['Dispatch performance', 'QC pass rates', 'Wastage', 'Stock cover', 'Machine uptime']), _pick('Frequency', _reportFreq),
    _person('Prepared by'), _date('Last run', back: 30), _status(_reportStatus),
  ], rows: 14),
  'sales-reports': PageSpec('Report', 'reports', 'Sales and marketing reports.', [
    _id('RPT'), _pick('Report', ['Channel sales', 'Pipeline', 'Campaign ROI', 'Repeat purchase', 'Marketplace health']), _pick('Frequency', _reportFreq),
    _person('Prepared by'), _date('Last run', back: 30), _status(_reportStatus),
  ], rows: 14),
  'finance-reports': PageSpec('Report', 'reports', 'Finance reports.', [
    _id('RPT'), _pick('Report', ['P&L', 'Receivables ageing', 'GST summary', 'Unit economics', 'Budget vs actual']), _pick('Frequency', _reportFreq),
    _person('Prepared by'), _date('Last run', back: 30), _status(_reportStatus),
  ], rows: 14),
  'data-quality': PageSpec('Check', 'checks', 'Automatic checks that the data adds up across systems.', [
    _id('DQ'), _pick('Dataset', ['Orders', 'Inventory', 'Members', 'Vending sales', 'Supplier bills']),
    _pick('Rule', ['No duplicate IDs', 'Totals match payments', 'Stock never negative', 'Every vend has a payment', 'GST numbers valid']), _num('Issues', 0, 120),
    _date('Checked', back: 7), _status(['Passed', 'Issues found']),
  ], rows: 20),
  'clickup-links': PageSpec('ClickUp space', 'ClickUp spaces', 'The ClickUp spaces each team works in, and their open tasks.', [
    _id('CU'), _pick('Space', ['Product launches', 'Procurement', 'Vending roll-out', 'Marketing calendar', 'Tech roadmap', 'Quality CAPA']), _num('Open tasks', 3, 140),
    _person('Owner'), _date('Updated', back: 14), _status(['Linked', 'Not linked']),
  ], rows: 12),

  // 12 Technology, IAM & Integrations
  'device-registry': PageSpec('Device', 'devices', 'Devices that connect to PIAX systems and their certificates.', [
    _id('DEV'), _pick('Type', ['Vending controller', 'Payment terminal', 'Warehouse scanner', 'Label printer']), _pick('Location', [..._sites.take(4), ..._warehouses.take(2)]),
    _pick('Firmware', ['v2.3.1', 'v2.4.0', 'v2.4.2']), _date('Certificate expires', back: 10, ahead: 400), _status(['Active', 'Certificate expiring', 'Revoked']),
  ]),
  'api-webhook-health': PageSpec('Endpoint', 'endpoints', 'Each API and webhook: success rate and speed over the last day.', [
    _id('API'), _pick('Endpoint', ['Razorpay webhook', 'WhatsApp webhook', 'Courier tracking', 'Google sign-in', 'Vending telemetry', 'Marketplace sync']),
    _pct('Success (24h)', 85, 100), _num('Average latency', 80, 2400, 'ms'), _date('Last call', back: 1), _status(['Healthy', 'Degraded', 'Down']),
  ], rows: 18),
  'sync-failures': PageSpec('Failed sync', 'failed syncs', 'Records that failed to sync between systems, and their retries.', [
    _id('SYN'), _pick('Integration', ['Razorpay', 'WhatsApp', 'Courier', 'Marketplace', 'Vending']), _pick('Record', ['Order', 'Stock', 'Payment', 'Vend', 'Invoice']),
    _num('Retries', 0, 6), _date('Failed', back: 7), _status(['Retrying', 'Resolved', 'Failed']),
  ]),
  'notification-rules': PageSpec('Rule', 'rules', 'Who gets told about what, and how.', [
    _id('NTF'), _pick('Event', ['New order', 'Refund due', 'Machine offline', 'Stock below reorder', 'QC failure', 'Key expiring']),
    _pick('Channel', ['WhatsApp', 'Email', 'Push', 'SMS']), _pick('Recipients', ['Operations', 'Founders', 'Finance', 'Support']), _date('Updated', back: 200),
    _status(['Active', 'Paused']),
  ], rows: 16),
  'security-events': PageSpec('Security event', 'security events', 'Sign-ins, permission changes and data exports worth a second look.', [
    _id('SEC'), _pick('Event', ['Failed admin sign-in', 'New device sign-in', 'Permission changed', 'Key used from new IP', 'Member data exported']),
    _pick('Severity', _severity), _person('User'), _date('When', back: 30), _status(['Open', 'Investigating', 'Reviewed']),
  ]),
  'access-reviews': PageSpec('Access review', 'access reviews', 'Periodic checks that each person still needs the access they have.', [
    _id('UAR'), _person('Person'), _pick('Role', ['Owner', 'Admin', 'Operations', 'Finance', 'Support', 'Viewer']), _num('Systems', 2, 9),
    _date('Due', back: 10, ahead: 60), _status(['Completed', 'Due', 'Overdue']),
  ], rows: 16),
  'import-export': PageSpec('Job', 'jobs', 'Bulk imports and exports, how many rows and whether they worked.', [
    _id('JOB'), _pick('Job', ['Import products', 'Export orders', 'Import stock count', 'Export GST report', 'Import price list']), _num('Rows', 20, 40000),
    _person('Run by'), _date('Ran', back: 30), _status(['Completed', 'Running', 'Failed']),
  ]),
  'backup-recovery': PageSpec('Backup', 'backups', 'Backups of each system and when a restore was last tested.', [
    _id('BKP'), _pick('System', ['Website database', 'Order store', 'Media library', 'Admin data']), _num('Size', 1, 180, 'GB'), _num('Restore tested', 0, 90, 'days ago'),
    _date('Taken', back: 14), _status(['Succeeded', 'Failed', 'Running']),
  ]),
};

// ================================================================ Rows

/// One generated row: cell values by column label (numbers stay numbers, dates stay dates).
typedef DemoRow = Map<String, Object>;

/// Each page's rows while the app is open, so additions and edits stay when the page is left and reopened.
final _store = <String, List<DemoRow>>{};

/// The rows a page shows and edits: generated once, then kept (and changed) in memory until the app closes.
List<DemoRow> rowsFor(String itemId, PageSpec spec) => _store.putIfAbsent(itemId, () => demoRows(itemId, spec));

/// The page's rows, the same every time for the same item id.
List<DemoRow> demoRows(String itemId, PageSpec spec, {DateTime? now}) {
  final r = math.Random(itemId.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff));
  final at = now ?? DateTime.now();
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
  final idPrefix = spec.first(ColKind.id)?.pool.first ?? 'ID';
  return [
    for (var i = 0; i < spec.rows; i++)
      {
        for (final c in spec.columns)
          c.label: switch (c.kind) {
            ColKind.id => '$idPrefix-${1001 + i}',
            ColKind.pick || ColKind.status => _weighted(r, c.pool),
            ColKind.person => pick(_people),
            ColKind.money => (c.min + r.nextDouble() * r.nextDouble() * (c.max - c.min)).round(),
            ColKind.number || ColKind.percent => (c.min + r.nextDouble() * (c.max - c.min)).round(),
            ColKind.date => at.subtract(Duration(hours: ((r.nextDouble() * r.nextDouble()) * c.back * 24 - (c.ahead > 0 ? r.nextDouble() * c.ahead * 24 : 0)).round())),
          },
      },
  ];
}

/// Earlier choices come up more often (statuses list the common, healthy ones first).
String _weighted(math.Random r, List<String> pool) {
  final weights = [for (var i = 0; i < pool.length; i++) pool.length - i + 1];
  var n = r.nextInt(weights.fold(0, (a, b) => a + b));
  for (var i = 0; i < pool.length; i++) {
    n -= weights[i];
    if (n < 0) return pool[i];
  }
  return pool.last;
}

/// Green for done and healthy, amber for waiting, red for failed or stopped, grey otherwise.
(Color, Color) demoTone(String status) {
  const good = {
    'Approved', 'Received', 'Passed', 'Released', 'Delivered', 'Paid', 'Active', 'Online', 'Completed', 'Healthy', 'Won', 'Settled', 'Matched', 'Resolved',
    'In stock', 'On track', 'Accepted', 'Succeeded', 'Installed', 'Up to date', 'Full', 'Dispensed', 'Profitable', 'Validated', 'Filed', 'Valid', 'Achieved',
    'Converted to PO', 'Within standard', 'Posted', 'Reserved', 'OK', 'Confirmed', 'Ready', 'Strong', 'Comfortable', 'Above target', 'Linked', 'Closed', 'Implemented',
    'Counted', 'Reviewed', 'Dispatched',
  };
  const waiting = {
    'Draft', 'Pending', 'Pending approval', 'In progress', 'Open', 'Scheduled', 'Under review', 'In transit', 'Partially received', 'Due', 'Planned', 'Negotiation',
    'Proposal', 'Qualified', 'Lead', 'Shortlisted', 'Due soon', 'Low stock', 'At risk', 'Retrying', 'Running', 'Investigating', 'Submitted', 'Preparing', 'Technical evaluation',
    'Sent', 'In production', 'Quality check', 'Ordered', 'Ready for FAT', 'Site survey', 'Weak signal', 'Update available', 'Low', 'Refunded', 'Acknowledged',
    'Break-even', 'Expiring soon', 'Retest', 'On hold', 'Awaiting results', 'Corrective action', 'Pending release', 'Over standard', 'Reorder now', 'Renewal due',
    'Watch', 'Tight', 'On target', 'Average', 'Review due', 'Briefed', 'Waiting on customer', 'New', 'Pending count', 'Certificate expiring', 'Degraded', 'Paused',
    'Onboarding', 'Quoted', 'Reworked', 'Variance found', 'Issues found', 'Not linked', 'Scrapped', 'Needs service', 'Under repair', 'In storage',
  };
  const stopped = {
    'Rejected', 'Failed', 'Overdue', 'Cancelled', 'Quarantined', 'Out of stock', 'Offline', 'Lost', 'Disputed', 'Expired', 'Blocked', 'Mismatch', 'Behind', 'Down',
    'Retired', 'Delayed', 'Empty', 'Loss-making', 'Not allowed', 'Missed', 'Update failed', 'Over budget', 'Negative', 'Shortfall', 'Below target', 'Unprofitable',
    'Weak', 'Revoked', 'Discontinued', 'Suppressed', 'Ended',
  };
  if (good.contains(status)) return (const Color(0xFFDDF3EC), const Color(0xFF0B5B4E));
  if (stopped.contains(status)) return (const Color(0xFFF3E3E3), const Color(0xFF8B2E2E));
  if (waiting.contains(status)) return (const Color(0xFFFFF4D6), const Color(0xFF8A5A00));
  return (const Color(0xFFEEF2F1), const Color(0xFF475569));
}

String _cell(Col c, Object? v) {
  if (v == null) return '—';
  final n = NumberFormat.decimalPattern('en_IN');
  return switch (c.kind) {
    ColKind.money => rupees((v as num).round()),
    ColKind.number => '${n.format(v)}${c.unit.isEmpty ? '' : ' ${c.unit}'}',
    ColKind.percent => '$v%',
    ColKind.date => DateFormat('d MMM yyyy').format(v as DateTime),
    _ => '$v',
  };
}

// ================================================================ Page

/// A menu page built from its [PageSpec]: header, numbers, highlights, charts and a working table.
class NavModulePage extends StatefulWidget {
  const NavModulePage({super.key, required this.itemId, required this.spec, this.onSibling});
  final String itemId;
  final PageSpec spec;

  /// Opens another page of the same section (from the chips under the header).
  final void Function(NavItem item)? onSibling;

  @override
  State<NavModulePage> createState() => _NavModulePageState();
}

class _NavModulePageState extends State<NavModulePage> {
  late List<DemoRow> _rows = rowsFor(widget.itemId, widget.spec);
  void _menusChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    OptionStore.instance.addListener(_menusChanged); // dropdown menus edited in Settings or by "Other…"
  }

  @override
  void dispose() {
    OptionStore.instance.removeListener(_menusChanged);
    super.dispose();
  }

  late RecordQuery _q = rememberedQuery('nav:${widget.itemId}');
  bool _all = false;

  /// The record open in the side panel (wide screens), like the order desk.
  DemoRow? _selected;
  bool _split = false;

  /// Opens [row]: in the side panel on wide screens, as its own page on phones.
  Future<void> _open(DemoRow row) async {
    if (_split) return setState(() => _selected = identical(_selected, row) ? null : row);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFFF2F6F5),
        appBar: AppBar(title: Text('${row['ID']}', style: const TextStyle(fontWeight: FontWeight.w600))),
        body: StatefulBuilder(
          builder: (context, refresh) => RowDetail(
            spec: s,
            row: row,
            onEdit: () async {
              await _edit(row);
              refresh(() {});
            },
            onDelete: () async {
              if (await _confirmDelete(row) && context.mounted) Navigator.of(context).pop();
            },
          ),
        ),
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete(DemoRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${row['ID']}?'),
        content: Text('This ${s.entity.toLowerCase()} is removed from the demo data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    setState(() {
      _rows.remove(row);
      if (identical(_selected, row)) {
        _selected = null;
        _panelExpanded = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.entity} deleted.')));
    return true;
  }

  /// What can be filtered and sorted on: every column, by its kind.
  List<FilterField> get _fields => [
    for (final c in s.columns)
      switch (c.kind) {
        ColKind.id => FilterField(c.label, c.label, FilterKind.text),
        ColKind.pick || ColKind.status => FilterField(c.label, c.label, FilterKind.choice, options: OptionStore.instance.options('nav:${widget.itemId}.${c.label}', c.pool)),
        ColKind.person => FilterField(c.label, c.label, FilterKind.choice, options: OptionStore.instance.options('nav:${widget.itemId}.${c.label}', _people)),
        ColKind.money => FilterField(c.label, c.label, FilterKind.number, money: true),
        ColKind.number => FilterField(c.label, c.label, FilterKind.number, unit: c.unit),
        ColKind.percent => FilterField(c.label, c.label, FilterKind.number, unit: '%'),
        ColKind.date => FilterField(c.label, c.label, FilterKind.date),
      },
  ];

  static Object? _read(DemoRow row, String key) => key == modifiedKey ? row['_modified'] : row[key];

  void _setQuery(RecordQuery q) {
    rememberQuery('nav:${widget.itemId}', q);
    setState(() => _q = q);
  }

  PageSpec get s => widget.spec;

  /// Adds a record (new ID after the highest one) or edits [row]; deleting removes it. Numbers and charts follow.
  /// The side panel shows the form (wide screens): for [_formRow], or a new record when it's null.
  bool _formOpen = false;
  DemoRow? _formRow;

  /// The side panel fills the page (its full-screen button); reset whenever the panel closes.
  bool _panelExpanded = false;

  /// Adds a record or edits [row]: in the side panel on wide screens, full screen on phones.
  Future<void> _edit([DemoRow? row]) async {
    if (_split) {
      return setState(() {
        _formOpen = true;
        _formRow = row;
        if (row != null) _selected = row;
      });
    }
    final result = await Navigator.of(context).push<_EditResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => DemoRowForm(spec: s, row: row, pageKey: 'nav:${widget.itemId}')),
    );
    if (result != null && mounted) _apply(result, row);
  }

  /// Saves what the form returned: adds (new ID after the highest), updates, or deletes. Numbers and charts follow.
  void _apply(_EditResult result, DemoRow? row) {
    DemoRow? added;
    setState(() {
      if (result.delete) {
        _rows.remove(row);
        if (identical(_selected, row)) _selected = null;
      } else if (row == null) {
        final prefix = s.first(ColKind.id)?.pool.first ?? 'ID';
        final next = _rows.map((r) => int.tryParse('${r['ID']}'.split('-').last) ?? 0).fold(1000, math.max) + 1;
        added = {...result.row, 'ID': '$prefix-$next', '_modified': DateTime.now()};
        _rows.insert(0, added!);
        if (_split) _selected = added;
      } else {
        row.addAll({...result.row, '_modified': DateTime.now()});
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.delete ? '${s.entity} deleted.' : row == null ? '${s.entity} added.' : 'Saved.'),
    ));
  }

  @override
  void didUpdateWidget(NavModulePage old) {
    super.didUpdateWidget(old);
    // Another page in the same place: its own rows, with the search, filter and sort cleared.
    if (old.itemId != widget.itemId) {
      _rows = rowsFor(widget.itemId, widget.spec);
      _q = rememberedQuery('nav:${widget.itemId}');
      _all = false;
    }
  }

  List<DemoRow> get _shown => applyQuery(_rows, _q, _fields, _read);

  @override
  Widget build(BuildContext context) {
    // Numbers, charts and highlights describe the rows the filters keep.
    final data = _shown;
    final found = navItemById(widget.itemId)!;
    final (section, item) = found;
    final now = DateTime.now();
    final statusCol = s.first(ColKind.status), moneyCol = s.first(ColKind.money), dateCol = s.first(ColKind.date);
    final numCol = s.columns.where((c) => c.kind == ColKind.number || c.kind == ColKind.percent).firstOrNull;
    final pickCol = s.first(ColKind.pick);
    final total = data.length;

    // Numbers, with the change against the 30 days before the last 30.
    (int, int) window(bool Function(DemoRow) where) {
      if (dateCol == null) return (0, 0);
      var cur = 0, prev = 0;
      for (final row in data.where(where)) {
        final d = row[dateCol.label] as DateTime;
        final age = now.difference(d).inDays;
        if (age >= 0 && age < 30) cur++;
        if (age >= 30 && age < 60) prev++;
      }
      return (cur, prev);
    }

    Delta delta((int, int) w, {String caption = 'vs previous 30 days'}) {
      final (cur, prev) = w;
      if (prev == 0) return Delta(cur == 0 ? 'no change' : '+$cur', cur > 0, caption: caption);
      final pct = (cur - prev) * 100 / prev;
      return Delta('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%', pct >= 0, caption: caption);
    }

    final statusCounts = <String, int>{};
    if (statusCol != null) {
      for (final st in statusCol.pool) {
        statusCounts[st] = data.where((r) => r[statusCol.label] == st).length;
      }
    }
    final bad = statusCounts.entries.where((e) => demoTone(e.key).$2 == const Color(0xFF8B2E2E)).fold(0, (a, e) => a + e.value);
    final waiting = statusCounts.entries.where((e) => demoTone(e.key).$2 == const Color(0xFF8A5A00)).fold(0, (a, e) => a + e.value);
    final moneySum = moneyCol == null ? 0 : data.fold<int>(0, (a, r) => a + (r[moneyCol.label] as int));
    final numAvg = numCol == null ? 0.0 : data.fold<int>(0, (a, r) => a + (r[numCol.label] as int)) / math.max(1, total);
    final cards = <HeadlineCard>[
      HeadlineCard(label: 'All ${s.plural}', value: '$total', icon: section.icon, module: '', delta: delta(window((_) => true))),
      if (moneyCol != null)
        HeadlineCard(label: 'Total ${moneyCol.label.toLowerCase()}', value: rupees(moneySum), icon: Icons.payments_outlined, module: '',
            delta: Delta('avg ${rupees(moneySum ~/ math.max(1, total))}', true, caption: 'per ${s.entity.toLowerCase()}')),
      if (numCol != null)
        HeadlineCard(label: 'Average ${numCol.label.toLowerCase()}', value: numCol.kind == ColKind.percent ? '${numAvg.toStringAsFixed(1)}%' : '${NumberFormat.decimalPattern('en_IN').format(numAvg.round())}${numCol.unit.isEmpty ? '' : ' ${numCol.unit}'}',
            icon: Icons.insights_outlined, module: '', delta: Delta('${numCol.min}–${numCol.max}${numCol.kind == ColKind.percent ? '%' : ''}', true, caption: 'usual range')),
      if (statusCol != null)
        HeadlineCard(label: 'Need attention', value: '${bad + waiting}', icon: Icons.flag_outlined, module: '',
            delta: Delta('$bad stopped · $waiting waiting', bad == 0, caption: '${((bad + waiting) * 100 / math.max(1, total)).round()}% of all')),
    ];

    // Weekly series: counts as the line, value (or count) as the columns.
    final future = dateCol != null && dateCol.ahead > dateCol.back / 3;
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final start = future ? monday.subtract(const Duration(days: 7 * 5)) : monday.subtract(const Duration(days: 7 * 11));
    final counts = List<int>.filled(12, 0), values = List<int>.filled(12, 0);
    if (dateCol != null) {
      for (final row in data) {
        final d = row[dateCol.label] as DateTime;
        final i = DateTime(d.year, d.month, d.day).difference(start).inDays ~/ 7;
        if (i < 0 || i >= 12) continue;
        counts[i]++;
        values[i] += moneyCol == null ? 1 : row[moneyCol.label] as int;
      }
    }
    String weekLabel(int i) => DateFormat('d MMM').format(start.add(Duration(days: 7 * i)));

    // Status colours (green done, amber waiting, red stopped); statuses sharing a tone step lighter, 30% apart.
    final seen = <Color, int>{};
    final statusSlices = [
      for (final e in statusCounts.entries)
        () {
          final base = demoTone(e.key).$2;
          final k = seen.update(base, (n) => n + 1, ifAbsent: () => 0);
          return Slice(e.key, e.value, Color.lerp(base, Colors.white, 0.3 * k)!);
        }(),
    ];
    final byPick = <String, int>{};
    if (pickCol != null) {
      for (final row in data) {
        final k = '${row[pickCol.label]}';
        byPick[k] = (byPick[k] ?? 0) + (moneyCol == null ? 1 : row[moneyCol.label] as int);
      }
    }
    final pickSlices = [
      for (final e in (byPick.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6)) Slice(e.key, e.value, chartPalette[0]),
    ];

    // Written highlights.
    final highlights = <String>[
      if (pickSlices.isNotEmpty)
        '${pickSlices.first.label} leads by ${pickCol!.label.toLowerCase()}: ${moneyCol == null ? '${pickSlices.first.count} ${s.plural}' : rupees(pickSlices.first.count)}'
            ' (${(pickSlices.first.count * 100 / math.max(1, pickSlices.fold(0, (a, x) => a + x.count))).round()}% of the top ${pickSlices.length}).',
      if (statusCol != null && statusCounts.isNotEmpty)
        () {
          final top = statusCounts.entries.reduce((a, b) => b.value > a.value ? b : a);
          return 'Most ${s.plural} are ${top.key.toLowerCase()} (${top.value} of $total).';
        }(),
      if (bad > 0) '$bad ${bad == 1 ? s.entity.toLowerCase() : s.plural} need action: they are failed, overdue or stopped.',
      if (moneyCol != null && data.isNotEmpty)
        () {
          final top = data.reduce((a, b) => (b[moneyCol.label] as int) > (a[moneyCol.label] as int) ? b : a);
          return 'The largest is ${top['ID']} at ${rupees(top[moneyCol.label] as int)}.';
        }(),
      if (dateCol != null)
        () {
          final (cur, prev) = window((_) => true);
          return '$cur ${s.plural} in the last 30 days, against $prev in the 30 before.';
        }(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [...globalSearchActions(context), const SizedBox(width: 8)],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // Wide windows keep a side panel for the open record; the list gets the rest.
          _split = box.maxWidth >= 1100;
          final panel = _split && (_selected != null || _formOpen) ? 460.0 : 0.0;
          final w = box.maxWidth - panel;
          final pad = w >= 900 ? 28.0 : 16.0;
          final inner = w - pad * 2;
          final wide = inner >= 1100, medium = inner >= 700;
          const gap = 18.0;
          final chart = DashCard(
            title: future ? '${s.plural[0].toUpperCase()}${s.plural.substring(1)} by week, around today' : '${s.plural[0].toUpperCase()}${s.plural.substring(1)} by week, last 12 weeks',
            subtitle: dateCol == null ? null : 'By ${dateCol.label.toLowerCase()}. ${moneyCol == null ? 'Columns and line: how many.' : 'Columns: ${moneyCol.label.toLowerCase()}. Line: how many.'} Touch for exact numbers.',
            child: ComboChart(bars: values, counts: counts, label: weekLabel, barLabel: moneyCol?.label ?? 'Count', lineLabel: s.plural[0].toUpperCase() + s.plural.substring(1), money: moneyCol != null),
          );
          final donut = DashCard(
            title: 'By ${statusCol?.label.toLowerCase() ?? 'status'}',
            subtitle: 'Tap a status in the table filters to list only those.',
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: DonutChart(slices: statusSlices, centerLabel: s.plural, size: 180, horizontal: false),
            ),
          );
          final breakdown = DashCard(
            title: pickCol == null ? 'Breakdown' : '${moneyCol == null ? 'Count' : moneyCol.label} by ${pickCol.label.toLowerCase()}',
            child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: BarList(slices: pickSlices, format: moneyCol == null ? null : rupees)),
          );
          final notes = DashCard(
            title: 'Highlights',
            subtitle: 'Worked out from the rows below.',
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final h in highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 5), child: Icon(Icons.circle, size: 7, color: brand)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(h, style: const TextStyle(color: Color(0xFF26413B), fontSize: 13.5, height: 1.4))),
                    ]),
                  ),
              ]),
            ),
          );
          Widget row(double h, List<(int, Widget)> parts) => SizedBox(
            height: h,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, (flex, child)) in parts.indexed) ...[if (i > 0) const SizedBox(width: gap), Expanded(flex: flex, child: child)],
            ]),
          );
          Widget fixed(double h, Widget child) => SizedBox(height: h, child: child);

          final list = ListView(
            key: const Key('nav-page-scroll'),
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 104), // room under the last row for the Add button
            children: [
              _Header(section: section, item: item, spec: s, onSibling: widget.onSibling),
              const SizedBox(height: gap),
              EqualRows(columns: wide ? cards.length : medium ? (cards.length == 3 ? 3 : 2) : 1, gap: 14, children: [for (final (i, c) in cards.indexed) HeadlineStatCard(card: c, highlight: i == 0)]),
              const SizedBox(height: gap),
              if (wide) ...[
                row(560, [(2, chart), (1, donut)]),
                const SizedBox(height: gap),
                row(360, [(1, breakdown), (1, notes)]),
              ] else if (medium) ...[
                fixed(460, chart),
                const SizedBox(height: gap),
                row(560, [(1, donut), (1, breakdown)]),
                const SizedBox(height: gap),
                fixed(300, notes),
              ] else ...[
                fixed(440, chart),
                const SizedBox(height: gap),
                fixed(580, donut),
                const SizedBox(height: gap),
                fixed(380, breakdown),
                const SizedBox(height: gap),
                fixed(360, notes),
              ],
              const SizedBox(height: 26),
              _table(context, medium),
            ],
          );
          final withAdd = floatingAdd('Add ${s.entity.toLowerCase()}', () => _edit(), list);
          if (!_split) return withAdd;
          final open = _selected != null && _rows.contains(_selected) ? _selected : null;
          final Widget? panelBody = _formOpen
              ? DemoRowForm(
                  key: ValueKey('form-${_formRow?['ID'] ?? 'new'}'),
                  spec: s,
                  pageKey: 'nav:${widget.itemId}',
                  row: _formRow,
                  onDone: (result) {
                    final row = _formRow;
                    setState(() {
                      _formOpen = false;
                      if (result == null) {
                        // closed: the whole panel goes, details too
                        _selected = null;
                        _panelExpanded = false;
                      }
                    });
                    if (result != null) _apply(result, row);
                  },
                )
              : open == null
              ? null
              : RowDetail(
                  key: ValueKey(open['ID']),
                  spec: s,
                  row: open,
                  onClose: () => setState(() {
                    _selected = null;
                    _panelExpanded = false;
                  }),
                  onEdit: () => _edit(open),
                  onDelete: () => _confirmDelete(open),
                );
          // Full screen: the panel takes the whole page, its content kept to a readable width.
          if (panelBody != null && _panelExpanded) {
            return PanelScope(
              expanded: true,
              onToggle: () => setState(() => _panelExpanded = false),
              child: ColoredBox(
                color: const Color(0xFFF7FAF9),
                child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: panelBody)),
              ),
            );
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: withAdd),
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: panelBody == null ? 0 : 460,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: Color(0xFFF7FAF9), border: Border(left: BorderSide(color: Color(0xFFE1E8E6)))),
              child: panelBody == null
                  ? const SizedBox.shrink()
                  : PanelScope(
                      expanded: false,
                      onToggle: () => setState(() => _panelExpanded = true),
                      child: OverflowBox(alignment: Alignment.centerLeft, minWidth: 460, maxWidth: 460, child: panelBody),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _table(BuildContext context, bool medium) {
    final shown = _shown;
    final visible = _all ? shown : shown.take(12).toList();
    final statusCol = s.first(ColKind.status);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('All ${s.plural}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Tap a row to see it in full, then edit or delete it.', style: TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
        const SizedBox(height: 12),
        FilterBar(
          pageKey: 'nav:${widget.itemId}',
          fields: _fields,
          query: _q,
          onChanged: _setQuery,
          total: _rows.length,
          shown: shown.length,
          count: (draft) => applyQuery(_rows, draft, _fields, _read).length,
          noun: s.plural,
          quickField: statusCol?.label,
          quickCounts: {
            if (statusCol != null)
              for (final st in OptionStore.instance.options('nav:${widget.itemId}.${statusCol.label}', statusCol.pool)) st: _rows.where((r) => r[statusCol.label] == st).length,
          },
        ),
        const SizedBox(height: 10),
      ],
    );
    Widget chip(String st) {
      final (bg, fg) = demoTone(st);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(st, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
    }

    final Widget body;
    if (shown.isEmpty) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Nothing matches. Try another search or filter.', style: TextStyle(color: Color(0xFF5A6C68)))));
    } else if (medium) {
      body = Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE6EEEB))),
        clipBehavior: Clip.antiAlias,
        // At least as wide as the card, so the table fills it; wider tables scroll sideways.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: () {
              final i = s.columns.indexWhere((c) => c.label == _q.sortKey);
              return i < 0 ? null : i;
            }(),
            sortAscending: _q.ascending,
            headingRowColor: const WidgetStatePropertyAll(Color(0xFFF4F8F6)),
            headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF34443F), fontSize: 13),
            columns: [
              for (final (i, c) in s.columns.indexed)
                DataColumn(
                  label: Text(c.label),
                  numeric: c.kind == ColKind.money || c.kind == ColKind.number || c.kind == ColKind.percent,
                  onSort: (_, asc) => _setQuery(_q.copyWith(sortKey: s.columns[i].label, ascending: asc)),
                ),
            ],
            rows: [
              for (final row in visible)
                DataRow(selected: identical(_selected, row), onSelectChanged: (_) => _open(row), cells: [
                  for (final c in s.columns)
                    DataCell(c.kind == ColKind.status ? chip('${row[c.label]}') : Text(_cell(c, row[c.label]), style: TextStyle(fontWeight: c.kind == ColKind.id ? FontWeight.w600 : FontWeight.w500))),
                ]),
            ],
          ),
          ),
        ),
        ),
      );
    } else {
      body = Column(children: [
        for (final row in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE6EEEB))),
              child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(row),
              child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${row['ID']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                  if (statusCol != null) chip('${row[statusCol.label]}'),
                ]),
                const SizedBox(height: 8),
                for (final c in s.columns.where((c) => c.kind != ColKind.id && c.kind != ColKind.status))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      SizedBox(width: 130, child: Text(c.label, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5))),
                      Expanded(child: Text(_cell(c, row[c.label]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                    ]),
                  ),
              ]),
              ),
              ),
            ),
          ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        body,
        if (shown.length > 12) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _all = !_all),
              icon: Icon(_all ? Icons.expand_less : Icons.expand_more),
              label: Text(_all ? 'Show fewer' : 'Show all ${shown.length}'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.section, required this.item, required this.spec, this.onSibling});
  final NavSection section;
  final NavItem item;
  final PageSpec spec;
  final void Function(NavItem)? onSibling;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6EEEB))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Breadcrumb',
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
            const Text('Admin', style: TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
            const Icon(Icons.chevron_right, size: 15, color: Color(0xFF8A9A96)),
            Text('${section.numbered} ${section.label}', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
            const Icon(Icons.chevron_right, size: 15, color: Color(0xFF8A9A96)),
            Text(item.label, style: const TextStyle(color: Color(0xFF0C1C19), fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: const Color(0xFFD8EEE3), borderRadius: BorderRadius.circular(14)),
            child: Icon(section.icon, color: brand, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(item.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(999)),
                  child: const Text('Demo data', style: TextStyle(color: Color(0xFF7F5300), fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(spec.about, style: const TextStyle(color: Color(0xFF34443F), fontSize: 14, height: 1.4)),
              const SizedBox(height: 4),
              Text('Part of ${section.label}: ${section.purpose[0].toLowerCase()}${section.purpose.substring(1)} Made-up records; nothing here is live.',
                  style: const TextStyle(color: Color(0xFF8A9A96), fontSize: 12.5)),
            ]),
          ),
        ]),
        if (onSibling != null) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final other in section.items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(other.label),
                    selected: other.id == item.id,
                    onSelected: other.id == item.id ? null : (_) => onSibling!(other),
                  ),
                ),
            ]),
          ),
        ],
      ],
    ),
  );
}


// ================================================================ Add / edit a record

class _EditResult {
  const _EditResult(this.row, {this.delete = false});
  final DemoRow row;
  final bool delete;
}

/// The add / edit form for one record of a content page, built from the page's columns: a list to choose from for
/// fixed choices and people, a number box (₹ for money, % for percentages) for numbers, a date picker for dates.
class DemoRowForm extends StatefulWidget {
  const DemoRowForm({super.key, required this.spec, this.row, this.onDone, this.pageKey = 'nav:page'});
  final PageSpec spec;

  /// The page the record belongs to ('nav:<item>'): names its dropdown menus.
  final String pageKey;

  /// In a side panel: called with the result (null when closed without saving), instead of leaving a page.
  final void Function(_EditResult? result)? onDone;

  /// The record being edited; null to add one.
  final DemoRow? row;

  @override
  State<DemoRowForm> createState() => _DemoRowFormState();
}

class _DemoRowFormState extends State<DemoRowForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, Object?> _values;
  late final Map<String, TextEditingController> _text;

  PageSpec get s => widget.spec;
  Iterable<Col> get _fields => s.columns.where((c) => c.kind != ColKind.id);

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _values = {
      for (final c in _fields)
        c.label: row?[c.label] ??
            switch (c.kind) {
              ColKind.pick || ColKind.status => c.pool.first,
              ColKind.person => _people.first,
              ColKind.date => DateTime.now(),
              _ => null,
            },
    };
    _text = {
      for (final c in _fields.where((c) => c.kind == ColKind.money || c.kind == ColKind.number || c.kind == ColKind.percent))
        c.label: TextEditingController(text: row?[c.label] == null ? '' : '${row![c.label]}'),
    };
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    _finish(_EditResult({
      for (final c in _fields) c.label: _text.containsKey(c.label) ? int.parse(_text[c.label]!.text.trim()) : _values[c.label]!,
    }));
  }

  void _finish(_EditResult? result) {
    if (widget.onDone != null) return widget.onDone!(result);
    Navigator.of(context).pop(result);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.row!['ID']}?'),
        content: Text('This ${s.entity.toLowerCase()} is removed from the demo data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) _finish(_EditResult(widget.row!, delete: true));
  }

  Widget _field(Col c) {
    final decoration = InputDecoration(labelText: c.label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));
    switch (c.kind) {
      case ColKind.pick || ColKind.status || ColKind.person:
        // The menu with the team's own values, and "Other…" to add one.
        return ChoiceDropdown(
          optionKey: '${widget.pageKey}.${c.label}',
          where: s.plural[0].toUpperCase() + s.plural.substring(1),
          defaults: c.kind == ColKind.person ? _people : c.pool,
          value: '${_values[c.label]}',
          label: c.label,
          decoration: decoration,
          required: true,
          onChanged: (v) => setState(() => _values[c.label] = v),
        );
      case ColKind.date:
        final at = _values[c.label] as DateTime;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: at, firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (picked != null) setState(() => _values[c.label] = picked);
          },
          child: InputDecorator(decoration: decoration.copyWith(suffixIcon: const Icon(Icons.event)), child: Text(DateFormat('d MMM yyyy').format(at))),
        );
      default:
        return TextFormField(
          controller: _text[c.label],
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 16),
          decoration: decoration.copyWith(
            prefixText: c.kind == ColKind.money ? '₹ ' : null,
            suffixText: c.kind == ColKind.percent ? '%' : c.unit.isEmpty ? null : c.unit,
            helperText: c.kind == ColKind.money ? null : 'Usually ${c.min}–${c.max}',
          ),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return 'Enter the ${c.label.toLowerCase()}.';
            if (int.tryParse(value) == null) return 'Enter a whole number.';
            return null;
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.row != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        automaticallyImplyLeading: widget.onDone == null,
        title: Text(editing ? 'Edit ${widget.row!['ID']}' : 'Add ${s.entity.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (editing) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          Padding(
            padding: EdgeInsets.only(right: widget.onDone == null ? 12 : 4),
            child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: Text(editing ? 'Save' : 'Add')),
          ),
          // In the side panel: close (without saving) at the right end; it closes the whole panel.
          ?panelExpandButton(context),
          if (widget.onDone != null) ...[IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => _finish(null)), const SizedBox(width: 8)],
        ],
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    '${s.about} ${editing ? 'Changes' : 'New ${s.plural}'} stay while the app is open (demo data).',
                    style: const TextStyle(color: Color(0xFF26413B), fontSize: 13.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6EEEB))),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final two = box.maxWidth >= 560;
                      final fields = _fields.toList();
                      return Wrap(
                        spacing: 14,
                        runSpacing: 16,
                        children: [for (final c in fields) SizedBox(width: two ? (box.maxWidth - 14) / 2 : box.maxWidth, child: _field(c))],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(onPressed: _save, icon: Icon(editing ? Icons.check : Icons.add), label: Text(editing ? 'Save changes' : 'Add ${s.entity.toLowerCase()}')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ================================================================ One record, in full

/// A record of a content page in full: its ID and status, every field with its value, and Edit / Delete. Shown in the
/// side panel on wide screens (with a close button) and as its own page on phones.
class RowDetail extends StatelessWidget {
  const RowDetail({super.key, required this.spec, required this.row, required this.onEdit, required this.onDelete, this.onClose});
  final PageSpec spec;
  final DemoRow row;
  final VoidCallback onEdit, onDelete;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final statusCol = spec.first(ColKind.status);
    final status = statusCol == null ? null : '${row[statusCol.label]}';
    final modified = row['_modified'] as DateTime?;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(children: [
          Expanded(child: Text('${row['ID']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)))),
          ?panelExpandButton(context),
          if (onClose != null) IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: demoTone(status).$1, borderRadius: BorderRadius.circular(999)),
              child: Text(status, style: TextStyle(color: demoTone(status).$2, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          Text(spec.entity, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
          if (modified != null) Text('· changed ${DateFormat('d MMM, h:mm a').format(modified)}', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'))),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB3261E), side: const BorderSide(color: Color(0xFFF0B8B3))),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE6EEEB))),
          child: Column(children: [
            for (final (i, c) in spec.columns.where((c) => c.kind != ColKind.id && c.kind != ColKind.status).indexed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEDF2F0)))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 150, child: Text(c.label, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13))),
                  Expanded(child: SelectableText(_cell(c, row[c.label]), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Demo data: changes stay while the app is open.', style: TextStyle(color: Color(0xFF8A9A96), fontSize: 12)),
      ],
    );
  }
}
