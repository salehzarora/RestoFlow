/// ORDER-EDIT-001G — the Overview "Order edits" data layer
/// (`owner_order_edits`, API_CONTRACT §4.47).
///
/// Written against the seams that carry the window and the money: the
/// parameters the real repository puts on the wire, how each failure is
/// classified, how the envelope is parsed (integers only, D-007), and the
/// query key's identity.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_range.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_window.dart';
import 'package:restoflow_dashboard/src/analytics/owner_order_edits_query_key.dart';
import 'package:restoflow_dashboard/src/data/owner_order_edits.dart';
import 'package:restoflow_dashboard/src/data/owner_order_edits_repository.dart';
import 'package:restoflow_dashboard/src/data/real_owner_order_edits_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

class _RecordingTransport implements SyncRpcTransport {
  _RecordingTransport({this.answer, this.error});

  final Object? answer;
  final SyncTransportException? error;
  final List<String> functions = <String>[];
  final List<Map<String, dynamic>> params = <Map<String, dynamic>>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> args) async {
    functions.add(function);
    params.add(Map<String, dynamic>.from(args));
    final failure = error;
    if (failure != null) throw failure;
    return answer ??
        <String, dynamic>{
          'ok': true,
          'entity': 'owner_order_edits',
          'currency_code': 'ILS',
          'currency_codes': <dynamic>[],
          'range': args['p_range'] ?? 'custom',
          'limit': args['p_limit'],
          'order_edit_enabled_in_scope': false,
          'staff_visible': false,
          'summary': _zeros(),
          'by_reason': <dynamic>[],
          'by_staff': <dynamic>[],
          'edits': <dynamic>[],
          'count': 0,
          'matching': 0,
          'has_more': false,
          'next_cursor': null,
        };
  }
}

Map<String, dynamic> _zeros() => <String, dynamic>{
  'edit_count': 0,
  'edited_order_count': 0,
  'removed_minor': 0,
  'replaced_out_minor': 0,
  'replaced_in_minor': 0,
  'added_minor': 0,
  'net_change_minor': 0,
  'gross_retired_minor': 0,
};

Map<String, dynamic> _figures({
  int edits = 1,
  int orders = 1,
  int removed = 1500,
  int out = 4000,
  int inn = 4000,
  int added = 900,
}) => <String, dynamic>{
  'edit_count': edits,
  'edited_order_count': orders,
  'removed_minor': removed,
  'replaced_out_minor': out,
  'replaced_in_minor': inn,
  'added_minor': added,
  'net_change_minor': inn + added - removed - out,
  'gross_retired_minor': removed + out,
};

Map<String, dynamic> _fullPayload({
  bool staffVisible = true,
}) => <String, dynamic>{
  'ok': true,
  'entity': 'owner_order_edits',
  'currency_code': 'ILS',
  'currency_codes': <dynamic>['ILS'],
  'range': 'last7',
  'limit': 2,
  'order_edit_enabled_in_scope': true,
  'staff_visible': staffVisible,
  'summary': _figures(edits: 3, orders: 2, added: 1800),
  'by_reason': <dynamic>[
    <String, dynamic>{'reason_code': 'customer_changed_mind', ..._figures()},
    <String, dynamic>{
      'reason_code': null,
      ..._figures(removed: 0, out: 0, inn: 0, added: 900),
    },
  ],
  'by_staff': <dynamic>[
    <String, dynamic>{'staff_name': 'Amira', ..._figures(edits: 3)},
  ],
  'edits': <dynamic>[
    <String, dynamic>{
      'order_edit_id': 'e-2',
      'order_id': 'o-1',
      'order_code': '#ABC123',
      'edit_number': 2,
      'order_status': 'voided',
      'order_type': 'dine_in',
      'branch_name': 'Main',
      'staff_name': 'Amira',
      'reason_code': null,
      'kitchen_channel': 'kds',
      'created_at': '2026-10-09 12:55',
      'created_at_utc': '2026-10-09T09:55:00Z',
      'business_day': '2026-10-09',
      'timezone': 'Asia/Jerusalem',
      'currency_code': 'ILS',
      ..._figures(removed: 0, out: 0, inn: 0, added: 900),
    },
    // Unrenderable: no identity — skipped, never invented.
    <String, dynamic>{'order_code': '#NOID00', ..._figures()},
    // Unrenderable: no display code.
    <String, dynamic>{'order_edit_id': 'e-x', ..._figures()},
    'not a map',
  ],
  'count': 2,
  'matching': 3,
  'has_more': true,
  'next_cursor': '2026-10-09 09:55:00+00|e-2',
};

MembershipContext _membership() => MembershipContext(
  id: 'm-1',
  organizationId: 'org-1',
  organizationName: 'Org',
  restaurantId: 'rest-1',
  restaurantName: 'Rest One',
  branchId: 'branch-1',
  branchName: 'Main',
  role: MembershipRole.orgOwner,
  status: 'active',
);

OwnerOrderEditsQueryKey _key({
  AnalyticsRange range = AnalyticsRange.today,
  CustomAnalyticsWindow? custom,
  String? restaurantId,
  String? branchId,
  int limit = kOverviewOrderEditsLimit,
  String organizationId = 'org-1',
  bool demo = false,
}) => OwnerOrderEditsQueryKey(
  organizationId: organizationId,
  restaurantId: restaurantId,
  branchId: branchId,
  range: range,
  customWindow: custom,
  limit: limit,
  isDemoMode: demo,
);

CustomAnalyticsWindow _custom(String start, String end) =>
    AnalyticsWindow.custom(DateTime.parse(start), DateTime.parse(end))
        as CustomAnalyticsWindow;

Future<OwnerOrderEdits> _load(
  _RecordingTransport t, {
  OwnerOrderEditsQueryKey? key,
  String? reasonCode,
  String? cursor,
}) {
  final k = key ?? _key();
  return RealOwnerOrderEditsRepository(
    scope: _membership(),
    transport: t,
  ).loadOrderEdits(
    range: k.range,
    analyticsScope: k.analyticsScope,
    customWindow: k.customWindow,
    limit: k.limit,
    reasonCode: reasonCode,
    cursor: cursor,
  );
}

void main() {
  group('A. wire parameters', () {
    test('a preset sends only p_range, never the dates', () async {
      for (final range in AnalyticsRange.values) {
        final t = _RecordingTransport();
        await _load(t, key: _key(range: range));
        expect(t.functions.single, 'owner_order_edits');
        final p = t.params.single;
        expect(p['p_range'], range.wire);
        expect(p.containsKey('p_start'), isFalse);
        expect(p.containsKey('p_end'), isFalse);
      }
    });

    test('a custom window sends only the pair, never p_range', () async {
      final t = _RecordingTransport();
      await _load(
        t,
        key: _key(
          range: AnalyticsRange.last90,
          custom: _custom('2026-09-01', '2026-09-14'),
        ),
      );
      final p = t.params.single;
      expect(p['p_start'], '2026-09-01');
      expect(p['p_end'], '2026-09-14');
      expect(p.containsKey('p_range'), isFalse);
    });

    test('scope ids come from the key; the organization from the membership; '
        'the limit is sent', () async {
      final t = _RecordingTransport();
      await _load(
        t,
        key: _key(restaurantId: 'rest-9', branchId: 'branch-9'),
      );
      final p = t.params.single;
      expect(p['p_organization_id'], 'org-1');
      expect(p['p_restaurant_id'], 'rest-9');
      expect(p['p_branch_id'], 'branch-9');
      expect(p['p_limit'], kOverviewOrderEditsLimit);
    });

    test('an org-wide key is not narrowed to the membership pins', () async {
      final t = _RecordingTransport();
      await _load(t);
      expect(t.params.single['p_restaurant_id'], isNull);
      expect(t.params.single['p_branch_id'], isNull);
    });

    test('reason and cursor are sent only when set', () async {
      final t = _RecordingTransport();
      await _load(t);
      expect(t.params.single.containsKey('p_reason_code'), isFalse);
      expect(t.params.single.containsKey('p_cursor'), isFalse);
      await _load(t, reasonCode: 'none', cursor: 'c|e');
      expect(t.params.last['p_reason_code'], 'none');
      expect(t.params.last['p_cursor'], 'c|e');
    });

    test('a key claiming a FOREIGN organization fails closed', () async {
      final t = _RecordingTransport();
      await expectLater(
        _load(t, key: _key(organizationId: 'org-OTHER')),
        throwsA(isA<OwnerOrderEditsException>()),
      );
      expect(t.functions, isEmpty, reason: 'nothing may reach the wire');
    });

    test('no transport is a failure, never an empty block', () async {
      await expectLater(
        const RealOwnerOrderEditsRepository().loadOrderEdits(
          range: AnalyticsRange.today,
        ),
        throwsA(isA<RealRepoNotWiredError>()),
      );
    });
  });

  group('B. failure classification', () {
    test('PGRST202 and 404 degrade to unavailable', () async {
      for (final code in ['PGRST202', '404']) {
        final t = _RecordingTransport(
          error: SyncTransportException(
            SyncTransportErrorKind.server,
            code: code,
            message: 'Could not find the function public.owner_order_edits',
          ),
        );
        final r = await _load(t, key: _key(range: AnalyticsRange.last7));
        expect(r.supported, isFalse, reason: code);
        expect(r.visibleOnOverview, isFalse);
        expect(r.rangeWire, 'last7');
      }
    });

    test('42501 and 22023 THROW — never softened to unavailable', () async {
      for (final e in const [
        SyncTransportException(
          SyncTransportErrorKind.auth,
          code: '42501',
          message: 'permission denied',
        ),
        SyncTransportException(
          SyncTransportErrorKind.server,
          code: '22023',
          message: 'unknown reason code',
        ),
      ]) {
        await expectLater(
          _load(_RecordingTransport(error: e)),
          throwsA(isA<OwnerOrderEditsException>()),
        );
      }
    });

    test('permission_denied (kitchen staff) throws', () async {
      final t = _RecordingTransport(
        answer: <String, dynamic>{
          'ok': false,
          'error': 'permission_denied',
          'entity': 'owner_order_edits',
        },
      );
      await expectLater(_load(t), throwsA(isA<OwnerOrderEditsException>()));
    });

    test('an entity mismatch throws', () async {
      final t = _RecordingTransport(
        answer: <String, dynamic>{..._fullPayload(), 'entity': 'owner_x'},
      );
      await expectLater(_load(t), throwsA(isA<OwnerOrderEditsException>()));
    });

    test('an empty window is supported data with zeros', () async {
      final r = await _load(_RecordingTransport());
      expect(r.supported, isTrue);
      expect(r.isEmpty, isTrue);
      expect(r.summary.grossRetiredMinor, 0);
      expect(r.edits, isEmpty);
      expect(r.currencyCodes, isEmpty);
    });
  });

  group('C. payload parse', () {
    test('every envelope field, the null-reason row and paging', () async {
      final r = await _load(_RecordingTransport(answer: _fullPayload()));
      expect(r.currencyCode, 'ILS');
      expect(r.currencyCodes, ['ILS']);
      expect(r.rangeWire, 'last7');
      expect(r.enabledInScope, isTrue);
      expect(r.staffVisible, isTrue);
      expect(r.summary.editCount, 3);
      expect(r.summary.editedOrderCount, 2);
      expect(r.summary.removedMinor, 1500);
      expect(r.summary.replacedOutMinor, 4000);
      expect(r.summary.replacedInMinor, 4000);
      expect(r.summary.addedMinor, 1800);
      expect(r.summary.netChangeMinor, 300);
      expect(r.summary.grossRetiredMinor, 5500);
      expect(r.byReason.map((b) => b.reasonCode), [
        'customer_changed_mind',
        null,
      ]);
      expect(r.byReason.last.figures.addedMinor, 900);
      expect(r.byStaff.single.staffName, 'Amira');
      expect(r.count, 2);
      expect(r.matching, 3);
      expect(r.hasMore, isTrue);
      expect(r.nextCursor, '2026-10-09 09:55:00+00|e-2');
    });

    test('edit rows: fields copied, malformed rows skipped', () async {
      final r = await _load(_RecordingTransport(answer: _fullPayload()));
      expect(r.edits.map((e) => e.orderEditId), ['e-2']);
      final e = r.edits.single;
      expect(e.orderCode, '#ABC123');
      expect(e.editNumber, 2);
      expect(e.orderVoided, isTrue);
      expect(e.reasonCode, isNull);
      expect(e.staffName, 'Amira');
      expect(e.createdAtLabel, '2026-10-09 12:55');
      expect(e.businessDay, '2026-10-09');
      expect(e.timezone, 'Asia/Jerusalem');
      expect(e.kitchenChannel, 'kds');
      expect(e.figures.netChangeMinor, 900);
    });

    test(
      'staff_visible false: no staff rows and no names, even if sent',
      () async {
        final r = await _load(
          _RecordingTransport(answer: _fullPayload(staffVisible: false)),
        );
        expect(r.staffVisible, isFalse);
        expect(r.byStaff, isEmpty);
        expect(r.edits.single.staffName, isNull);
        // Everything else is the same.
        expect(r.summary.grossRetiredMinor, 5500);
        expect(r.byReason, hasLength(2));
      },
    );

    test('money stays integer minor units (D-007)', () async {
      final r = await _load(_RecordingTransport(answer: _fullPayload()));
      for (final f in [
        r.summary,
        ...r.byReason.map((b) => b.figures),
        ...r.edits.map((e) => e.figures),
      ]) {
        for (final v in [
          f.removedMinor,
          f.replacedOutMinor,
          f.replacedInMinor,
          f.addedMinor,
          f.netChangeMinor,
          f.grossRetiredMinor,
        ]) {
          expect(v, isA<int>());
        }
      }
    });

    test('currency rule: money only in the window currency', () async {
      final r = await _load(_RecordingTransport(answer: _fullPayload()));
      expect(r.moneyRenderableIn('ILS'), isTrue);
      expect(r.moneyRenderableIn('USD'), isFalse);
      const mixed = OwnerOrderEdits(
        currencyCode: 'ILS',
        rangeWire: 'today',
        currencyCodes: ['ILS', 'USD'],
      );
      expect(mixed.moneyRenderableIn('ILS'), isFalse);
      const empty = OwnerOrderEdits(currencyCode: 'ILS', rangeWire: 'today');
      expect(empty.moneyRenderableIn('ILS'), isTrue);
    });

    test('visibility: enabled scope or edits in the window', () {
      const hidden = OwnerOrderEdits(currencyCode: 'ILS', rangeWire: 'today');
      expect(hidden.visibleOnOverview, isFalse);
      const enabled = OwnerOrderEdits(
        currencyCode: 'ILS',
        rangeWire: 'today',
        enabledInScope: true,
      );
      expect(enabled.visibleOnOverview, isTrue);
      const editedThenOff = OwnerOrderEdits(
        currencyCode: 'ILS',
        rangeWire: 'today',
        summary: OrderEditFigures(editCount: 2),
      );
      expect(editedThenOff.visibleOnOverview, isTrue);
      expect(
        const OwnerOrderEdits.unavailable('today').visibleOnOverview,
        isFalse,
      );
    });
  });

  group('D. demo repository', () {
    test('the MONEY §9.2 worked example and its identity', () async {
      final r = await const DemoOwnerOrderEditsRepository().loadOrderEdits(
        range: AnalyticsRange.today,
      );
      final s = r.summary;
      expect(
        [s.removedMinor, s.replacedOutMinor, s.replacedInMinor, s.addedMinor],
        [1500, 4000, 4000, 900],
      );
      expect(s.netChangeMinor, -600);
      expect(
        s.netChangeMinor,
        s.replacedInMinor + s.addedMinor - s.removedMinor - s.replacedOutMinor,
      );
      expect(s.grossRetiredMinor, s.removedMinor + s.replacedOutMinor);
      expect(r.visibleOnOverview, isTrue);
    });

    test('echoes the window token; a cursor gives an empty page', () async {
      const repo = DemoOwnerOrderEditsRepository();
      for (final range in AnalyticsRange.values) {
        expect((await repo.loadOrderEdits(range: range)).rangeWire, range.wire);
      }
      final custom = await repo.loadOrderEdits(
        range: AnalyticsRange.today,
        customWindow: _custom('2026-09-01', '2026-09-02'),
      );
      expect(custom.rangeWire, kCustomRangeWire);
      final next = await repo.loadOrderEdits(
        range: AnalyticsRange.today,
        cursor: 'x',
      );
      expect(next.edits, isEmpty);
    });

    test('a failing demo repository throws', () async {
      await expectLater(
        const DemoOwnerOrderEditsRepository(
          failureMessage: 'boom',
        ).loadOrderEdits(range: AnalyticsRange.today),
        throwsA(isA<OwnerOrderEditsException>()),
      );
    });
  });

  group('E. query-key identity', () {
    test('preset != custom; two custom windows differ', () {
      expect(
        _key(range: AnalyticsRange.last30) ==
            _key(
              range: AnalyticsRange.last30,
              custom: _custom('2026-03-01', '2026-03-30'),
            ),
        isFalse,
      );
      expect(
        _key(custom: _custom('2026-03-01', '2026-03-14')) ==
            _key(custom: _custom('2026-03-02', '2026-03-14')),
        isFalse,
      );
    });

    test('demo != real; limit and scope are part of identity', () {
      expect(_key(demo: true) == _key(), isFalse);
      expect(_key(limit: 5) == _key(limit: 25), isFalse);
      expect(_key(branchId: 'b-1') == _key(branchId: 'b-2'), isFalse);
    });

    test('identical inputs are one entry', () {
      final a = _key(custom: _custom('2026-03-01', '2026-03-14'));
      final b = _key(custom: _custom('2026-03-01', '2026-03-14'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the Overview limit is the card size', () {
      expect(_key().limit, kOverviewOrderEditsLimit);
      expect(kOverviewOrderEditsLimit, 5);
      expect(kOrderEditsPageSize, 25);
    });
  });
}
