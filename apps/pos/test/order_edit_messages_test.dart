import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/order_edit_diff.dart';
import 'package:restoflow_pos/src/data/order_edit_read_model.dart';
import 'package:restoflow_pos/src/data/order_edit_response.dart';
import 'package:restoflow_pos/src/data/staff_capabilities.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/order_edit_controller.dart';
import 'package:restoflow_pos/src/state/receipt_print_controller.dart';
import 'package:restoflow_pos/src/widgets/order_edit_cart_widgets.dart';
import 'package:restoflow_pos/src/widgets/order_edit_messages.dart';

import 'support/order_edit_fixtures.dart';

/// ORDER-EDIT-001E — the edit flow's PURE UI policy (plan §8a/§8b):
///
///  * every [OrderEditNotice], [OrderEditSendBlock] and [OrderEditEntryResult]
///    maps to its existing, translated string — never raw backend text;
///  * the result toast follows the server's landing facts, and a paper edit
///    is "saved", never "printed" (the change slip is ORDER-EDIT-001F);
///  * a sent line's controls follow its flags and the session's rights;
///  * the reason is the cashier's chip, or the plan's preselect, never a
///    stale draft of an earlier edit;
///  * decision D7: only a bill THIS session handed to a printer counts.

OrderEditApplied _applied({
  int number = 3,
  bool ack = false,
  PosKitchenChannel channel = PosKitchenChannel.kds,
  String? newRound,
}) => OrderEditApplied(
  orderEditId: 'edit-$number',
  editNumber: number,
  revision: 9,
  kitchenChannel: channel,
  kitchenAckRequired: ack,
  newRoundId: newRound,
);

PosStaffCapabilities _caps({
  Object? voidOrder = true,
  String role = 'cashier',
  bool managerOnly = false,
}) => PosStaffCapabilities.fromJson(
  {'apply_discount': true, if (voidOrder != null) 'void_order': voidOrder},
  role: role,
  branchFeatures: {
    'order_edit_enabled': true,
    'order_edit_finished_food_manager_only': managerOnly,
  },
);

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('notices', () {
    test('every notice has its own translated message', () {
      final expected = <OrderEditNotice, String>{
        OrderEditNotice.rebased: l10n.posOrderEditRebased,
        OrderEditNotice.reasonRequired: l10n.posOrderEditReasonRequired,
        OrderEditNotice.allRemovedUseCancel:
            l10n.posOrderEditAllRemovedUseCancel,
        OrderEditNotice.discountExceedsOrderTotal:
            l10n.posDiscountExceedsOrderTotal,
        OrderEditNotice.fullCompDenied: l10n.posDiscountFullCompDenied,
        OrderEditNotice.removalNotPermitted:
            l10n.posOrderEditErrorRemovalNotPermitted,
        OrderEditNotice.finishedFoodNeedsManager:
            l10n.posOrderEditErrorFinishedFoodNeedsManager,
        OrderEditNotice.notAllowed: l10n.posOrderEditErrorNotAllowed,
        OrderEditNotice.featureDisabled: l10n.posOrderEditErrorFeatureDisabled,
        OrderEditNotice.notEditable: l10n.posOrderEditErrorNotEditable,
        OrderEditNotice.alreadyPaid: l10n.posOrderEditErrorAlreadyPaid,
        OrderEditNotice.kitchenModeChanged:
            l10n.posOrderEditErrorKitchenModeChanged,
        OrderEditNotice.taxModeUnsupported:
            l10n.posOrderEditErrorTaxModeUnsupported,
        OrderEditNotice.lineHasDiscount: l10n.posOrderEditErrorLineHasDiscount,
        OrderEditNotice.legacyLine: l10n.posOrderEditErrorLegacyLine,
        OrderEditNotice.itemUnavailable: l10n.posOrderEditErrorItemUnavailable(
          'Cola, Fries',
        ),
        OrderEditNotice.optionNotInScope:
            l10n.posOrderEditErrorOptionNotInScope,
        OrderEditNotice.prepSnapshotStale: l10n.posPrepSnapshotStale,
        OrderEditNotice.invalid: l10n.posOrderEditErrorInvalid,
        OrderEditNotice.tooManyChanges: l10n.posOrderEditErrorTooManyChanges,
        OrderEditNotice.blockedUnacknowledged:
            l10n.posOrderEditBlockedUnacknowledged,
        OrderEditNotice.slipTooLarge: l10n.posOrderEditErrorSlipTooLarge,
        OrderEditNotice.retry: l10n.posOrderEditRetry,
        OrderEditNotice.conflictBlocked: l10n.posAdditionConflictBlocked,
        OrderEditNotice.hydrating: l10n.posAdditionLoadingPending,
        OrderEditNotice.needsConnection: l10n.posOrderEditNeedsConnection,
        OrderEditNotice.detailUnavailable: l10n.posAdditionFailedRetry,
      };
      expect(expected.keys.toSet(), OrderEditNotice.values.toSet());
      for (final e in expected.entries) {
        expect(
          orderEditNoticeMessage(l10n, e.key, items: const ['Cola', 'Fries']),
          e.value,
          reason: e.key.name,
        );
      }
    });

    test('a rebase names what it left out on its own line', () {
      final message = orderEditResultMessage(
        l10n,
        const OrderEditResult(
          status: OrderEditSubmitStatus.refused,
          notice: OrderEditNotice.rebased,
          droppedItems: ['Burger', 'Fries'],
        ),
      );
      expect(
        message,
        '${l10n.posOrderEditRebased}\n'
        '${l10n.posOrderEditRebaseDropped('Burger, Fries')}',
      );
    });

    test('a send the footer already explains says nothing more', () {
      expect(
        orderEditResultMessage(
          l10n,
          const OrderEditResult(
            status: OrderEditSubmitStatus.notSent,
            sendBlock: OrderEditSendBlock.reasonRequired,
          ),
        ),
        isNull,
      );
    });
  });

  group('the applied toast', () {
    test('the kitchen must confirm wins over a new ticket', () {
      expect(
        orderEditAppliedMessage(l10n, _applied(ack: true, newRound: 'round-2')),
        'Change 3 sent: kitchen must confirm',
      );
    });

    test('a KDS change that landed only in a new round: new ticket', () {
      expect(
        orderEditAppliedMessage(l10n, _applied(newRound: 'round-2')),
        'Change 3 sent: new ticket for the kitchen',
      );
    });

    test('a KDS change without a new round: saved', () {
      expect(orderEditAppliedMessage(l10n, _applied()), 'Change 3 saved');
    });

    test('paper is saved — never "printed" before ORDER-EDIT-001F', () {
      final message = orderEditAppliedMessage(
        l10n,
        _applied(channel: PosKitchenChannel.paper, newRound: 'round-2'),
      );
      expect(message, 'Change 3 saved');
      expect(message, isNot(l10n.posOrderEditResultPrinted(3)));
      expect(message.toLowerCase(), isNot(contains('print')));
    });

    test('applied but not yet proven: the honest "saved"', () {
      expect(
        orderEditAppliedMessage(
          l10n,
          _applied(ack: true),
          refreshRequired: true,
        ),
        'Change 3 saved',
      );
    });

    test('remade dishes ride their own line (decision D8)', () {
      expect(
        orderEditAppliedMessage(l10n, _applied(ack: true), remakeCount: 2),
        'Change 3 sent: kitchen must confirm\n'
        'Already cooked: 2 dishes will be remade',
      );
      expect(
        orderEditAppliedMessage(l10n, _applied(), remakeCount: 1),
        'Change 3 saved\nAlready cooked: 1 dish will be remade',
      );
    });

    test('orderEditResultMessage carries the toast for an applied result', () {
      expect(
        orderEditResultMessage(
          l10n,
          OrderEditResult(
            status: OrderEditSubmitStatus.applied,
            applied: _applied(ack: true),
            remakeCount: 1,
          ),
        ),
        'Change 3 sent: kitchen must confirm\n'
        'Already cooked: 1 dish will be remade',
      );
    });
  });

  test('every send block has its footer line', () {
    final expected = <OrderEditSendBlock, String>{
      OrderEditSendBlock.noChanges: l10n.posOrderEditNoChanges,
      OrderEditSendBlock.wouldEmpty: l10n.posOrderEditAllRemovedUseCancel,
      OrderEditSendBlock.discountExceeds:
          l10n.posOrderEditDiscountExceedsNewSubtotal,
      OrderEditSendBlock.fullCompDenied: l10n.posDiscountFullCompDenied,
      OrderEditSendBlock.tooManyChanges: l10n.posOrderEditErrorTooManyChanges,
      OrderEditSendBlock.invalidLineChange: l10n.posOrderEditErrorInvalid,
      OrderEditSendBlock.removalNotPermitted:
          l10n.posOrderEditErrorRemovalNotPermitted,
      OrderEditSendBlock.finishedFoodNeedsManager:
          l10n.posOrderEditErrorFinishedFoodNeedsManager,
      OrderEditSendBlock.offline: l10n.posOrderEditNeedsConnection,
      OrderEditSendBlock.reasonRequired: l10n.posOrderEditReasonRequired,
      OrderEditSendBlock.reasonOtherRequired:
          l10n.posOrderEditReasonOtherRequired,
    };
    expect(expected.keys.toSet(), OrderEditSendBlock.values.toSet());
    for (final e in expected.entries) {
      expect(orderEditSendBlockMessage(l10n, e.key), e.value);
    }
  });

  test('every entry result says what it came to', () {
    final expected = <OrderEditEntryResult, String?>{
      OrderEditEntryResult.entered: null,
      OrderEditEntryResult.superseded: null,
      // The caller offers Park / Clear instead.
      OrderEditEntryResult.cartNotEmpty: null,
      OrderEditEntryResult.hydrating: l10n.posAdditionLoadingPending,
      OrderEditEntryResult.busy: l10n.posOrderEditCartNotEmptyBody,
      OrderEditEntryResult.additionActive: l10n.posOrderEditCartNotEmptyBody,
      OrderEditEntryResult.offline: l10n.posOrderEditNeedsConnection,
      OrderEditEntryResult.pendingAttempt: l10n.posOrderEditPendingBlocked,
      // The anti-oracle: the server does not know the order yet.
      OrderEditEntryResult.orderNotFound:
          l10n.posOrderEditBlockedUnacknowledged,
      OrderEditEntryResult.featureDisabled:
          l10n.posOrderEditErrorFeatureDisabled,
      OrderEditEntryResult.notEditable: l10n.posOrderEditErrorNotEditable,
      OrderEditEntryResult.alreadyPaid: l10n.posOrderEditErrorAlreadyPaid,
      OrderEditEntryResult.kitchenModeChanged:
          l10n.posOrderEditErrorKitchenModeChanged,
      OrderEditEntryResult.detailUnavailable: l10n.posAdditionFailedRetry,
    };
    expect(expected.keys.toSet(), OrderEditEntryResult.values.toSet());
    for (final e in expected.entries) {
      expect(orderEditEntryMessage(l10n, e.key), e.value, reason: e.key.name);
    }
  });

  group('line controls', () {
    final menu = menuOf([
      menuItem('mi-burger', name: 'Burger', price: 4000),
      menuItem('mi-cola', name: 'Cola', price: 800, unavailable: true),
    ]);
    final d = detail(
      items: [
        detailItem('oi-1', menuItemId: 'mi-burger', name: 'Burger', unit: 4000),
        detailItem(
          'oi-2',
          menuItemId: 'mi-burger',
          name: 'Burger',
          unit: 4000,
          quantity: 2,
          lineDiscount: 500,
        ),
        detailItem(
          'oi-3',
          menuItemId: 'mi-burger',
          name: 'Burger',
          unit: 4000,
          legacy: null,
        ),
        detailItem('oi-4', menuItemId: 'mi-gone', name: 'Soup', unit: 1200),
        detailItem('oi-5', menuItemId: 'mi-cola', name: 'Cola', unit: 800),
        detailItem(
          'oi-6',
          menuItemId: 'mi-burger',
          name: 'Burger',
          unit: 4000,
          unitStatus: 'ready',
        ),
      ],
    );
    final baseline = baselineOf(d, menu: menu);
    CartLineView line(String id, {int? quantity, bool removed = false}) {
      final s = baseline.lineFor(id)!;
      final l = sent(s, quantity: quantity, removed: removed);
      return CartLineView(
        lineId: l.line.lineId,
        menuItemId: l.line.menuItemId,
        name: l.line.name,
        quantity: l.line.quantity,
        unitPriceMinor: l.line.unitPriceMinor,
        lineTotalMinor: l.line.lineTotalMinor,
        currencyCode: 'ILS',
        modifiers: l.line.modifiers,
        editSource: s,
        editRemoved: removed,
      );
    }

    test('an editable sent line: every control', () {
      final c = orderEditLineControls(
        line('oi-1'),
        baseline: baseline,
        capabilities: _caps(),
      );
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit, c.canUndo],
        [true, true, true, true, false],
      );
      expect(c.hint, isNull);
      expect(c.managerNeeded, isFalse);
    });

    test('remove only (a line discount; a legacy price) and keep or remove '
        'only (left the menu, D11): the trash alone', () {
      for (final (id, hint) in [
        ('oi-2', OrderEditLineHint.removeOnlyDiscount),
        ('oi-3', OrderEditLineHint.removeOnlyLegacy),
        ('oi-4', OrderEditLineHint.keepOrRemoveOnly),
      ]) {
        final c = orderEditLineControls(
          line(id),
          baseline: baseline,
          capabilities: _caps(),
        );
        expect(
          [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit],
          [false, false, true, false],
          reason: id,
        );
        expect(c.hint, hint, reason: id);
      }
    });

    test('an unsellable item withholds "+" only', () {
      final c = orderEditLineControls(
        line('oi-5'),
        baseline: baseline,
        capabilities: _caps(),
      );
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit],
        [false, true, true, true],
      );
    });

    test('void_order KNOWN denied: "+" stays, removing controls go, and '
        '"−" only takes back an increase', () {
      final denied = _caps(voidOrder: false);
      final c = orderEditLineControls(
        line('oi-1'),
        baseline: baseline,
        capabilities: denied,
      );
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit],
        [true, false, false, false],
      );
      final grown = orderEditLineControls(
        line('oi-1', quantity: 2),
        baseline: baseline,
        capabilities: denied,
      );
      expect(grown.canDecrease, isTrue);
      expect(grown.canRemove, isFalse);
    });

    test('void_order UNKNOWN is not denied (D14)', () {
      final c = orderEditLineControls(
        line('oi-1'),
        baseline: baseline,
        capabilities: _caps(voidOrder: null),
      );
      expect(c.canRemove, isTrue);
      expect(c.canEdit, isTrue);
    });

    test('finished food with the switch ON: a cashier needs a manager on a '
        'Ready line; a manager does not', () {
      // The detail's switch is fresher than the session probe, so it is the
      // one that counts.
      final off = orderEditLineControls(
        line('oi-6'),
        baseline: baseline,
        capabilities: _caps(managerOnly: true),
      );
      expect(off.managerNeeded, isFalse);
      final on = baselineOf(
        detail(
          items: d.items,
          features: const PosBranchFeatures(
            orderEditEnabled: true,
            finishedFoodManagerOnly: true,
          ),
        ),
        menu: menu,
      );
      CartLineView ready() {
        final s = on.lineFor('oi-6')!;
        return CartLineView(
          lineId: 'sent-oi-6',
          menuItemId: s.menuItemId,
          name: s.name,
          quantity: s.quantity,
          unitPriceMinor: s.unitPriceMinor,
          lineTotalMinor: s.lineTotalMinor,
          currencyCode: 'ILS',
          editSource: s,
        );
      }

      final cashier = orderEditLineControls(
        ready(),
        baseline: on,
        capabilities: _caps(),
      );
      expect(cashier.managerNeeded, isTrue);
      expect(
        [cashier.canIncrease, cashier.canRemove, cashier.canEdit],
        [true, false, false],
      );
      final manager = orderEditLineControls(
        ready(),
        baseline: on,
        capabilities: _caps(role: 'manager'),
      );
      expect(manager.managerNeeded, isFalse);
      expect(manager.canRemove, isTrue);
    });

    test('a struck-through line offers Undo only; a lock turns it off', () {
      final c = orderEditLineControls(
        line('oi-1', removed: true),
        baseline: baseline,
        capabilities: _caps(),
      );
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit, c.canUndo],
        [false, false, false, false, true],
      );
      expect(
        orderEditLineControls(
          line('oi-1', removed: true),
          baseline: baseline,
          locked: true,
        ).canUndo,
        isFalse,
      );
    });

    test('a frozen attempt locks every control but keeps the hints', () {
      final c = orderEditLineControls(
        line('oi-2'),
        baseline: baseline,
        capabilities: _caps(),
        locked: true,
      );
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit],
        [false, false, false, false],
      );
      expect(c.hint, OrderEditLineHint.removeOnlyDiscount);
    });

    test('an added line is an ordinary cart line, up to 999', () {
      const added = CartLineView(
        lineId: 'line-9',
        menuItemId: 'mi-burger',
        name: 'Burger',
        quantity: 999,
        unitPriceMinor: 4000,
        lineTotalMinor: 3996000,
        currencyCode: 'ILS',
      );
      final c = orderEditLineControls(added, baseline: baseline);
      expect(
        [c.canIncrease, c.canDecrease, c.canRemove, c.canEdit],
        [false, true, true, true],
      );
    });
  });

  group('the reason', () {
    final d = detail(
      items: [
        detailItem('oi-1', name: 'Burger', unit: 4000),
        detailItem('oi-2', name: 'Fries', unit: 1500, unitStatus: 'preparing'),
      ],
    );
    final b = baselineOf(d);
    final waitingRemoved = planOrderEdit(b, [
      sent(b.lineFor('oi-1')!, removed: true),
      sent(b.lineFor('oi-2')!),
    ], tax: BranchTax.disabled);
    final cookingRemoved = planOrderEdit(b, [
      sent(b.lineFor('oi-1')!),
      sent(b.lineFor('oi-2')!, removed: true),
    ], tax: BranchTax.disabled);

    test('untouched chips: the preselect, only when every removing change '
        'touches a ticket still Waiting', () {
      expect(
        orderEditEffectiveReason(
          const OrderEditReasonDraft(),
          generation: 4,
          plan: waitingRemoved,
        ).code,
        'customer_changed_mind',
      );
      expect(
        orderEditEffectiveReason(
          const OrderEditReasonDraft(),
          generation: 4,
          plan: cookingRemoved,
        ).code,
        isNull,
      );
    });

    test('the cashier\'s own chip wins — including clearing it', () {
      expect(
        orderEditEffectiveReason(
          const OrderEditReasonDraft(
            generation: 4,
            code: 'kitchen_issue',
            chosen: true,
          ),
          generation: 4,
          plan: waitingRemoved,
        ).code,
        'kitchen_issue',
      );
      expect(
        orderEditEffectiveReason(
          const OrderEditReasonDraft(generation: 4, chosen: true),
          generation: 4,
          plan: waitingRemoved,
        ).code,
        isNull,
      );
    });

    test('a draft of an earlier edit is ignored', () {
      final r = orderEditEffectiveReason(
        const OrderEditReasonDraft(
          generation: 2,
          code: 'other',
          text: 'old',
          chosen: true,
        ),
        generation: 4,
        plan: cookingRemoved,
      );
      expect(r.code, isNull);
      expect(r.text, '');
    });
  });

  group('decision D7: the presented bill', () {
    test('the bill job key is the order row\'s', () {
      expect(orderEditBillJobKey('order-1'), 'bill:srv:order-1');
    });

    test('only a bill this session handed to a printer counts', () {
      final at = DateTime.utc(2026, 10, 9, 12, 30);
      expect(
        orderEditBillPresentedAt(
          ReceiptPrintJob(status: PrintJobStatus.sentToPrinter, at: at),
        ),
        at,
      );
      for (final status in PrintJobStatus.values) {
        if (status == PrintJobStatus.sentToPrinter) continue;
        expect(
          orderEditBillPresentedAt(ReceiptPrintJob(status: status, at: at)),
          isNull,
          reason: status.name,
        );
      }
      expect(orderEditBillPresentedAt(null), isNull);
    });
  });
}
