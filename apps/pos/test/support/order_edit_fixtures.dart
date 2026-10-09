import 'package:restoflow_domain/restoflow_domain.dart' show KitchenMeat;
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_detail_repository.dart';
import 'package:restoflow_pos/src/data/order_edit_baseline.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/payment.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';

/// ORDER-EDIT-001E — shared fixtures for the edit-engine suites: an
/// authoritative detail built through the PUBLIC constructors (the parser has
/// its own suite), a live menu, and edit-cart lines bound to sent lines.
///
/// Every amount is a literal integer minor value (D-007).

const kFeaturesOn = PosBranchFeatures(
  orderEditEnabled: true,
  finishedFoodManagerOnly: false,
);

PosOrderDetailModifier detailMod(
  String optionId,
  String name, {
  int price = 0,
  int quantity = 1,
  String group = 'Toppings',
  KitchenMeat? meat,
}) => PosOrderDetailModifier(
  optionName: name,
  priceMinor: price,
  quantity: quantity,
  modifierName: group,
  modifierOptionId: optionId,
  meat: meat,
);

PosOrderDetailItem detailItem(
  String id, {
  String? menuItemId,
  String name = 'Item',
  int quantity = 1,
  int unit = 1000,
  int lineDiscount = 0,
  int? lineTotal,
  List<PosOrderDetailModifier> modifiers = const <PosOrderDetailModifier>[],
  String? notes,
  String unitStatus = 'submitted',
  Object? legacy = false,
  String? roundId,
  bool identified = true,
}) {
  var configured = unit;
  for (final m in modifiers) {
    configured += m.priceMinor * m.quantity;
  }
  return PosOrderDetailItem(
    name: name,
    quantity: quantity,
    unitPriceMinor: unit,
    lineDiscountMinor: lineDiscount,
    lineTotalMinor: lineTotal ?? quantity * configured - lineDiscount,
    modifiers: modifiers,
    notes: notes,
    serviceRoundId: roundId,
    orderItemId: identified ? id : null,
    menuItemId: identified ? (menuItemId ?? 'mi-$id') : null,
    status: 'pending',
    unitStatus: unitStatus,
    legacy: legacy is bool ? legacy : null,
  );
}

PosOrderDetail detail({
  required List<PosOrderDetailItem> items,
  String orderType = 'dine_in',
  String status = 'preparing',
  PosKitchenChannel? channel = PosKitchenChannel.kds,
  PosBranchFeatures? features = kFeaturesOn,
  int discount = 0,
  int? tax,
  int? grand,
  int? subtotal,
  bool paid = false,
  String? tableLabel = '4',
}) {
  var sum = 0;
  for (final i in items) {
    sum += i.lineTotalMinor;
  }
  final sub = subtotal ?? sum;
  final t = tax ?? 0;
  return PosOrderDetail(
    orderId: 'order-1',
    orderCode: '#A1B2C3',
    orderType: orderType,
    status: status,
    revision: 3,
    currencyCode: 'ILS',
    subtotalMinor: sub,
    discountTotalMinor: discount,
    taxTotalMinor: t,
    grandTotalMinor: grand ?? (sub - discount + t),
    items: items,
    rounds: const <PosOrderDetailRound>[],
    tableLabel: tableLabel,
    payment: paid
        ? PosOrderDetailPayment(
            paymentId: '00000000-0000-0000-0000-000000000001',
            status: PaymentStatus.completed,
            method: PaymentMethod.cash,
            amountMinor: sub,
            tenderedMinor: sub,
            changeMinor: 0,
            paidAt: DateTime.utc(2026, 10, 9, 12),
          )
        : null,
    kitchenChannel: channel,
    branchFeatures: features,
  );
}

PosModifierGroup menuGroup(
  String id,
  String menuItemId,
  List<PosModifierOption> options, {
  String name = 'Toppings',
}) => PosModifierGroup(
  id: id,
  menuItemId: menuItemId,
  name: name,
  options: options,
);

DemoMenuItem menuItem(
  String id, {
  String name = 'Item',
  int price = 1000,
  bool unavailable = false,
}) => DemoMenuItem(
  id: id,
  name: name,
  priceMinor: price,
  categoryId: 'cat',
  categoryName: 'Cat',
  availability: unavailable ? 'unavailable' : 'available',
);

PosMenuData menuOf(
  List<DemoMenuItem> items, {
  List<PosModifierGroup> groups = const <PosModifierGroup>[],
}) => PosMenuData(
  categories: const [],
  items: items,
  currencyCode: 'ILS',
  modifierGroups: groups,
);

OrderEditBaseline baselineOf(PosOrderDetail d, {PosMenuData? menu}) {
  final verdict = OrderEditBaseline.fromDetail(d, menu: menu);
  final b = verdict.baseline;
  if (b == null) {
    throw StateError('fixture is not editable: ${verdict.ineligibility}');
  }
  return b;
}

SelectedModifier mod(
  String optionId,
  String name, {
  int price = 0,
  int quantity = 1,
  String group = 'Toppings',
  KitchenMeat? meat,
}) => SelectedModifier(
  optionId: optionId,
  groupName: group,
  optionName: name,
  priceDeltaMinor: price,
  quantity: quantity,
  kitchenMeat: meat,
);

/// The cart line loaded for [s] (`'sent-<id>'`), optionally changed.
OrderEditCartLine sent(
  OrderEditSourceLine s, {
  int? quantity,
  List<SelectedModifier>? modifiers,
  Object? note = _keep,
  String? lineId,
  bool removed = false,
}) {
  final q = quantity ?? s.quantity;
  final mods = modifiers ?? s.toSelectedModifiers();
  final n = identical(note, _keep) ? s.notes : note as String?;
  return OrderEditCartLine(
    sourceOrderItemId: s.orderItemId,
    removed: removed,
    line: CartLineView(
      lineId: lineId ?? 'sent-${s.orderItemId}',
      menuItemId: s.menuItemId,
      name: s.name,
      quantity: q,
      unitPriceMinor: s.unitPriceMinor,
      lineTotalMinor: orderEditLineTotalMinor(
        source: s,
        quantity: q,
        modifiers: mods,
        unitPriceMinor: s.unitPriceMinor,
        note: n,
      ),
      currencyCode: 'ILS',
      modifiers: mods,
      note: n,
    ),
  );
}

/// A part split off [s] (`'sent-<id>-p<n>'`).
OrderEditCartLine part(
  OrderEditSourceLine s,
  int n, {
  required int quantity,
  List<SelectedModifier>? modifiers,
  Object? note = _keep,
}) => sent(
  s,
  quantity: quantity,
  modifiers: modifiers,
  note: note,
  lineId: 'sent-${s.orderItemId}-p$n',
);

/// A line the cashier added from the menu.
OrderEditCartLine added(
  String lineId,
  String menuItemId, {
  String name = 'Added',
  int quantity = 1,
  int unit = 1000,
  List<SelectedModifier> modifiers = const <SelectedModifier>[],
  String? note,
}) => OrderEditCartLine(
  line: CartLineView(
    lineId: lineId,
    menuItemId: menuItemId,
    name: name,
    quantity: quantity,
    unitPriceMinor: unit,
    lineTotalMinor: configuredLineTotalMinor(
      basePriceMinor: unit,
      modifiers: modifiers,
      quantity: quantity,
    ),
    currencyCode: 'ILS',
    modifiers: modifiers,
    note: note,
  ),
);

/// The unchanged edit cart of [b].
List<OrderEditCartLine> untouched(OrderEditBaseline b) => [
  for (final s in b.lines) sent(s),
];

const Object _keep = Object();
