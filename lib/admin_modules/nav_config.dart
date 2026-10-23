import 'package:flutter/material.dart';

// The admin console's navigation: 12 numbered sections, each with its submenu. One typed list, used by the sidebar,
// the folded icon rail and the phone drawer. Every item has a stable id and says what it opens: one of the app's
// pages, an admin module (optionally filtered to a status), or, where nothing is built yet, a labelled
// demonstration page.

/// The app's own pages a menu item can open.
enum AppPage { overview, analytics, orders, refunds, settings }

sealed class NavTarget {
  const NavTarget();
}

class PageTarget extends NavTarget {
  const PageTarget(this.page);
  final AppPage page;
}

class ModuleTarget extends NavTarget {
  const ModuleTarget(this.module, {this.status});
  final String module;
  final String? status;
}

/// A screen of its own that isn't a module or one of the app's pages (the Site & app builder, Competitor comparison).
class ScreenTarget extends NavTarget {
  const ScreenTarget(this.screen);
  final String screen;
}

/// Not built yet: opens the demonstration page for the item.
class DemoTarget extends NavTarget {
  const DemoTarget();
}

class NavItem {
  const NavItem(this.id, this.label, [this.target = const DemoTarget()]);
  final String id;
  final String label;
  final NavTarget target;
}

class NavSection {
  const NavSection({required this.id, required this.number, required this.label, required this.icon, required this.purpose, required this.items});
  final String id;
  final int number;
  final String label;
  final IconData icon;

  /// What the section is responsible for (shown on its demonstration pages).
  final String purpose;
  final List<NavItem> items;

  String get numbered => number.toString().padLeft(2, '0');
}

const navSections = <NavSection>[
  NavSection(
    id: 'executive', number: 1, label: 'Executive Command Centre', icon: Icons.space_dashboard_outlined,
    purpose: 'Consolidates cross-functional performance and exceptions.',
    items: [
      NavItem('founder-overview', 'Founder Overview', PageTarget(AppPage.overview)),
      NavItem('business-health', 'Business Health & KPIs', PageTarget(AppPage.analytics)),
      NavItem('priority-exceptions', 'Priority Exceptions'),
      NavItem('decisions-approvals', 'Decisions & Approvals'),
      NavItem('targets-forecasts', 'Targets & Forecasts'),
      NavItem('competitor-comparison', 'Competitor Comparison', ScreenTarget('competitors')),
    ],
  ),
  NavSection(
    id: 'product', number: 2, label: 'Product & Master Data', icon: Icons.inventory_2_outlined,
    purpose: 'Defines the products, SKUs and configuration.',
    items: [
      NavItem('product-catalogue', 'Product Catalogue', ModuleTarget('products')),
      NavItem('sku-variants', 'SKU & Variants'),
      NavItem('bom-packaging', 'BOM & Packaging Configuration'),
      NavItem('product-specs', 'Product Specifications & Revisions'),
      NavItem('pricing-tax', 'Pricing & Tax Rules'),
      NavItem('suppliers-partners', 'Suppliers & Partners'),
      NavItem('warehouses-locations', 'Warehouses & Locations'),
    ],
  ),
  NavSection(
    id: 'procurement', number: 3, label: 'Procurement, OEM & Packaging', icon: Icons.precision_manufacturing_outlined,
    purpose: 'Manages sourcing, manufacturing and packing.',
    items: [
      NavItem('purchase-requests', 'Purchase Requests'),
      NavItem('supplier-quotations', 'Supplier Quotations'),
      NavItem('purchase-orders', 'Purchase Orders'),
      NavItem('oem-planning', 'OEM Production Planning'),
      NavItem('oem-orders', 'OEM Production Orders'),
      NavItem('goods-receipt', 'Goods Receipt'),
      NavItem('packaging-materials', 'Packaging Materials & Vendors'),
      NavItem('packing-work-orders', 'Packing Work Orders'),
      NavItem('material-consumption', 'Material Consumption'),
      NavItem('wastage-rework', 'Wastage & Rework'),
    ],
  ),
  NavSection(
    id: 'quality', number: 4, label: 'Quality & Product Governance', icon: Icons.verified_outlined,
    purpose: 'Manages inspection, testing and release.',
    items: [
      NavItem('incoming-qc', 'Incoming Quality Control'),
      NavItem('in-process-qc', 'In-process Quality Control'),
      NavItem('finished-goods-qc', 'Finished Goods Quality Control'),
      NavItem('batch-release', 'Batch Release & Quarantine'),
      NavItem('lab-reports', 'Testing & Lab Reports'),
      NavItem('claims-evidence', 'Claims & Evidence'),
      NavItem('incidents-capa', 'Incidents & Corrective Actions'),
      NavItem('change-control', 'Change Control'),
    ],
  ),
  NavSection(
    id: 'inventory', number: 5, label: 'Inventory & Logistics', icon: Icons.warehouse_outlined,
    purpose: 'Manages warehouse stock, dispatch and delivery.',
    items: [
      NavItem('stock-overview', 'Stock Overview'),
      NavItem('batch-ledger', 'Batch & Location Ledger'),
      NavItem('stock-reservations', 'Stock Reservations'),
      NavItem('transfers-counts', 'Transfers & Cycle Counts'),
      NavItem('reorder-planning', 'Reorder Planning'),
      NavItem('courier-tracking', 'Courier & Delivery Tracking', ModuleTarget('partners')),
      NavItem('returns-reverse', 'Returns & Reverse Logistics', PageTarget(AppPage.refunds)),
    ],
  ),
  NavSection(
    id: 'vending', number: 6, label: 'Vending Machine Operations', icon: Icons.local_convenience_store_outlined,
    purpose: 'Manages physical vending assets, device connectivity, vending transactions, refills and service.',
    items: [
      NavItem('vending-command', 'Vending Command Centre'),
      NavItem('machine-register', 'Machine Register & Asset Passport'),
      NavItem('vending-oem', 'OEM Procurement Tracker'),
      NavItem('vending-fat', 'Factory Acceptance Testing (FAT)'),
      NavItem('vending-deployment', 'Deployment & Installation'),
      NavItem('vending-connectivity', 'Connectivity & Device Health'),
      NavItem('vending-firmware', 'Machine Configuration & Firmware'),
      NavItem('vending-slots', 'Product Slots & Live Stock'),
      NavItem('vending-transactions', 'Sales & Vend Transactions'),
      NavItem('vending-payments', 'Payments & Settlement'),
      NavItem('vending-refill', 'Refill & Route Planning'),
      NavItem('vending-service', 'Maintenance & Service Desk'),
      NavItem('vending-alerts', 'Machine Alerts & Incident Logs'),
      NavItem('vending-locations', 'Location & Partner Management'),
      NavItem('vending-revenue-share', 'Revenue Share & Reconciliation'),
      NavItem('vending-profitability', 'Machine Profitability'),
      NavItem('vending-warranty', 'Warranty & AMC'),
      NavItem('vending-retirement', 'Retirement & Redeployment'),
    ],
  ),
  NavSection(
    id: 'sales', number: 7, label: 'Sales & Business Growth', icon: Icons.trending_up,
    purpose: 'Manages commercial channels, customers and partnerships.',
    items: [
      NavItem('crm-pipeline', 'CRM & Sales Pipeline'),
      NavItem('b2b-sales', 'B2B & Institutional Sales'),
      NavItem('b2g-tenders', 'B2G & Tender Pipeline'),
      NavItem('d2c-orders', 'D2C & Website Orders', PageTarget(AppPage.orders)),
      NavItem('marketplace-sales', 'Marketplace Sales'),
      NavItem('franchisees', 'Franchisees'),
      NavItem('consumer-subscriptions', 'Consumer Subscriptions', ModuleTarget('subscriptions')),
      NavItem('institutional-contracts', 'Institutional Supply Contracts'),
      NavItem('premium-offerings', 'Premium Offerings', ModuleTarget('plans')),
    ],
  ),
  NavSection(
    id: 'finance', number: 8, label: 'Finance & Unit Economics', icon: Icons.account_balance_outlined,
    purpose: 'Reconciles the financial consequences of all business activities.',
    items: [
      NavItem('revenue-reconciliation', 'Revenue Reconciliation'),
      NavItem('receivables', 'Customer Receivables'),
      NavItem('payables', 'Supplier Payables'),
      NavItem('gateway-settlements', 'Payment Gateway Settlements'),
      NavItem('marketplace-settlements', 'Marketplace Settlements'),
      NavItem('vending-settlements', 'Vending Settlements'),
      NavItem('product-costing', 'Product Costing'),
      NavItem('channel-contribution', 'Channel & Machine Contribution'),
      NavItem('expenses-budgets', 'Expenses & Budgets'),
      NavItem('cash-flow', 'Cash Flow Forecast'),
      NavItem('inventory-valuation', 'Inventory Valuation'),
      NavItem('compliance-documents', 'Compliance Documents'),
    ],
  ),
  NavSection(
    id: 'website', number: 9, label: 'Website, App & Content', icon: Icons.web_outlined,
    purpose: 'Manages published digital experiences.',
    items: [
      NavItem('site-builder', 'Site & App Builder', ScreenTarget('builder')),
      NavItem('website-cms', 'Website CMS', ModuleTarget('pages')),
      NavItem('app-content', 'App Content & Settings', ModuleTarget('settings')),
      NavItem('banners-offers', 'Banners, Offers & Coupons', ModuleTarget('banners')),
      NavItem('blogs-education', 'Blogs & Education Hub', ModuleTarget('articles')),
      NavItem('store-locations', 'Store Locations', ModuleTarget('stores')),
      NavItem('media-library', 'Media Library', ModuleTarget('media')),
      NavItem('publishing-queue', 'Reviews & Publishing Queue', ModuleTarget('articles', status: 'Draft')),
      NavItem('release-history', 'Release History', ModuleTarget('appUpdates')),
    ],
  ),
  NavSection(
    id: 'marketing', number: 10, label: 'Marketing & Customer Experience', icon: Icons.campaign_outlined,
    purpose: 'Manages campaigns, support and retention.',
    items: [
      NavItem('campaign-calendar', 'Campaign Calendar'),
      NavItem('social-creators', 'Social Media & Creator Programs'),
      NavItem('customer-segments', 'Customer Segments', ModuleTarget('members')),
      NavItem('acquisition-conversion', 'Acquisition & Conversion'),
      NavItem('campaign-attribution', 'Campaign Attribution'),
      NavItem('customer-support', 'Customer Support'),
      NavItem('complaints-feedback', 'Complaints & Feedback'),
      NavItem('reviews-surveys', 'Reviews & Surveys', ModuleTarget('ratings')),
      NavItem('retention', 'Retention & Repeat Purchase'),
    ],
  ),
  NavSection(
    id: 'people', number: 11, label: 'People, Governance & Reports', icon: Icons.groups_outlined,
    purpose: 'Manages organisational controls and reporting.',
    items: [
      NavItem('team-directory', 'Team Directory', ModuleTarget('staff')),
      NavItem('roles-permissions', 'Roles & Permissions'),
      NavItem('approval-policies', 'Approval Policies'),
      NavItem('sops-documents', 'SOPs & Documents'),
      NavItem('kpi-catalogue', 'KPI Catalogue'),
      NavItem('executive-reports', 'Executive Reports'),
      NavItem('operations-reports', 'Operations & Quality Reports'),
      NavItem('sales-reports', 'Sales & Marketing Reports'),
      NavItem('finance-reports', 'Finance Reports'),
      NavItem('data-quality', 'Data Quality & Reconciliation'),
      NavItem('clickup-links', 'ClickUp Links'),
    ],
  ),
  NavSection(
    id: 'technology', number: 12, label: 'Technology, IAM & Integrations', icon: Icons.hub_outlined,
    purpose: 'Manages technical infrastructure, identities and system integrations.',
    items: [
      NavItem('integration-registry', 'Integration Registry', ModuleTarget('credentials')),
      NavItem('device-registry', 'Device Registry & Certificates'),
      NavItem('api-webhook-health', 'API & Webhook Health'),
      NavItem('sync-failures', 'Sync Failures & Retries'),
      NavItem('notification-rules', 'Notification Rules'),
      NavItem('audit-logs', 'Audit Logs', ModuleTarget('audit')),
      NavItem('security-events', 'Security Events'),
      NavItem('access-reviews', 'User Access Reviews'),
      NavItem('import-export', 'Import & Export Jobs'),
      NavItem('backup-recovery', 'Backup & Recovery'),
      NavItem('system-configuration', 'System Configuration', PageTarget(AppPage.settings)),
    ],
  ),
];

/// The section and item with this id.
(NavSection, NavItem)? navItemById(String id) {
  for (final s in navSections) {
    for (final i in s.items) {
      if (i.id == id) return (s, i);
    }
  }
  return null;
}

/// The first item that opens [module], for highlighting when a module was opened from elsewhere.
NavItem? navItemForModule(String module) {
  for (final s in navSections) {
    for (final i in s.items) {
      if (i.target case ModuleTarget(module: final m) when m == module) return i;
    }
  }
  return null;
}

NavItem? navItemForPage(AppPage page) {
  for (final s in navSections) {
    for (final i in s.items) {
      if (i.target case PageTarget(page: final p) when p == page) return i;
    }
  }
  return null;
}

NavSection? navSectionOf(String itemId) => navItemById(itemId)?.$1;
