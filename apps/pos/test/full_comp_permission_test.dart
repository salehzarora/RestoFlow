import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/discount.dart';
import 'package:restoflow_pos/src/data/discount_repository.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart';

/// FULL-COMP-PERMISSION-001 — the POS side of the SEPARATE "make an order free"
/// permission.
///
/// The demo cart's only item is ₪42.00 (subtotal 4200 minor, tax 0), so a fixed
/// discount of ₪42 or a 100% discount both land the order on EXACTLY zero.
///
/// The rule under test is "the RESULTING TOTAL is zero", never "the 100% preset was
/// chosen" — which is why a FIXED discount that happens to cover the order is
/// asserted alongside the percentage one. A percentage-only client gate would have
/// been a hole, and the POS is where a cashier would have found it.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

/// Records whether the backend was reached at all — the point of the client-side
/// pre-check is that a known-doomed request is never sent.
class _RecordingDiscountRepo implements DiscountRepository {
  _RecordingDiscountRepo({this.throws});

  final DiscountException? throws;
  int calls = 0;

  @override
  Future<OrderDiscount> applyOrderDiscount({
    required String orderId,
    required DiscountType type,
    required int value,
    required String reason,
    required int subtotalMinor,
    required int taxTotalMinor,
    int? expectedRevision,
  }) async {
    calls++;
    final t = throws;
    if (t != null) throw t;
    final raw = type == DiscountType.fixed
        ? value
        : (subtotalMinor * value) ~/ 10000;
    final discount = raw > subtotalMinor ? subtotalMinor : raw;
    return OrderDiscount(
      discountTotalMinor: discount,
      grandTotalMinor: subtotalMinor - discount + taxTotalMinor,
    );
  }
}

class _Caps implements StaffCapabilitiesRepository {
  const _Caps(this._value);
  final PosStaffCapabilities? _value;

  @override
  Future<PosStaffCapabilities?> fetch() async => _value;
}

/// A cashier who may discount but may NOT make an order free (the default).
const _cashier = PosStaffCapabilities(
  applyDiscount: true,
  applyFullComp: false,
);

/// A cashier explicitly granted the right, or a manager/owner (who holds it by
/// role — the server resolves both to the same EFFECTIVE answer).
const _mayComp = PosStaffCapabilities(applyDiscount: true, applyFullComp: true);

Future<void> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDiscount(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('apply-discount-button')));
  await tester.pumpAndSettle();
}

Future<void> _enterDiscount(
  WidgetTester tester, {
  required String value,
  bool percentage = false,
}) async {
  if (percentage) {
    await tester.tap(find.byKey(const Key('discount-type-percentage')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const Key('discount-value-field')), value);
  await tester.enterText(
    find.byKey(const Key('discount-reason-field')),
    'on the house',
  );
  await tester.tap(find.byKey(const Key('discount-apply-button')));
  await tester.pumpAndSettle();
}

void main() {
  group('a cashier WITHOUT the full-comp permission', () {
    testWidgets('may still apply an ordinary partial discount', (tester) async {
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_cashier),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '10'); // ₪10 off ₪42 -> ₪32 left

      expect(repo.calls, 1, reason: 'the discount was sent to the server');
      expect(
        find.text(l10n.posDiscountFullCompDenied),
        findsNothing,
        reason: 'a partial discount is not a comp — do not scold the cashier',
      );
      expect(find.byKey(const Key('confirmation-discount')), findsOneWidget);
    });

    testWidgets('CANNOT reduce the total to zero with a PERCENTAGE, and the '
        'doomed request is never sent', (tester) async {
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_cashier),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '100', percentage: true);

      expect(find.text(l10n.posDiscountFullCompDenied), findsOneWidget);
      expect(
        repo.calls,
        0,
        reason: 'blocked BEFORE any optimistic local success or backend call',
      );
      expect(find.byKey(const Key('confirmation-discount')), findsNothing);
    });

    testWidgets('CANNOT bypass the rule with a FIXED amount that covers the '
        'whole order', (tester) async {
      // The whole point of gating on the RESULTING TOTAL: disabling a "100%"
      // preset would not have caught this.
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_cashier),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '42'); // exactly the ₪42.00 subtotal

      expect(find.text(l10n.posDiscountFullCompDenied), findsOneWidget);
      expect(repo.calls, 0);
      expect(find.byKey(const Key('confirmation-discount')), findsNothing);
    });
  });

  group('an operator WITH the right', () {
    testWidgets('a granted cashier may make the order free', (tester) async {
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_mayComp),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '100', percentage: true);

      expect(find.text(l10n.posDiscountFullCompDenied), findsNothing);
      expect(repo.calls, 1);
      expect(find.byKey(const Key('confirmation-discount')), findsOneWidget);
    });

    testWidgets('a manager/owner (right held BY ROLE) may make the order free', (
      tester,
    ) async {
      // The server resolves role-held and explicitly-granted rights to the same
      // EFFECTIVE answer, so the POS needs no role knowledge at all.
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_mayComp),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '42');

      expect(repo.calls, 1);
      expect(find.byKey(const Key('confirmation-discount')), findsOneWidget);
    });
  });

  group('the server stays authoritative', () {
    testWidgets('a TYPED full-comp refusal is shown with its own message, not '
        'the generic "ask a manager"', (tester) async {
      final l10n = await _en();
      // The client believes it may comp (e.g. a grant was revoked mid-shift), so
      // the pre-check passes and the SERVER refuses. This is the path that proves
      // the client never has the last word.
      final repo = _RecordingDiscountRepo(
        throws: const DiscountException(
          'full_comp_permission_required',
          permissionDenied: true,
          fullCompRequired: true,
        ),
      );
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_mayComp),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '100', percentage: true);

      expect(repo.calls, 1, reason: 'the server was asked and it refused');
      expect(find.text(l10n.posDiscountFullCompDenied), findsOneWidget);
      expect(
        find.text(l10n.posDiscountPermissionDenied),
        findsNothing,
        reason:
            'a comp refusal must not be flattened into "you cannot discount" — '
            'ordinary discounts still work',
      );
      expect(find.byKey(const Key('confirmation-discount')), findsNothing);
    });

    testWidgets('a TYPED negative-total refusal has its own message', (
      tester,
    ) async {
      final l10n = await _en();
      final repo = _RecordingDiscountRepo(
        throws: const DiscountException(
          'discount_exceeds_order_total',
          exceedsOrderTotal: true,
        ),
      );
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(_mayComp),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '10');

      expect(find.text(l10n.posDiscountExceedsOrderTotal), findsOneWidget);
      expect(find.byKey(const Key('confirmation-discount')), findsNothing);
    });

    testWidgets('UNKNOWN capabilities do NOT block the cashier — the server '
        'decides', (tester) async {
      // A capability probe that fails (offline, transient error) must not silently
      // strip a manager of the ability to comp. Unknown is not denied: we let the
      // request through and the SERVER refuses if it must.
      final l10n = await _en();
      final repo = _RecordingDiscountRepo();
      await _pump(
        tester,
        overrides: [
          discountRepositoryProvider.overrideWithValue(repo),
          staffCapabilitiesRepositoryProvider.overrideWithValue(
            const _Caps(null),
          ),
        ],
      );
      await _openDiscount(tester, l10n);
      await _enterDiscount(tester, value: '100', percentage: true);

      expect(
        repo.calls,
        1,
        reason: 'no client-side block when the right is unknown',
      );
      expect(find.text(l10n.posDiscountFullCompDenied), findsNothing);
    });
  });

  group('the capability wire is fail-closed', () {
    test('a missing apply_full_comp field parses as DENIED', () {
      final caps = PosStaffCapabilities.fromJson(const {
        'apply_discount': true,
      });
      expect(caps.applyDiscount, isTrue);
      expect(
        caps.applyFullComp,
        isFalse,
        reason: 'an old server that never sends the field must not grant it',
      );
    });

    test('malformed values never manufacture a grant', () {
      for (final junk in <Object?>['true', 1, null, 'yes']) {
        expect(
          PosStaffCapabilities.fromJson({
            'apply_full_comp': junk,
          }).applyFullComp,
          isFalse,
        );
      }
      expect(
        PosStaffCapabilities.fromJson(const {
          'apply_full_comp': true,
        }).applyFullComp,
        isTrue,
      );
    });

    test('the fail-closed default grants nothing', () {
      expect(PosStaffCapabilities.none.applyDiscount, isFalse);
      expect(PosStaffCapabilities.none.applyFullComp, isFalse);
    });
  });
}
