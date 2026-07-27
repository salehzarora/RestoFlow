import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PRINT-BRANDING-LOGO-001 — resolves a TRANSIENT signed URL for the current
/// restaurant logo (enabled + present), or null (missing/disabled/failure ->
/// the Dashboard order reprint renders text-only). The URL is never persisted.
typedef ReceiptLogoUrlResolver = Future<String?> Function();

/// Null by default (demo / unconfigured). Overridden in the dashboard shell with
/// a resolver built from the branding repository + storage.
final receiptLogoUrlResolverProvider = Provider<ReceiptLogoUrlResolver?>(
  (ref) => null,
);
