import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax, DeviceBranchTaxReader;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_order_snapshots.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_snapshot.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/recent_orders_store.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/discount_controller.dart'
    show staffCapabilitiesProvider;
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/order_sync_controller.dart';
import 'package:restoflow_pos/src/state/pos_branch_tax.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/widgets/cart_panel.dart';
import 'package:restoflow_pos/src/widgets/modifier_selection_sheet.dart';
import 'package:restoflow_pos/src/widgets/order_edit_cart_widgets.dart';
import 'package:restoflow_pos/src/widgets/order_setup_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the cart in EDIT MODE (plan step 8, test 13; design
/// §7.1 points 3-8), driven end to end through the real [CartPanelContent],
/// the real [OrderEditController] and a SCRIPTED `sync_push`:
///
///  * the banner takes the order-setup slot, names the order and its table,
///    and "Discard changes" asks first; Clear is gone;
///  * each sent line shows its kitchen stage ("Printed" on paper), an added
///    line is "New", the trash strikes through with Undo, and narrowed lines
///    say why and keep only what the server would accept;
///  * the footer is the live plan: "Was → Now (±)" with LTR-isolated money in
///    every locale, the tax and "Discount kept" rows, and the ONE reason Send
///    is disabled, with the Cancel-order and Lower-discount affordances;
///  * the reason chips appear only for a removing change, with the
///    "Customer changed mind" preselect only for Waiting tickets;
///  * the finished-food confirm comes BEFORE anything is dispatched;
///  * the result toast follows the server, and paper never says "printed";
///  * a pre-bill this session printed rides the payload (D7) and is offered
///    again after the edit;
///  * "Apply to: Just 1" splits one unit off.
///
/// Every amount is an independent literal (D-007).

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');
const _lri = '\u2066';
const _pdi = '\u2069';

typedef _Handler = Object? Function(Map<String, dynamic> op);

class _Transport implements SyncRpcTransport {
  _Transport(this.script);
  final List<_Handler> script;
  final List<Map<String, dynamic>> ops = [];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function != 'sync_push') return {'ok': false};
    final op = ((params['p_operations'] as List).single as Map)
        .cast<String, dynamic>();
    ops.add(op);
    final handler = script.length >= ops.length
        ? script[ops.length - 1]
        : script.last;
    return handler(op);
  }
}

class _Details implements OrderDetailRepository {
  final Map<String, PosOrderDetail> byId = {};
  int fetches = 0;

  @override
  Future<PosOrderDetail> fetch(String orderId) async {
    fetches++;
    final d = byId[orderId];
    if (d == null) {
      throw const PosOrderDetailException(
        PosOrderDetailFailure.notFound,
        'order_not_found',
      );
    }
    return d;
  }
}

class _Tax implements DeviceBranchTaxReader {
  BranchTax tax = BranchTax.disabled;

  @override
  Future<BranchTax?> load() async => tax;
}

/// A bill this session handed to a printer (decision D7).
class _BillPrinted extends ReceiptPrintController {
  _BillPrinted(this.at);
  final DateTime at;

  @override
  Map<String, ReceiptPrintJob> build() => {
    orderEditBillJobKey('order-1'): ReceiptPrintJob(
      status: PrintJobStatus.sentToPrinter,
      at: at,
    ),
  };
}

PosStaffCapabilities _caps({
  Object? voidOrder = true,
  bool fullComp = true,
  String role = 'cashier',
}) => PosStaffCapabilities.fromJson(
  {
    'apply_discount': true,
    'apply_full_comp': fullComp,
    if (voidOrder != null) 'void_order': voidOrder,
  },
  role: role,
  branchFeatures: const {
    'order_edit_enabled': true,
    'order_edit_finished_food_manager_only': false,
  },
);

final _lemonade = menuItem('mi-lemonade', name: 'Lemonade', price: 900);

PosMenuData _menu({bool colaUnavailable = false}) => menuOf(
  [
    menuItem('mi-burger', name: 'Burger', price: 4000),
    menuItem('mi-fries', name: 'Fries', price: 1500),
    menuItem('mi-cola', name: 'Cola', price: 800, unavailable: colaUnavailable),
    menuItem('mi-tea', name: 'Tea', price: 500),
    _lemonade,
  ],
  groups: [
    menuGroup('grp-top', 'mi-burger', const [
      PosModifierOption(id: 'opt-bacon', name: 'Bacon', priceDeltaMinor: 500),
    ]),
  ],
);

/// Burger ×2 at 4000 (Waiting) + Fries 1500 (In kitchen) + Cola 800 (Ready)
/// + Tea 500 (Served) = 10800.
List<PosOrderDetailItem> _items() => [
  detailItem(
    'oi-burger',
    menuItemId: 'mi-burger',
    name: 'Burger',
    quantity: 2,
    unit: 4000,
  ),
  detailItem(
    'oi-fries',
    menuItemId: 'mi-fries',
    name: 'Fries',
    unit: 1500,
    unitStatus: 'preparing',
  ),
  detailItem(
    'oi-cola',
    menuItemId: 'mi-cola',
    name: 'Cola',
    unit: 800,
    unitStatus: 'ready',
  ),
  detailItem(
    'oi-tea',
    menuItemId: 'mi-tea',
    name: 'Tea',
    unit: 500,
    unitStatus: 'served',
  ),
];

/// [d] after the server applied `edit-1` — what proves the edit.
PosOrderDetail _proven(PosOrderDetail d) => PosOrderDetail(
  orderId: d.orderId,
  orderCode: d.orderCode,
  orderType: d.orderType,
  status: d.status,
  revision: d.revision + 1,
  currencyCode: d.currencyCode,
  subtotalMinor: d.subtotalMinor,
  discountTotalMinor: d.discountTotalMinor,
  taxTotalMinor: d.taxTotalMinor,
  grandTotalMinor: d.grandTotalMinor,
  items: d.items,
  rounds: d.rounds,
  tableLabel: d.tableLabel,
  kitchenChannel: d.kitchenChannel,
  branchFeatures: d.branchFeatures,
  editCount: 1,
  edits: const [PosOrderDetailEdit(orderEditId: 'edit-1', editNumber: 1)],
);

class _H {
  _H({
    PosOrderDetail? order,
    PosMenuData? menu,
    PosStaffCapabilities? caps,
    this.ack = true,
    String channel = 'kds',
    List<_Handler>? script,
    List<Override> extra = const [],
  }) {
    final o = order ?? detail(items: _items());
    details.byId['order-1'] = o;
    transport = _Transport(
      script ??
          [
            (op) {
              // The server applied it: the authoritative detail proves it.
              details.byId['order-1'] = _proven(o);
              return _applied(op, ack: ack, channel: channel);
            },
          ],
    );
    final capabilities = caps ?? _caps();
    final m = menu ?? _menu();
    c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(_session),
        orderDetailRepositoryProvider.overrideWithValue(details),
        orderSnapshotRepositoryProvider.overrideWithValue(
          DemoOrderSnapshotRepository(),
        ),
        posSyncPollIntervalProvider.overrideWithValue(null),
        posBranchTaxReaderProvider.overrideWithValue(tax),
        posMenuProvider.overrideWith((ref) async => m),
        staffCapabilitiesProvider.overrideWith((ref) async => capabilities),
        clientIdGeneratorProvider.overrideWithValue(
          FixedClientIdGenerator(const ['op-1', 'op-2', 'op-3']),
        ),
        posVerifiedKitchenModeProvider.overrideWithValue(null),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
  }

  final bool ack;
  final _Details details = _Details();
  final _Tax tax = _Tax();
  late final _Transport transport;
  late final ProviderContainer c;

  CartController get cart => c.read(cartControllerProvider.notifier);
  OrderEditState get edit => c.read(orderEditControllerProvider);
}

Object? _envelope(Map<String, dynamic> op, Map<String, Object?> row) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': op['local_operation_id'],
      'operation_type': 'order.edit',
      ...row,
    },
  ],
};

Object? _applied(
  Map<String, dynamic> op, {
  bool ack = true,
  String channel = 'kds',
}) => _envelope(op, {
  'status': 'applied',
  'ok': true,
  'order_id': 'order-1',
  'order_edit_id': 'edit-1',
  'edit_number': 1,
  'revision': 4,
  'kitchen_channel': channel,
  'kitchen_ack_required': ack,
  'new_round_id': 'round-2',
  'new_round_number': 2,
  'changes': const <Object?>[],
});

_Handler _refused(String code) =>
    (op) => _envelope(op, {'status': 'rejected', 'error': code});

Future<AppLocalizations> _l10n([String code = 'en']) =>
    AppLocalizations.delegate.load(Locale(code));

/// Pumps the cart panel over [h] and opens the edit of `order-1`.
Future<void> _open(
  WidgetTester tester,
  _H h, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.c,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: CartPanelContent()),
      ),
    ),
  );
  await tester.pump();
  final entry = h.c
      .read(orderEditControllerProvider.notifier)
      .enterForOrder('order-1');
  await tester.pumpAndSettle();
  expect(await entry, OrderEditEntryResult.entered);
  expect(h.c.read(cartControllerProvider).isEditing, isTrue);
}

Finder _key(String key) => find.byKey(Key(key));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

bool _stepEnabled(WidgetTester tester, String key) =>
    tester
        .widget<InkResponse>(
          find.descendant(of: _key(key), matching: find.byType(InkResponse)),
        )
        .onTap !=
    null;

bool _buttonEnabled(WidgetTester tester, String key) =>
    tester.widget<IconButton>(_key(key)).onPressed != null;

bool _sendEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_key('order-edit-send')).onPressed != null;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  group('banner and lines', () {
    testWidgets('the banner takes the setup slot and names the order and its '
        'table; Clear is gone', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);

      expect(_key('pos-order-edit-banner'), findsOneWidget);
      expect(
        _text(tester, 'pos-order-edit-banner-text'),
        'Editing #A1B2C3 · Table 4',
      );
      expect(find.byType(OrderSetupSection), findsNothing);
      expect(find.widgetWithText(TextButton, l10n.posClearCart), findsNothing);
      // No setup-section Send: the edit footer owns the bottom.
      expect(_key('order-edit-footer'), findsOneWidget);
      expect(find.text(l10n.posSendOrder), findsNothing);
    });

    testWidgets('a takeaway (no table) reads "Editing #A1B2C3"', (
      tester,
    ) async {
      final h = _H(
        order: detail(items: _items(), orderType: 'takeaway', tableLabel: null),
      );
      await _open(tester, h);
      expect(_text(tester, 'pos-order-edit-banner-text'), 'Editing #A1B2C3');
    });

    testWidgets('each sent line shows its kitchen stage', (tester) async {
      final h = _H();
      await _open(tester, h);
      for (final (id, label) in [
        ('oi-burger', 'Waiting'),
        ('oi-fries', 'In kitchen'),
        ('oi-cola', 'Ready'),
        ('oi-tea', 'Served'),
      ]) {
        expect(
          find.descendant(
            of: _key('cart-line-stage-sent-$id'),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: id,
        );
      }
    });

    testWidgets('on a printer-only branch every line is "Printed"', (
      tester,
    ) async {
      final h = _H(
        order: detail(items: _items(), channel: PosKitchenChannel.paper),
      );
      await _open(tester, h);
      for (final id in ['oi-burger', 'oi-fries', 'oi-cola', 'oi-tea']) {
        expect(
          find.descendant(
            of: _key('cart-line-stage-sent-$id'),
            matching: find.text('Printed'),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('a menu tap adds a "New" line and never merges into a sent '
        'one', (tester) async {
      final h = _H();
      await _open(tester, h);
      h.cart.addItem(menuItem('mi-burger', name: 'Burger', price: 4000));
      await tester.pumpAndSettle();
      final lines = h.c.read(cartControllerProvider).lines;
      final added = lines.singleWhere((l) => l.editAdded);
      expect(added.menuItemId, 'mi-burger');
      expect(
        lines.singleWhere((l) => l.lineId == 'sent-oi-burger').quantity,
        2,
      );
      expect(
        find.descendant(
          of: _key('cart-line-new-${added.lineId}'),
          matching: find.text('New'),
        ),
        findsOneWidget,
      );
      expect(_key('cart-line-new-sent-oi-burger'), findsNothing);
    });

    testWidgets('the trash strikes a sent line through; Undo takes it back', (
      tester,
    ) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-fries');

      expect(_key('cart-remove-sent-oi-fries'), findsNothing);
      expect(_key('cart-undo-remove-sent-oi-fries'), findsOneWidget);
      final name = tester.widget<Text>(
        find.descendant(
          of: find.byType(CartPanelContent),
          matching: find.text('Fries'),
        ),
      );
      expect(name.style?.decoration, TextDecoration.lineThrough);
      expect(
        h.c
            .read(cartControllerProvider)
            .lines
            .singleWhere((l) => l.lineId == 'sent-oi-fries')
            .editRemoved,
        isTrue,
      );

      await _tap(tester, 'cart-undo-remove-sent-oi-fries');
      expect(_key('cart-remove-sent-oi-fries'), findsOneWidget);
      expect(_key('cart-undo-remove-sent-oi-fries'), findsNothing);
    });

    testWidgets('narrowed lines say why and keep only the trash', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H(
        menu: _menu(colaUnavailable: true),
        order: detail(
          items: [
            detailItem(
              'oi-disc',
              menuItemId: 'mi-burger',
              name: 'Burger',
              quantity: 2,
              unit: 4000,
              lineDiscount: 500,
            ),
            detailItem(
              'oi-old',
              menuItemId: 'mi-fries',
              name: 'Fries',
              unit: 1500,
              legacy: null,
            ),
            detailItem(
              'oi-gone',
              menuItemId: 'mi-soup',
              name: 'Soup',
              unit: 1200,
            ),
            detailItem(
              'oi-cola',
              menuItemId: 'mi-cola',
              name: 'Cola',
              unit: 800,
            ),
          ],
        ),
      );
      await _open(tester, h);

      for (final (id, hint) in [
        ('oi-disc', l10n.posOrderEditRemoveOnlyDiscount),
        ('oi-old', l10n.posOrderEditRemoveOnlyLegacy),
        ('oi-gone', l10n.posOrderEditKeepOrRemoveOnly),
      ]) {
        expect(_text(tester, 'cart-line-hint-sent-$id'), hint, reason: id);
        expect(_stepEnabled(tester, 'cart-increase-sent-$id'), isFalse);
        expect(_stepEnabled(tester, 'cart-decrease-sent-$id'), isFalse);
        expect(_buttonEnabled(tester, 'cart-edit-sent-$id'), isFalse);
        expect(_buttonEnabled(tester, 'cart-remove-sent-$id'), isTrue);
      }
      // Sold out: no "+", everything else stays.
      expect(_key('cart-line-hint-sent-oi-cola'), findsNothing);
      expect(_stepEnabled(tester, 'cart-increase-sent-oi-cola'), isFalse);
      expect(_stepEnabled(tester, 'cart-decrease-sent-oi-cola'), isTrue);
      expect(_buttonEnabled(tester, 'cart-remove-sent-oi-cola'), isTrue);
    });

    testWidgets('void_order denied: the banner says additions still work; '
        '"+" stays and "−" only takes back an increase', (tester) async {
      final l10n = await _l10n();
      final h = _H(caps: _caps(voidOrder: false));
      await _open(tester, h);

      expect(
        _text(tester, 'pos-order-edit-removal-hint'),
        l10n.posOrderEditRemovalNotAllowedHint,
      );
      expect(_buttonEnabled(tester, 'cart-remove-sent-oi-burger'), isFalse);
      expect(_buttonEnabled(tester, 'cart-edit-sent-oi-burger'), isFalse);
      expect(_stepEnabled(tester, 'cart-decrease-sent-oi-burger'), isFalse);
      expect(_stepEnabled(tester, 'cart-increase-sent-oi-burger'), isTrue);

      await _tap(tester, 'cart-increase-sent-oi-burger');
      expect(_stepEnabled(tester, 'cart-decrease-sent-oi-burger'), isTrue);
      // An increase needs no reason and no void right.
      expect(_key('order-edit-reasons'), findsNothing);
      expect(_sendEnabled(tester), isTrue);
    });

    testWidgets('finished food with the switch ON: "Manager needed" on a '
        'cashier\'s Ready and Served lines', (tester) async {
      final h = _H(
        order: detail(
          items: _items(),
          features: const PosBranchFeatures(
            orderEditEnabled: true,
            finishedFoodManagerOnly: true,
          ),
        ),
      );
      await _open(tester, h);
      for (final id in ['oi-cola', 'oi-tea']) {
        expect(
          find.descendant(
            of: _key('cart-line-manager-sent-$id'),
            matching: find.text('Manager needed'),
          ),
          findsOneWidget,
        );
        expect(_buttonEnabled(tester, 'cart-remove-sent-$id'), isFalse);
      }
      expect(_key('cart-line-manager-sent-oi-fries'), findsNothing);
      expect(_buttonEnabled(tester, 'cart-remove-sent-oi-fries'), isTrue);
    });

    testWidgets('"Discard changes" asks first, then leaves the order as sent', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-fries');

      await _tap(tester, 'pos-order-edit-discard');
      expect(find.text(l10n.posOrderEditDiscardConfirmTitle), findsOneWidget);
      expect(find.text(l10n.posOrderEditDiscardConfirmBody), findsOneWidget);
      await _tap(tester, 'order-edit-discard-cancel');
      expect(h.c.read(cartControllerProvider).isEditing, isTrue);

      await _tap(tester, 'pos-order-edit-discard');
      await _tap(tester, 'order-edit-discard-confirm');
      expect(h.c.read(cartControllerProvider).isEditing, isFalse);
      expect(h.c.read(cartControllerProvider).isEmpty, isTrue);
      expect(h.edit.phase, OrderEditPhase.idle);
      expect(h.transport.ops, isEmpty);
      expect(_key('pos-order-edit-banner'), findsNothing);
    });
  });

  group('the footer', () {
    testWidgets('"Was → Now (−)" with every money run LTR-isolated', (
      tester,
    ) async {
      final h = _H();
      await _open(tester, h);
      expect(
        _text(tester, 'order-edit-totals-change'),
        'Was $_lri₪108.00$_pdi → Now $_lri₪108.00$_pdi ($_lri+₪0.00$_pdi)',
      );
      await _tap(tester, 'cart-remove-sent-oi-fries');
      expect(
        _text(tester, 'order-edit-totals-change'),
        'Was $_lri₪108.00$_pdi → Now $_lri₪93.00$_pdi ($_lri−₪15.00$_pdi)',
      );
      expect(_text(tester, 'order-edit-subtotal'), '₪93.00');
    });

    for (final (code, was, now) in [
      ('ar', 'كان', 'الآن'),
      ('he', 'היה', 'עכשיו'),
    ]) {
      testWidgets('$code: "←" with the money still isolated', (tester) async {
        final h = _H();
        await _open(tester, h, locale: Locale(code));
        await _tap(tester, 'cart-remove-sent-oi-fries');
        final text = _text(tester, 'order-edit-totals-change');
        expect(
          text,
          '$was $_lri₪108.00$_pdi ← $now $_lri₪93.00$_pdi '
          '($_lri−₪15.00$_pdi)',
        );
      });
    }

    testWidgets('the tax row and "Discount kept"', (tester) async {
      final h = _H(
        // 10800 − 1000 = 9800 taxable; 17% → 1666; grand 11466.
        order: detail(items: _items(), discount: 1000, tax: 1666),
      );
      h.tax.tax = const BranchTax(enabled: true, rateBp: 1700);
      await _open(tester, h);
      expect(
        _text(tester, 'order-edit-discount-kept'),
        'Discount $_lri₪10.00$_pdi kept',
      );
      expect(_text(tester, 'order-edit-tax'), '₪16.66');
      await _tap(tester, 'cart-remove-sent-oi-fries');
      // 9300 − 1000 = 8300 → 1411; grand 9300 − 1000 + 1411 = 9711.
      expect(_text(tester, 'order-edit-tax'), '₪14.11');
      expect(
        _text(tester, 'order-edit-totals-change'),
        'Was $_lri₪114.66$_pdi → Now $_lri₪97.11$_pdi ($_lri−₪17.55$_pdi)',
      );
    });

    testWidgets('nothing changed yet: "No changes yet", Send off', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditNoChanges,
      );
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('every line removed: "Cancel the order instead", with the '
        'Cancel-order link only for an order the till can show', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      for (final id in ['oi-burger', 'oi-fries', 'oi-cola', 'oi-tea']) {
        await _tap(tester, 'cart-remove-sent-$id');
      }
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditAllRemovedUseCancel,
      );
      expect(_sendEnabled(tester), isFalse);
      // This till holds no row for the order: no dead link is drawn.
      expect(_key('order-edit-cancel-order'), findsNothing);
      // An added line makes it an edit again.
      h.cart.addItem(_lemonade);
      await tester.pumpAndSettle();
      expect(
        _text(tester, 'order-edit-send-block-text'),
        isNot(l10n.posOrderEditAllRemovedUseCancel),
      );
    });

    testWidgets('a discount above the new subtotal: the reason and "Lower '
        'discount"', (tester) async {
      final l10n = await _l10n();
      final h = _H(order: detail(items: _items(), discount: 9000));
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-burger');
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditDiscountExceedsNewSubtotal,
      );
      expect(
        find.descendant(
          of: _key('order-edit-lower-discount'),
          matching: find.text(l10n.posOrderEditLowerDiscount),
        ),
        findsOneWidget,
      );
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('"Lower discount" opens the existing discount sheet, then '
        're-baselines with every intent kept (D10)', (tester) async {
      final l10n = await _l10n();
      final h = _H(order: detail(items: _items(), discount: 9000));
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-burger');
      await _tap(tester, 'order-edit-lower-discount');
      expect(_key('discount-value-field'), findsOneWidget);
      expect(h.transport.ops, isEmpty);

      // The discount was lowered to 1000 as its own committed change.
      h.details.byId['order-1'] = detail(items: _items(), discount: 1000);
      Navigator.of(tester.element(_key('discount-value-field'))).pop();
      await tester.pumpAndSettle();

      expect(h.edit.baseline!.discountMinor, 1000);
      expect(
        h.c
            .read(cartControllerProvider)
            .lines
            .singleWhere((l) => l.lineId == 'sent-oi-burger')
            .editRemoved,
        isTrue,
      );
      expect(
        find.text(l10n.posOrderEditDiscountExceedsNewSubtotal),
        findsNothing,
      );
      // 2800 − 1000: the Waiting burger's removal is preselected, so Send is
      // ready.
      expect(
        _text(tester, 'order-edit-totals-change'),
        'Was $_lri₪98.00$_pdi → Now $_lri₪18.00$_pdi ($_lri−₪80.00$_pdi)',
      );
      expect(_sendEnabled(tester), isTrue);
      expect(h.transport.ops, isEmpty);
    });

    testWidgets('"Cancel order" opens the existing cancel sheet; a cancelled '
        'order ends the edit quietly', (tester) async {
      final l10n = await _l10n();
      final store = InMemoryRecentOrdersStore();
      final at = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await store.persist(kDemoSyncScope.key, [
        PosRecentOrder.discovered(
          PosOrderSnapshot(
            orderId: 'order-1',
            orderCode: '#A1B2C3',
            revision: 3,
            status: 'preparing',
            settlement: PosSettlement.unpaid,
            subtotalMinor: 10800,
            discountTotalMinor: 0,
            taxTotalMinor: 0,
            grandTotalMinor: 10800,
            createdAt: at,
            updatedAt: at,
            syncAt: at,
            orderType: 'dine_in',
            tableLabel: '4',
            currencyCode: 'ILS',
          ),
        ),
      ]);
      final h = _H(
        extra: [
          posSyncScopeProvider.overrideWithValue(kDemoSyncScope),
          posRecentOrdersStoreProvider.overrideWithValue(store),
          posSyncCursorStoreProvider.overrideWithValue(
            InMemorySyncCursorStore(),
          ),
        ],
      );
      await _open(tester, h);
      for (final id in ['oi-burger', 'oi-fries', 'oi-cola', 'oi-tea']) {
        await _tap(tester, 'cart-remove-sent-$id');
      }
      await _tap(tester, 'order-edit-cancel-order');
      expect(_key('cancel-order-sheet'), findsOneWidget);

      // The order was cancelled through that sheet.
      h.details.byId['order-1'] = detail(items: _items(), status: 'voided');
      Navigator.of(tester.element(_key('cancel-order-sheet'))).pop();
      await tester.pumpAndSettle();

      expect(h.c.read(cartControllerProvider).isEditing, isFalse);
      expect(h.edit.phase, OrderEditPhase.idle);
      expect(find.text(l10n.posOrderEditErrorNotEditable), findsNothing);
      expect(h.transport.ops, isEmpty);
    });

    testWidgets('a free order without the full-comp right', (tester) async {
      final l10n = await _l10n();
      final h = _H(
        caps: _caps(fullComp: false),
        // Keep only Cola + Tea (1300) under a 1300 discount: total 0.
        order: detail(items: _items(), discount: 1300),
      );
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-burger');
      await _tap(tester, 'cart-remove-sent-oi-fries');
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posDiscountFullCompDenied,
      );
      expect(_sendEnabled(tester), isFalse);
    });

    testWidgets('offline: "Editing needs a connection"', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      expect(_sendEnabled(tester), isTrue);
      h.c
          .read(posOfflineModeProvider.notifier)
          .recordOfflineCacheServed(
            snapshotFetchedAt: DateTime.utc(2026, 10, 9),
          );
      await tester.pumpAndSettle();
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditNeedsConnection,
      );
      expect(_sendEnabled(tester), isFalse);
    });
  });

  group('reasons', () {
    testWidgets('no chips for a pure addition or increase', (tester) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      h.cart.addItem(_lemonade);
      await tester.pumpAndSettle();
      expect(_key('order-edit-reasons'), findsNothing);
      expect(_key('order-edit-send-block'), findsNothing);
      expect(_sendEnabled(tester), isTrue);
    });

    testWidgets('removing a Waiting ticket preselects "Customer changed '
        'mind"', (tester) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-burger');
      expect(_key('order-edit-reasons'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(_key('order-edit-reason-customer_changed_mind'))
            .selected,
        isTrue,
      );
      expect(_sendEnabled(tester), isTrue);
    });

    testWidgets('anything the kitchen has started: the cashier must choose; '
        '"Other" needs text', (tester) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-fries');
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditReasonRequired,
      );
      for (final code in kOrderEditReasonCodes) {
        expect(
          tester.widget<ChoiceChip>(_key('order-edit-reason-$code')).selected,
          isFalse,
        );
      }
      expect(_sendEnabled(tester), isFalse);

      await _tap(tester, 'order-edit-reason-other');
      expect(
        _text(tester, 'order-edit-send-block-text'),
        l10n.posOrderEditReasonOtherRequired,
      );
      await tester.enterText(_key('order-edit-reason-other'), '  ');
      await tester.pumpAndSettle();
      expect(_sendEnabled(tester), isFalse);
      await tester.enterText(_key('order-edit-reason-other'), 'Spilled');
      await tester.pumpAndSettle();
      expect(_key('order-edit-send-block'), findsNothing);
      expect(_sendEnabled(tester), isTrue);
    });
  });

  group('send', () {
    testWidgets('finished food: the confirm comes BEFORE anything is sent', (
      tester,
    ) async {
      final l10n = await _l10n();
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-remove-sent-oi-cola');
      await _tap(tester, 'order-edit-reason-kitchen_issue');

      await _tap(tester, 'order-edit-send');
      expect(_key('order-edit-finished-food-sheet'), findsOneWidget);
      expect(find.text(l10n.posOrderEditAlreadyCookedTitle), findsOneWidget);
      expect(
        _text(tester, 'order-edit-finished-food-totals'),
        'Was $_lri₪108.00$_pdi → Now $_lri₪100.00$_pdi ($_lri−₪8.00$_pdi)',
      );
      expect(h.transport.ops, isEmpty);

      await _tap(tester, 'order-edit-finished-food-cancel');
      expect(h.transport.ops, isEmpty);
      expect(h.c.read(cartControllerProvider).isEditing, isTrue);

      await _tap(tester, 'order-edit-send');
      await _tap(tester, 'order-edit-finished-food-confirm');
      expect(h.transport.ops, hasLength(1));
      final payload = h.transport.ops.single['payload'] as Map;
      expect(payload['reason_code'], 'kitchen_issue');
      expect(payload['changes'], [
        {'op': 'remove', 'order_item_id': 'oi-cola'},
      ]);
    });

    testWidgets('applied: the toast follows the server, and the edit ends '
        'once the detail proves it', (tester) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');

      expect(h.transport.ops, hasLength(1));
      expect(find.text('Change 1 sent: kitchen must confirm'), findsOneWidget);
      expect(h.c.read(cartControllerProvider).isEditing, isFalse);
      expect(h.edit.phase, OrderEditPhase.idle);
    });

    testWidgets('paper: "Change 1 saved", never "printed"', (tester) async {
      final l10n = await _l10n();
      final h = _H(
        order: detail(items: _items(), channel: PosKitchenChannel.paper),
        ack: false,
        channel: 'paper',
      );
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');
      expect(find.text('Change 1 saved'), findsOneWidget);
      expect(find.text(l10n.posOrderEditResultPrinted(1)), findsNothing);
      expect(find.textContaining('printed'), findsNothing);
    });

    testWidgets('a refusal says why and keeps the edit open', (tester) async {
      final l10n = await _l10n();
      final h = _H(script: [_refused('too_many_changes')]);
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');
      expect(find.text(l10n.posOrderEditErrorTooManyChanges), findsOneWidget);
      expect(h.c.read(cartControllerProvider).isEditing, isTrue);
      expect(h.edit.phase, OrderEditPhase.active);
      expect(_sendEnabled(tester), isTrue);
    });

    testWidgets('an unknown outcome: the banner and Send retry the SAME '
        'identity', (tester) async {
      final l10n = await _l10n();
      final h = _H(
        script: [
          (op) => {'ok': true, 'results': <Object?>[]},
          (op) => _applied(op),
        ],
      );
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');
      expect(
        _text(tester, 'pos-order-edit-banner-text'),
        l10n.posOrderEditRetry,
      );
      expect(
        tester.widget<TextButton>(_key('pos-order-edit-discard')).onPressed,
        isNull,
      );
      expect(_sendEnabled(tester), isTrue);

      await _tap(tester, 'pos-order-edit-retry');
      expect(h.transport.ops, hasLength(2));
      expect(
        h.transport.ops[1]['local_operation_id'],
        h.transport.ops[0]['local_operation_id'],
      );
    });

    testWidgets('D7: a bill this session printed rides the payload, and the '
        'edit offers a new one', (tester) async {
      final l10n = await _l10n();
      final h = _H(
        extra: [
          receiptPrintControllerProvider.overrideWith(
            () => _BillPrinted(DateTime.utc(2026, 10, 9, 11, 30)),
          ),
        ],
      );
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');
      final payload = h.transport.ops.single['payload'] as Map;
      expect(payload['bill_presented_at'], '2026-10-09T11:30:00.000Z');

      // The toast first, then "Bill changed: print new bill?".
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(l10n.posOrderEditBillChanged), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, l10n.posPrintBillAction),
        findsOneWidget,
      );
    });

    testWidgets('no bill printed here: nothing claims one was presented', (
      tester,
    ) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-increase-sent-oi-burger');
      await _tap(tester, 'order-edit-send');
      final payload = h.transport.ops.single['payload'] as Map;
      expect(payload.containsKey('bill_presented_at'), isFalse);
    });
  });

  group('modify', () {
    testWidgets('a sent line\'s sheet edits options only; "Just 1" splits one '
        'unit off', (tester) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-edit-sent-oi-burger');

      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(_key('modifier-item-quantity-row'), findsNothing);
      expect(_key('modifier-apply-to-row'), findsOneWidget);
      expect(find.text('All 2'), findsOneWidget);
      await _tap(tester, 'modifier-apply-to-one');
      await tester.tap(find.byKey(const ValueKey('modifier-option-opt-bacon')));
      await tester.pumpAndSettle();
      await _tap(tester, 'modifier-add-button');

      final lines = h.c.read(cartControllerProvider).lines;
      final burgers = lines.where((l) => l.menuItemId == 'mi-burger').toList();
      expect(burgers.map((l) => (l.lineId, l.quantity)), [
        ('sent-oi-burger', 1),
        ('sent-oi-burger-p1', 1),
      ]);
      expect(burgers[1].modifiers.single.optionId, 'opt-bacon');
      // +1 Bacon at 500 on one burger.
      expect(
        _text(tester, 'order-edit-totals-change'),
        'Was $_lri₪108.00$_pdi → Now $_lri₪113.00$_pdi ($_lri+₪5.00$_pdi)',
      );
      // A modify is a removing change: the reason chips appear.
      expect(_key('order-edit-reasons'), findsOneWidget);
    });

    testWidgets('a single unit offers no "Apply to"', (tester) async {
      final h = _H();
      await _open(tester, h);
      await _tap(tester, 'cart-edit-sent-oi-fries');
      expect(find.byType(ModifierSelectionSheet), findsOneWidget);
      expect(_key('modifier-apply-to-row'), findsNothing);
      expect(_key('modifier-item-quantity-row'), findsNothing);
    });
  });
}
