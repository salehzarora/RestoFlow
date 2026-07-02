import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The dashboard's effective tenant context (sprint).
///
/// `create_organization` mints the owner an ORG-WIDE membership
/// (`restaurant_id`/`branch_id` NULL), and `get_my_context` echoes those nulls
/// — but restaurant-scoped surfaces (menu management, printer/staff creation)
/// need a CONCRETE restaurant + branch, and money-bearing writes need the
/// org's REAL currency instead of a USD placeholder. [resolveTenantContext]
/// fills both from `public.list_org_structure` (manager+, GUC-free).
class ResolvedTenantContext {
  const ResolvedTenantContext({required this.membership, this.currencyCode});

  /// The membership, with restaurant/branch filled in from the org structure
  /// when the original was org- or restaurant-wide. Scope-limited memberships
  /// pass through unchanged (their scope is already concrete).
  final MembershipContext membership;

  /// The scope's effective ISO-4217 currency (`restaurants.currency_override`
  /// falling back to `organizations.default_currency`). Null when the
  /// structure read failed — money-bearing surfaces must then fail closed
  /// (an honest unavailable/error state), never assume a currency.
  final String? currencyCode;
}

/// Resolves the effective context for [membership] via
/// `public.list_org_structure`. NEVER throws: any failure (denied, transport,
/// malformed) returns the original membership with a null currency — the
/// dependent surfaces stay honest instead of blocking sign-in.
Future<ResolvedTenantContext> resolveTenantContext({
  required SyncRpcTransport transport,
  required MembershipContext membership,
}) async {
  final Object? raw;
  try {
    raw = await transport.invoke('list_org_structure', <String, dynamic>{
      'p_organization_id': membership.organizationId,
    });
  } catch (_) {
    return ResolvedTenantContext(membership: membership);
  }
  if (raw is! Map || raw['ok'] != true) {
    return ResolvedTenantContext(membership: membership);
  }

  final organization = raw['organization'];
  final orgCurrency = organization is Map
      ? _text(organization['default_currency'])
      : null;
  final restaurants = raw['restaurants'];
  if (restaurants is! List) {
    return ResolvedTenantContext(
      membership: membership,
      currencyCode: orgCurrency,
    );
  }

  // Pick the membership's restaurant when it has one, else the first (the
  // backend orders deterministically by created_at; onboarding always creates
  // exactly one restaurant + branch, so the pilot pick is unambiguous).
  Map<String, dynamic>? restaurant;
  for (final row in restaurants.whereType<Map>()) {
    final id = _text(row['id']);
    if (id == null) continue;
    if (membership.restaurantId == null || id == membership.restaurantId) {
      restaurant = Map<String, dynamic>.from(row);
      break;
    }
  }
  if (restaurant == null) {
    return ResolvedTenantContext(
      membership: membership,
      currencyCode: orgCurrency,
    );
  }
  final currency = _text(restaurant['currency_override']) ?? orgCurrency;

  Map<String, dynamic>? branch;
  final branches = restaurant['branches'];
  if (branches is List) {
    for (final row in branches.whereType<Map>()) {
      final id = _text(row['id']);
      if (id == null) continue;
      if (membership.branchId == null || id == membership.branchId) {
        branch = Map<String, dynamic>.from(row);
        break;
      }
    }
  }

  return ResolvedTenantContext(
    membership: MembershipContext(
      id: membership.id,
      organizationId: membership.organizationId,
      organizationName: membership.organizationName,
      restaurantId: _text(restaurant['id']) ?? membership.restaurantId,
      restaurantName: _text(restaurant['name']) ?? membership.restaurantName,
      branchId: branch == null ? membership.branchId : _text(branch['id']),
      branchName: branch == null
          ? membership.branchName
          : _text(branch['name']),
      role: membership.role,
      status: membership.status,
    ),
    currencyCode: currency,
  );
}

String? _text(Object? value) {
  if (value == null) return null;
  final s = value.toString();
  return s.isEmpty ? null : s;
}

/// Resolves the tenant context once, showing a brief spinner, then builds the
/// shell. A null [transport] (tests / no session transport) passes the
/// membership through unresolved.
class TenantContextLoader extends StatefulWidget {
  const TenantContextLoader({
    required this.membership,
    required this.transport,
    required this.builder,
    super.key,
  });

  final MembershipContext membership;
  final SyncRpcTransport? transport;
  final Widget Function(BuildContext context, ResolvedTenantContext resolved)
  builder;

  @override
  State<TenantContextLoader> createState() => _TenantContextLoaderState();
}

class _TenantContextLoaderState extends State<TenantContextLoader> {
  late final Future<ResolvedTenantContext> _future;

  @override
  void initState() {
    super.initState();
    final transport = widget.transport;
    _future = transport == null
        ? Future.value(ResolvedTenantContext(membership: widget.membership))
        : resolveTenantContext(
            transport: transport,
            membership: widget.membership,
          );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResolvedTenantContext>(
      future: _future,
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.builder(context, resolved);
      },
    );
  }
}
