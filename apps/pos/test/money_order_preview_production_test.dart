import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/state/order_preview_controller.dart';

/// MONEY-PRODUCTION-PATH-TESTS-002D [F] — Codex Blocker 7, the order preview.
///
/// Driven through the REAL `orderPreviewControllerProvider` family (its
/// generation fence, its authoritative-then-fallback policy) and the REAL
/// `OrderDetailPreviewModel` mappers. Nothing here hand-builds a preview model.
///
/// Every expected amount is an INDEPENDENT LITERAL.
///
/// Classification: CODEX COVERAGE GAP.

const kBase = 4500;
const k240 = 1500;
// 2 x (4500 + 1500) = 12000; + (1000 + 300) = 13300.
const kBurgerLine = 12000;
const kColaLine = 1300;
const kSubtotal = 13300;

PosOrderDetail _detail({PosOrderDetailPayment? payment}) => PosOrderDetail(
  orderId: 'ord-1',
  orderCode: '#O00042',
  orderType: 'takeaway',
  status: 'preparing',
  revision: 3,
  currencyCode: 'ILS',
  subtotalMinor: kSubtotal,
  discountTotalMinor: 0,
  taxTotalMinor: 0,
  grandTotalMinor: kSubtotal,
  payment: payment,
  rounds: const [],
  items: const [
    PosOrderDetailItem(
      name: 'Burger',
      quantity: 2,
      unitPriceMinor: kBase,
      lineDiscountMinor: 0,
      lineTotalMinor: kBurgerLine,
      modifiers: [
        PosOrderDetailModifier(
          optionName: '240g',
          modifierName: 'Meat',
          priceMinor: k240,
          quantity: 1,
        ),
      ],
    ),
    PosOrderDetailItem(
      name: 'Cola',
      quantity: 1,
      unitPriceMinor: 1000,
      lineDiscountMinor: 0,
      lineTotalMinor: kColaLine,
      modifiers: [],
    ),
  ],
);

class _Repo implements OrderDetailRepository {
  _Repo(this._detail);
  final PosOrderDetail? _detail;
  int fetches = 0;
  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    final d = _detail;
    if (d == null) {
      throw const PosOrderDetailException(PosOrderDetailFailure.malformed);
    }
    return d;
  }
}

/// A locally-persisted recent order, decoded through the REAL 002B decoder.
Map<String, Object?> localRecord({
  Object? subtotal = kSubtotal,
  Object? lineTotal = kBurgerLine,
  Map<String, Object?>? payment,
  String? orderId = 'ord-1',
}) => <String, Object?>{
  'order': <String, Object?>{
    'order_number': '#O00042',
    'currency_code': 'ILS',
    'order_type': 'takeaway',
    'subtotal_minor': subtotal,
    'discount_total_minor': 0,
    'tax_total_minor': 0,
    'tax_rate_bp': 0,
    if (orderId != null) 'order_id': orderId,
    'lines': <Object?>[
      <String, Object?>{
        'name': 'Burger',
        'quantity': 2,
        'line_total_minor': lineTotal,
        'currency_code': 'ILS',
        'modifiers': <Object?>['240g'],
      },
    ],
  },
  'submitted_at': '2026-08-06T09:00:00.000Z',
  if (payment != null) 'payment': payment,
};

Map<String, Object?> validPayment([Map<String, Object?> override = const {}]) =>
    <String, Object?>{
      'payment_id': 'pay-local-1',
      'order_number': '#O00042',
      'device_id': 'dev-1',
      'local_operation_id': 'op-1',
      'currency_code': 'ILS',
      'receipt_number': 'R-9',
      'paid_at': '2026-08-06T09:00:00.000Z',
      'amount_minor': kSubtotal,
      'tendered_minor': 15000,
      'change_minor': 1700,
      'method': 'cash',
      'status': 'completed',
      ...override,
    };

ProviderContainer harness(_Repo repo, {bool demo = false}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: demo),
      ),
      orderDetailRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Subscribes to the REAL family provider and waits for the controller's OWN
/// load to settle.
///
/// `build()` schedules its authoritative fetch as a microtask and every load
/// takes a new generation token, so calling `load()` manually would supersede
/// the controller's own in-flight read and then read the state before the
/// winner published. This drains microtasks until the production controller
/// reaches a terminal phase, which is what the sheet actually observes.
Future<OrderPreviewState> loaded(
  ProviderContainer c,
  PosRecentOrder order,
) async {
  // Subscribe so the autoDispose family stays alive while it loads.
  final sub = c.listen(orderPreviewControllerProvider(order), (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 50; i++) {
    final state = c.read(orderPreviewControllerProvider(order));
    if (state.phase != OrderPreviewPhase.loading) return state;
    await Future<void>.microtask(() {});
  }
  fail('the preview never left the loading phase');
}

void main() {
  group('[F] the AUTHORITATIVE detail path', () {
    test('F1 the preview maps the stored line and order totals exactly, with '
        'no repricing from any catalogue', () async {
      final repo = _Repo(_detail());
      final c = harness(repo);
      final order = PosRecentOrder.fromJson(localRecord());

      final state = await loaded(c, order);
      expect(state.phase, OrderPreviewPhase.ready);
      expect(repo.fetches, greaterThanOrEqualTo(1));
      expect(
        state.staleLocalCopy,
        isFalse,
        reason: 'this is server truth, not a local copy',
      );

      final model = state.model!;
      expect(model.lines, hasLength(2));
      expect(model.lines[0].quantity, 2);
      expect(
        model.lines[0].lineTotalMinor,
        kBurgerLine,
        reason: 'the stored quantity-2 upgraded line, unchanged',
      );
      expect(model.lines[1].lineTotalMinor, kColaLine);
      expect(model.subtotalMinor, kSubtotal);
      // The document's own arithmetic, independent of any production helper.
      expect(
        model.lines.fold<int>(0, (s, l) => s + (l.lineTotalMinor ?? 0)),
        kBurgerLine + kColaLine,
      );
      // The authoritative modifier snapshot rides through with its money.
      expect(model.lines[0].modifiers, hasLength(1));
      expect(model.lines[0].modifiers.single.priceDeltaMinor, k240);
    });

    test('F2 the SERVER payment wins over a local one', () async {
      final serverPaid = PosOrderDetailPayment(
        paymentId: 'pay-server-1',
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        amountMinor: kSubtotal,
        tenderedMinor: 15000,
        changeMinor: 1700,
        paidAt: DateTime.utc(2026, 8, 6, 9),
        receiptNumber: 'R-server',
      );
      final c = harness(_Repo(_detail(payment: serverPaid)));
      final order = PosRecentOrder.fromJson(
        localRecord(payment: validPayment({'payment_id': 'pay-local-1'})),
      );

      final model = (await loaded(c, order)).model!;
      expect(model.payment, isNotNull);
      expect(
        model.payment!.amountMinor,
        kSubtotal,
        reason: 'a valid authoritative payment is never downgraded',
      );
    });
  });

  group('[F] the LOCAL FALLBACK path', () {
    test('F3 a failed authoritative read falls back to the exact local money, '
        'labelled as a local copy', () async {
      final c = harness(_Repo(null)); // every fetch throws
      final order = PosRecentOrder.fromJson(localRecord());

      final state = await loaded(c, order);
      expect(state.phase, OrderPreviewPhase.ready);
      expect(
        state.staleLocalCopy,
        isTrue,
        reason: 'the cashier must be told this is not server truth',
      );
      final model = state.model!;
      expect(model.lines, hasLength(1));
      expect(model.lines.single.lineTotalMinor, kBurgerLine);
      expect(model.subtotalMinor, kSubtotal);
    });

    test('F4 the local fallback never INVENTS structured modifier prices that '
        'the local record does not carry', () async {
      final c = harness(_Repo(null));
      final order = PosRecentOrder.fromJson(localRecord());
      final model = (await loaded(c, order)).model!;

      // The local record stores modifiers as DISPLAY strings only.
      for (final m in model.lines.single.modifiers) {
        expect(
          m.priceDeltaMinor,
          isNull,
          reason:
              'a local display string has no authoritative price — '
              'fabricating one would put an invented number on screen',
        );
      }
    });
  });

  group('[F] corrupt local records can never look authoritative', () {
    test('F5 malformed order money is refused outright — there is no preview '
        'to show, rather than a zero-total one', () {
      for (final bad in <Object?>['13300', 'oops', 13300.0, true, null]) {
        expect(
          () => PosRecentOrder.fromJson(localRecord(subtotal: bad)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('F6 malformed ITEM money is refused too', () {
      for (final bad in <Object?>['12000', 'oops', 12000.0, true, null]) {
        expect(
          () => PosRecentOrder.fromJson(localRecord(lineTotal: bad)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('F7 a malformed payment method, status, tender or change refuses the '
        'record — no Paid, no Cash, no reprint eligibility', () {
      for (final bad in <Map<String, Object?>>[
        {'method': 'bitcoin'},
        {'method': 7},
        {'status': 'weird'},
        {'status': null},
        {'tendered_minor': '15000'},
        {'change_minor': 1700.0},
        {'paid_at': 'not-a-date'},
      ]) {
        expect(
          () =>
              PosRecentOrder.fromJson(localRecord(payment: validPayment(bad))),
          throwsA(isA<FormatException>()),
          reason: 'corrupt payment field ${bad.keys.single}',
        );
      }
    });

    test('F8 the VALID equivalents still decode, preview and offer a receipt — '
        'the strictness above is not blanket refusal', () async {
      final order = PosRecentOrder.fromJson(
        localRecord(payment: validPayment()),
      );
      expect(order.payment, isNotNull);
      expect(order.payment!.method, PaymentMethod.cash);
      expect(order.payment!.status, PaymentStatus.completed);
      expect(order.canReprintReceipt, isTrue);

      final c = harness(_Repo(null));
      final model = (await loaded(c, order)).model!;
      expect(model.subtotalMinor, kSubtotal);
      expect(model.payment, isNotNull);
      expect(model.payment!.amountMinor, kSubtotal);
    });

    test('F9 an order with NO local lines and a failed read fails honestly '
        'instead of showing an empty, authoritative-looking preview', () async {
      final c = harness(_Repo(null));
      // A branch-DISCOVERED order: a server snapshot only, no local lines.
      final order = PosRecentOrder.fromJson(<String, Object?>{
        'snapshot': <String, Object?>{
          'order_id': 'ord-9',
          'order_code': '#O00099',
          'status': 'preparing',
          'revision': 1,
          'subtotal_minor': 5000,
          'discount_total_minor': 0,
          'tax_total_minor': 0,
          'grand_total_minor': 5000,
          'created_at': '2026-08-06T09:00:00.000Z',
          'updated_at': '2026-08-06T09:00:00.000Z',
          'sync_at': '2026-08-06T09:00:00.000Z',
        },
      });
      final state = await loaded(c, order);
      expect(
        state.phase,
        OrderPreviewPhase.failed,
        reason: 'no lines to show and no server answer — say so',
      );
      expect(state.model, isNull);
    });
  });
}
