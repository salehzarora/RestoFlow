/// The Activity-log data SEAM (AUDIT-LOG-DASHBOARD-001).
///
/// The single place the Dashboard audit-timeline data is sourced. The demo
/// implementation returns a deterministic in-memory dataset (no Supabase, no
/// backend); the real implementation ([RealAuditLogRepository]) reads the
/// `public.owner_audit_events` RPC over the same authenticated transport the
/// rest of the real dashboard uses. Same return types, so the UI never branches
/// on the source. READ-ONLY: there is no write/update/delete method here — the
/// audit log is immutable (D-013) and this feature only lists it.
library;

import 'audit_log_models.dart';

/// Loads paginated pages of audit events for a scope. There is deliberately NO
/// mutation method — the timeline is strictly read-only.
abstract class AuditLogRepository {
  /// A page of events for [query], continuing from [cursor] (null = first page).
  /// Implementations may fail (network, auth, RLS) — surfaced as an error.
  Future<AuditPage> loadEvents(AuditQuery query, {String? cursor});
}

/// A failure loading the audit timeline.
class AuditLogException implements Exception {
  const AuditLogException(this.message);

  final String message;

  @override
  String toString() => 'AuditLogException: $message';
}

/// One demo audit event + how many days ago it happened (for range filtering).
class DemoAuditEvent {
  const DemoAuditEvent({
    required this.daysAgo,
    required this.minuteOfDay,
    required this.event,
    this.branchId,
    this.actorId,
  });

  final int daysAgo;

  /// STATIC-C548C0E-DEMO-ACTIVITY-ORDER-01 — minutes since midnight on that
  /// day, so two events on one day have a total order of their own.
  ///
  /// REQUIRED, deliberately. The timeline used to come out in whatever order
  /// the fixtures happened to be declared in, which held only until someone
  /// appended a row — and I did exactly that, putting 15:40 and 15:05 after
  /// 09:40. A field that must be supplied makes "when did this happen" part of
  /// writing a fixture rather than something to notice afterwards.
  ///
  /// It is NOT parsed from [AuditEvent.occurredAtLabel]: that is display text,
  /// localizable and free-form ("Yesterday 23:10"), and sorting a timeline by
  /// scraping its own labels would be brittle in exactly the way this defect
  /// already proved.
  final int minuteOfDay;

  final AuditEvent event;

  /// STATIC-97CDEE8-DEMO-ACTIVITY-01 — the identities the demo timeline filters
  /// on, matching the ids [DemoAuditFilterOptionsRepository] offers.
  ///
  /// They live on the demo WRAPPER, not on [AuditEvent]: that type is the real
  /// transport shape, where the server has already applied the filter and sends
  /// back names for display only. Adding ids there would mean inventing a
  /// contract the real RPC does not have.
  ///
  /// Null [branchId] is an ORG-level event — a membership grant, a menu edit —
  /// which belongs to no branch and is therefore excluded by any branch filter,
  /// exactly as a branch-scoped server query would exclude it.
  final String? branchId;

  /// The acting staff member's demo `employee_profile_id`.
  final String? actorId;
}

/// Serves the timeline from a deterministic in-memory dataset — honest demo
/// data, no backend. Filters/paginates in memory so the UI behaves exactly as
/// it will against the real RPC.
class DemoAuditLogRepository implements AuditLogRepository {
  DemoAuditLogRepository({
    List<DemoAuditEvent>? events,
    this.failureMessage,
    this.pageSize = 25,
    this.currencyCode = 'ILS',
  }) : _events = events ?? demoAuditEvents();

  final List<DemoAuditEvent> _events;

  /// When non-null, the load throws an [AuditLogException] (drives the error
  /// state in tests).
  final String? failureMessage;

  /// How many rows a page holds (so tests can exercise "load more").
  final int pageSize;
  final String currencyCode;

  @override
  Future<AuditPage> loadEvents(AuditQuery query, {String? cursor}) async {
    final message = failureMessage;
    if (message != null) throw AuditLogException(message);

    // STATIC-C548C0E-DEMO-ACTIVITY-ORDER-01 — FILTER, then SORT, then paginate,
    // in that order.
    //
    // This used to preserve source order and paginate it, so the timeline was
    // only newest-first for as long as the fixture list happened to be written
    // that way. It stopped being: appending the Harbor rows put 15:40 and 15:05
    // after 09:40, and with a small page size the newest events could land on a
    // LATER page than older ones. Sorting each page after slicing would look
    // right on page one and still be wrong across the boundary, which is why
    // the whole matched set is ordered before anything is taken from it.
    final matched = <(int, DemoAuditEvent)>[];
    for (var i = 0; i < _events.length; i++) {
      if (_matches(_events[i], query)) matched.add((i, _events[i]));
    }
    matched.sort(_newestFirst);
    final ordered = [for (final (_, e) in matched) e];
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final slice = ordered.skip(offset).take(pageSize).toList();
    final consumed = offset + slice.length;
    final hasMore = consumed < ordered.length;
    return AuditPage(
      events: slice.map((e) => e.event).toList(growable: false),
      hasMore: hasMore,
      nextCursor: hasMore ? consumed.toString() : null,
      currencyCode: currencyCode,
    );
  }

  bool _matches(DemoAuditEvent e, AuditQuery q) {
    final within = switch (q.range) {
      AuditRange.today => e.daysAgo == 0,
      AuditRange.yesterday => e.daysAgo == 1,
      AuditRange.last7 => e.daysAgo >= 0 && e.daysAgo <= 6,
      AuditRange.last30 => e.daysAgo >= 0 && e.daysAgo <= 29,
    };
    if (!within) return false;
    final cat = q.category.wire;
    if (cat != null && e.event.category != cat) return false;
    if (q.sensitiveOnly && !_isSensitive(e.event.action)) return false;
    // STATIC-97CDEE8-DEMO-ACTIVITY-01 — the branch and actor filters were
    // simply not applied here. The control offered them, the effective query
    // carried them and the controller passed them in, and the demo timeline
    // then returned other branches' and other people's events anyway: a filter
    // that visibly did nothing.
    //
    // Matched on IDS. The event carries display names too, and two branches or
    // two staff members may share one; a name is what to render, never what to
    // compare.
    final branch = q.branch;
    if (branch != null && e.branchId != branch.branchId) return false;
    final actor = q.actor;
    if (actor != null && e.actorId != actor.employeeProfileId) return false;
    return true;
  }

  /// Newest first: fewer days ago wins, then later in the day wins.
  ///
  /// The source index is the tie-break, and it is carried explicitly because
  /// `List.sort` is NOT stable in Dart — two events at the same minute would
  /// otherwise come back in an order that is merely whatever the sort happened
  /// to do. A demo dataset nobody can predict is a demo dataset nobody can
  /// write a test against.
  static int _newestFirst((int, DemoAuditEvent) a, (int, DemoAuditEvent) b) {
    final byDay = a.$2.daysAgo.compareTo(b.$2.daysAgo);
    if (byDay != 0) return byDay;
    final byMinute = b.$2.minuteOfDay.compareTo(a.$2.minuteOfDay);
    if (byMinute != 0) return byMinute;
    return a.$1.compareTo(b.$1);
  }

  static bool _isSensitive(String action) =>
      action.endsWith('_denied') ||
      action.startsWith('order.void') ||
      action.startsWith('order.discount') ||
      action.startsWith('staff.capabilities') ||
      action == 'staff.pin_set' ||
      action.startsWith('membership.') ||
      action.startsWith('employee.revok') ||
      action.startsWith('device.revok') ||
      action.startsWith('shift.') ||
      action.startsWith('cash_drawer.') ||
      action.startsWith('payment.');
}

/// STATIC-97CDEE8-DEMO-ACTIVITY-01 — the demo identities, shared by the option
/// source and the timeline so a selection can actually match an event. Stable
/// constants, never generated: a demo dataset that reshuffles its own ids
/// cannot be filtered, and could not be reasoned about in a test.
const demoBranchDowntown = 'demo-branch-downtown';
const demoBranchHarbor = 'demo-branch-harbor';
const demoActorAmira = 'demo-staff-amira';
const demoActorSami = 'demo-staff-sami';
const demoActorNadia = 'demo-staff-nadia';

/// The standard demo timeline (ILS): a spread of the real operational events —
/// a void (with reason), a discount, a permission change, an access grant, a
/// device removal, a shift close, plus a denied attempt and a generic/unmapped
/// event — across today / yesterday so the filters + detail have data. Payloads
/// mirror the REAL canonical shapes so the presentation mapper behaves honestly.
List<DemoAuditEvent> demoAuditEvents() => [
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 845,
    branchId: demoBranchDowntown,
    actorId: demoActorAmira,
    event: const AuditEvent(
      eventId: 'demo-ae-1',
      action: 'order.voided',
      category: 'voids',
      occurredAtLabel: '14:05',
      actorName: 'Amira',
      restaurantName: 'RestoFlow',
      branchName: 'Downtown',
      deviceLabel: 'POS-1',
      reason: 'Wrong table',
      oldValues: {'status': 'submitted'},
      newValues: {'status': 'voided', 'voided_item_count': 2},
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 800,
    branchId: demoBranchDowntown,
    actorId: demoActorAmira,
    event: const AuditEvent(
      eventId: 'demo-ae-2',
      action: 'order.discount_applied',
      category: 'discounts',
      occurredAtLabel: '13:20',
      actorName: 'Amira',
      restaurantName: 'RestoFlow',
      branchName: 'Downtown',
      deviceLabel: 'POS-1',
      oldValues: {'discount_total_minor': 0, 'grand_total_minor': 8400},
      newValues: {
        'discount_type': 'percent',
        'value': '10',
        'discount_total_minor': 840,
        'grand_total_minor': 7560,
      },
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 660,
    actorId: demoActorSami,
    event: const AuditEvent(
      eventId: 'demo-ae-3',
      action: 'staff.capabilities_updated',
      category: 'staff',
      occurredAtLabel: '11:00',
      actorName: 'Sami',
      restaurantName: 'RestoFlow',
      oldValues: {
        'capabilities': {
          'apply_discount': true,
          'void_order': true,
          'close_shift': true,
        },
      },
      newValues: {
        'capabilities': {
          'apply_discount': true,
          'void_order': false,
          'close_shift': true,
        },
      },
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 615,
    actorId: demoActorSami,
    event: const AuditEvent(
      eventId: 'demo-ae-4',
      action: 'membership.granted',
      category: 'access',
      occurredAtLabel: '10:15',
      actorName: 'Sami',
      restaurantName: 'RestoFlow',
      newValues: {'role': 'cashier'},
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 580,
    branchId: demoBranchDowntown,
    actorId: demoActorNadia,
    event: const AuditEvent(
      eventId: 'demo-ae-5',
      action: 'order.void_denied',
      category: 'voids',
      occurredAtLabel: '09:40',
      actorName: 'Nadia',
      restaurantName: 'RestoFlow',
      branchName: 'Downtown',
      deviceLabel: 'POS-1',
      reason: 'No manager approval',
      newValues: {'attempted_action': 'void_order', 'role': 'cashier'},
    ),
  ),
  DemoAuditEvent(
    daysAgo: 1,
    minuteOfDay: 1390,
    branchId: demoBranchDowntown,
    actorId: demoActorAmira,
    event: const AuditEvent(
      eventId: 'demo-ae-6',
      action: 'shift.closed',
      category: 'shifts',
      occurredAtLabel: 'Yesterday 23:10',
      actorName: 'Amira',
      restaurantName: 'RestoFlow',
      branchName: 'Downtown',
      deviceLabel: 'POS-1',
      newValues: {'status': 'closed'},
    ),
  ),
  DemoAuditEvent(
    daysAgo: 1,
    minuteOfDay: 1110,
    branchId: demoBranchDowntown,
    actorId: demoActorSami,
    event: const AuditEvent(
      eventId: 'demo-ae-7',
      action: 'device.revoked',
      category: 'devices',
      occurredAtLabel: 'Yesterday 18:30',
      actorName: 'Sami',
      restaurantName: 'RestoFlow',
      branchName: 'Downtown',
    ),
  ),
  DemoAuditEvent(
    daysAgo: 1,
    minuteOfDay: 960,
    actorId: demoActorSami,
    event: const AuditEvent(
      eventId: 'demo-ae-8',
      action: 'menu.menu_item.updated',
      category: 'menu',
      occurredAtLabel: 'Yesterday 16:00',
      actorName: 'Sami',
      restaurantName: 'RestoFlow',
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 940,
    branchId: demoBranchHarbor,
    actorId: demoActorAmira,
    event: const AuditEvent(
      eventId: 'demo-ae-9',
      action: 'order.voided',
      category: 'voids',
      occurredAtLabel: '15:40',
      actorName: 'Amira',
      restaurantName: 'RestoFlow',
      branchName: 'Harbor',
      deviceLabel: 'POS-2',
      reason: 'Customer left',
      oldValues: {'status': 'submitted'},
      newValues: {'status': 'voided', 'voided_item_count': 1},
    ),
  ),
  DemoAuditEvent(
    daysAgo: 0,
    minuteOfDay: 905,
    branchId: demoBranchHarbor,
    actorId: demoActorSami,
    event: const AuditEvent(
      eventId: 'demo-ae-10',
      action: 'shift.closed',
      category: 'shifts',
      occurredAtLabel: '15:05',
      actorName: 'Sami',
      restaurantName: 'RestoFlow',
      branchName: 'Harbor',
      deviceLabel: 'POS-2',
      newValues: {'status': 'closed'},
    ),
  ),
];
