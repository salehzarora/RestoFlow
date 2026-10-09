import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// ORDER-EDIT-001C: the order-edit strings (POS, KDS, the shared kitchen chrome
/// and change slip, the non-audit reason labels and the Dashboard) resolve in
/// ar/he/en, are really translated, keep the kitchen free of money-change words
/// and add no audit (`activityLog*`) strings (ORDER_EDIT_DESIGN §9.2).
typedef _Resolve = String Function(AppLocalizations l, String s, int n);

/// Every key ORDER-EDIT-001C adds, resolved through the generated
/// [AppLocalizations]: `s` fills every String placeholder, `n` every int one.
/// The set must equal the en keys whose description starts 'ORDER-EDIT-001C'.
final Map<String, _Resolve> _orderEditKeys = <String, _Resolve>{
  'posOrderEditBlockedUnacknowledged': (l, s, n) =>
      l.posOrderEditBlockedUnacknowledged,
  'posOrderEditNeedsConnection': (l, s, n) => l.posOrderEditNeedsConnection,
  'posOrderEditCartNotEmptyBody': (l, s, n) => l.posOrderEditCartNotEmptyBody,
  'posOrderEditParkCurrentCart': (l, s, n) => l.posOrderEditParkCurrentCart,
  'posOrderEditBanner': (l, s, n) => l.posOrderEditBanner(s),
  'posOrderEditBannerWithTable': (l, s, n) =>
      l.posOrderEditBannerWithTable(s, s),
  'posOrderEditDiscard': (l, s, n) => l.posOrderEditDiscard,
  'posOrderEditDiscardConfirmTitle': (l, s, n) =>
      l.posOrderEditDiscardConfirmTitle,
  'posOrderEditDiscardConfirmBody': (l, s, n) =>
      l.posOrderEditDiscardConfirmBody,
  'posOrderEditStageWaiting': (l, s, n) => l.posOrderEditStageWaiting,
  'posOrderEditStageInKitchen': (l, s, n) => l.posOrderEditStageInKitchen,
  'posOrderEditStageReady': (l, s, n) => l.posOrderEditStageReady,
  'posOrderEditStageServed': (l, s, n) => l.posOrderEditStageServed,
  'posOrderEditStagePrinted': (l, s, n) => l.posOrderEditStagePrinted,
  'posOrderEditApplyToLabel': (l, s, n) => l.posOrderEditApplyToLabel,
  'posOrderEditApplyToAll': (l, s, n) => l.posOrderEditApplyToAll(n),
  'posOrderEditApplyToOne': (l, s, n) => l.posOrderEditApplyToOne,
  'posOrderEditNewBadge': (l, s, n) => l.posOrderEditNewBadge,
  'posOrderEditUndoRemove': (l, s, n) => l.posOrderEditUndoRemove,
  'posOrderEditKeepOrRemoveOnly': (l, s, n) => l.posOrderEditKeepOrRemoveOnly,
  'posOrderEditRemoveOnlyDiscount': (l, s, n) =>
      l.posOrderEditRemoveOnlyDiscount,
  'posOrderEditRemoveOnlyLegacy': (l, s, n) => l.posOrderEditRemoveOnlyLegacy,
  'posOrderEditRemovalNotAllowedHint': (l, s, n) =>
      l.posOrderEditRemovalNotAllowedHint,
  'posOrderEditManagerNeeded': (l, s, n) => l.posOrderEditManagerNeeded,
  'posOrderEditTotalsChange': (l, s, n) => l.posOrderEditTotalsChange(s, s, s),
  'posOrderEditDiscountKept': (l, s, n) => l.posOrderEditDiscountKept(s),
  'posOrderEditSendChanges': (l, s, n) => l.posOrderEditSendChanges,
  'posOrderEditNoChanges': (l, s, n) => l.posOrderEditNoChanges,
  'posOrderEditAllRemovedUseCancel': (l, s, n) =>
      l.posOrderEditAllRemovedUseCancel,
  'posOrderEditLowerDiscount': (l, s, n) => l.posOrderEditLowerDiscount,
  'posOrderEditDiscountExceedsNewSubtotal': (l, s, n) =>
      l.posOrderEditDiscountExceedsNewSubtotal,
  'posOrderEditReasonTitle': (l, s, n) => l.posOrderEditReasonTitle,
  'posOrderEditReasonOtherHint': (l, s, n) => l.posOrderEditReasonOtherHint,
  'posOrderEditReasonRequired': (l, s, n) => l.posOrderEditReasonRequired,
  'posOrderEditReasonOtherRequired': (l, s, n) =>
      l.posOrderEditReasonOtherRequired,
  'posOrderEditAlreadyCookedTitle': (l, s, n) =>
      l.posOrderEditAlreadyCookedTitle,
  'posOrderEditAlreadyCookedBody': (l, s, n) => l.posOrderEditAlreadyCookedBody,
  'posOrderEditSending': (l, s, n) => l.posOrderEditSending,
  'posOrderEditPendingBlocked': (l, s, n) => l.posOrderEditPendingBlocked,
  'posOrderEditRetry': (l, s, n) => l.posOrderEditRetry,
  'posOrderEditResultKitchenMustConfirm': (l, s, n) =>
      l.posOrderEditResultKitchenMustConfirm(n),
  'posOrderEditResultNewTicket': (l, s, n) => l.posOrderEditResultNewTicket(n),
  'posOrderEditResultPrinted': (l, s, n) => l.posOrderEditResultPrinted(n),
  'posOrderEditResultSaved': (l, s, n) => l.posOrderEditResultSaved(n),
  'posOrderEditResultRemake': (l, s, n) => l.posOrderEditResultRemake(n),
  'posOrderEditedChip': (l, s, n) => l.posOrderEditedChip,
  'posOrderEditKitchenPendingChip': (l, s, n) =>
      l.posOrderEditKitchenPendingChip,
  'posOrderEditKitchenConfirmedChip': (l, s, n) =>
      l.posOrderEditKitchenConfirmedChip,
  'posOrderEditBillChanged': (l, s, n) => l.posOrderEditBillChanged,
  'posOrderEditRebased': (l, s, n) => l.posOrderEditRebased,
  'posOrderEditRebaseDropped': (l, s, n) => l.posOrderEditRebaseDropped(s),
  'posOrderEditErrorNotAllowed': (l, s, n) => l.posOrderEditErrorNotAllowed,
  'posOrderEditErrorInvalid': (l, s, n) => l.posOrderEditErrorInvalid,
  'posOrderEditErrorTooManyChanges': (l, s, n) =>
      l.posOrderEditErrorTooManyChanges,
  'posOrderEditErrorFeatureDisabled': (l, s, n) =>
      l.posOrderEditErrorFeatureDisabled,
  'posOrderEditErrorNotEditable': (l, s, n) => l.posOrderEditErrorNotEditable,
  'posOrderEditErrorAlreadyPaid': (l, s, n) => l.posOrderEditErrorAlreadyPaid,
  'posOrderEditErrorKitchenModeChanged': (l, s, n) =>
      l.posOrderEditErrorKitchenModeChanged,
  'posOrderEditErrorLineHasDiscount': (l, s, n) =>
      l.posOrderEditErrorLineHasDiscount,
  'posOrderEditErrorLegacyLine': (l, s, n) => l.posOrderEditErrorLegacyLine,
  'posOrderEditErrorRemovalNotPermitted': (l, s, n) =>
      l.posOrderEditErrorRemovalNotPermitted,
  'posOrderEditErrorFinishedFoodNeedsManager': (l, s, n) =>
      l.posOrderEditErrorFinishedFoodNeedsManager,
  'posOrderEditErrorItemUnavailable': (l, s, n) =>
      l.posOrderEditErrorItemUnavailable(s),
  'posOrderEditErrorOptionNotInScope': (l, s, n) =>
      l.posOrderEditErrorOptionNotInScope,
  'posOrderEditErrorTaxModeUnsupported': (l, s, n) =>
      l.posOrderEditErrorTaxModeUnsupported,
  'posOrderEditErrorSlipTooLarge': (l, s, n) => l.posOrderEditErrorSlipTooLarge,
  'posOrderEditSlipNotPrinted': (l, s, n) => l.posOrderEditSlipNotPrinted,
  'posOrderEditPrintAgain': (l, s, n) => l.posOrderEditPrintAgain,
  'posOrderEditNewerSlipOffer': (l, s, n) => l.posOrderEditNewerSlipOffer,
  'posOrderEditPrintLatest': (l, s, n) => l.posOrderEditPrintLatest,
  'posOrdersStatusInKitchen': (l, s, n) => l.posOrdersStatusInKitchen,
  'kdsEditChangedLabel': (l, s, n) => l.kdsEditChangedLabel,
  'kdsEditNewBadge': (l, s, n) => l.kdsEditNewBadge,
  'kdsEditWas': (l, s, n) => l.kdsEditWas(s),
  'kdsEditQuantityIncrease': (l, s, n) => l.kdsEditQuantityIncrease(n),
  'kdsEditRemake': (l, s, n) => l.kdsEditRemake,
  'kdsEditInsteadOf': (l, s, n) => l.kdsEditInsteadOf(s),
  'kdsEditAllItemsRemovedTitle': (l, s, n) => l.kdsEditAllItemsRemovedTitle,
  'kdsEditAllItemsRemovedBody': (l, s, n) => l.kdsEditAllItemsRemovedBody,
  'kdsEditGotIt': (l, s, n) => l.kdsEditGotIt,
  'kdsEditAlsoConfirms': (l, s, n) => l.kdsEditAlsoConfirms(s),
  'kdsEditRemadeInRound': (l, s, n) => l.kdsEditRemadeInRound(n),
  'kitchenEditChangeNumber': (l, s, n) => l.kitchenEditChangeNumber(n),
  'kitchenEditRemovedLabel': (l, s, n) => l.kitchenEditRemovedLabel,
  'kitchenChangeSlipTitle': (l, s, n) => l.kitchenChangeSlipTitle,
  'kitchenChangeSlipChangeLabel': (l, s, n) => l.kitchenChangeSlipChangeLabel,
  'kitchenChangeSlipAddLabel': (l, s, n) => l.kitchenChangeSlipAddLabel,
  'kitchenChangeSlipWasLabel': (l, s, n) => l.kitchenChangeSlipWasLabel,
  'kitchenChangeSlipNowLabel': (l, s, n) => l.kitchenChangeSlipNowLabel,
  'kitchenChangeSlipOrderNow': (l, s, n) => l.kitchenChangeSlipOrderNow,
  'kitchenChangeSlipFooter': (l, s, n) => l.kitchenChangeSlipFooter(s),
  'kitchenChangeSlipStaffLabel': (l, s, n) => l.kitchenChangeSlipStaffLabel,
  'kitchenChangeSlipReasonLabel': (l, s, n) => l.kitchenChangeSlipReasonLabel,
  'orderEditReasonCustomerChangedMind': (l, s, n) =>
      l.orderEditReasonCustomerChangedMind,
  'orderEditReasonEntryMistake': (l, s, n) => l.orderEditReasonEntryMistake,
  'orderEditReasonItemUnavailable': (l, s, n) =>
      l.orderEditReasonItemUnavailable,
  'orderEditReasonKitchenIssue': (l, s, n) => l.orderEditReasonKitchenIssue,
  'orderEditReasonOther': (l, s, n) => l.orderEditReasonOther,
  'ordersStatusInKitchen': (l, s, n) => l.ordersStatusInKitchen,
  'ordersEditedBadge': (l, s, n) => l.ordersEditedBadge(n),
  'ordersEditTimelineTitle': (l, s, n) => l.ordersEditTimelineTitle,
  'ordersEditKitchenConfirmedAt': (l, s, n) =>
      l.ordersEditKitchenConfirmedAt(s),
  'ordersEditKitchenPending': (l, s, n) => l.ordersEditKitchenPending,
  'ordersEditKitchenPrinted': (l, s, n) => l.ordersEditKitchenPrinted,
  'dashboardOrderEditsTitle': (l, s, n) => l.dashboardOrderEditsTitle,
  'dashboardOrderEditsSubtitle': (l, s, n) => l.dashboardOrderEditsSubtitle,
  'dashboardOrderEditsEditCount': (l, s, n) => l.dashboardOrderEditsEditCount,
  'dashboardOrderEditsEditedOrders': (l, s, n) =>
      l.dashboardOrderEditsEditedOrders,
  'dashboardOrderEditsRemoved': (l, s, n) => l.dashboardOrderEditsRemoved,
  'dashboardOrderEditsReplacedOut': (l, s, n) =>
      l.dashboardOrderEditsReplacedOut,
  'dashboardOrderEditsReplacedIn': (l, s, n) => l.dashboardOrderEditsReplacedIn,
  'dashboardOrderEditsAdded': (l, s, n) => l.dashboardOrderEditsAdded,
  'dashboardOrderEditsNetChange': (l, s, n) => l.dashboardOrderEditsNetChange,
  'dashboardOrderEditsGrossRemoved': (l, s, n) =>
      l.dashboardOrderEditsGrossRemoved,
  'dashboardOrderEditsByReason': (l, s, n) => l.dashboardOrderEditsByReason,
  'dashboardOrderEditsByStaff': (l, s, n) => l.dashboardOrderEditsByStaff,
  'dashboardOrderEditsEmpty': (l, s, n) => l.dashboardOrderEditsEmpty,
  'dashboardOrderEditSectionTitle': (l, s, n) =>
      l.dashboardOrderEditSectionTitle,
  'dashboardOrderEditEnabledLabel': (l, s, n) =>
      l.dashboardOrderEditEnabledLabel,
  'dashboardOrderEditEnabledHelp': (l, s, n) => l.dashboardOrderEditEnabledHelp,
  'dashboardOrderEditFinishedFoodLabel': (l, s, n) =>
      l.dashboardOrderEditFinishedFoodLabel,
  'dashboardOrderEditFinishedFoodHelp': (l, s, n) =>
      l.dashboardOrderEditFinishedFoodHelp,
  'dashboardOrderEditFinishedFoodPrinterOnlyNote': (l, s, n) =>
      l.dashboardOrderEditFinishedFoodPrinterOnlyNote,
  'dashboardOrderEditSaved': (l, s, n) => l.dashboardOrderEditSaved,
  'dashboardOrderEditSaveFailed': (l, s, n) => l.dashboardOrderEditSaveFailed,
  'staffCapVoidOrderAndEdits': (l, s, n) => l.staffCapVoidOrderAndEdits,
  'staffCapVoidOrderAndEditsHint': (l, s, n) => l.staffCapVoidOrderAndEditsHint,
};

/// Values that are only symbols plus a placeholder, so ar/he equal en.
const Set<String> _symbolOnlyKeys = <String>{'kdsEditQuantityIncrease'};

/// The `activityLog*` key count after ORDER-EDIT-001A. ORDER-EDIT-001C adds no
/// audit strings; a later ticket that adds `activityLog*` keys updates this.
const int _activityLogKeyCountSnapshot = 200;

String _arbDir() {
  for (final candidate in <String>['lib/l10n', 'packages/l10n/lib/l10n']) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  fail('Could not locate the ARB directory from CWD ${Directory.current.path}');
}

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('${_arbDir()}/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The en template's `@key` metadata of every key described as 001C.
Map<String, Map<String, dynamic>> _orderEditMetadata() {
  final en = _arb('en');
  return <String, Map<String, dynamic>>{
    for (final e in en.entries)
      if (e.key.startsWith('@') &&
          e.value is Map<String, dynamic> &&
          ((e.value as Map<String, dynamic>)['description'] as String? ?? '')
              .startsWith('ORDER-EDIT-001C '))
        e.key.substring(1): e.value as Map<String, dynamic>,
  };
}

Future<AppLocalizations> _load(String locale) =>
    AppLocalizations.delegate.load(Locale(locale));

Map<String, String> _resolveAll(AppLocalizations l, String s, int n) =>
    <String, String>{
      for (final e in _orderEditKeys.entries) e.key: e.value(l, s, n),
    };

void main() {
  test('the typed key list is exactly the 001C block of the en template', () {
    final metadata = _orderEditMetadata();
    expect(metadata.keys.toSet(), _orderEditKeys.keys.toSet());
    expect(_orderEditKeys, hasLength(127));
    final surface = RegExp(
      r'^ORDER-EDIT-001C (POS|KDS|Kitchen chrome|Change slip|Reason|Dashboard): ',
    );
    for (final e in metadata.entries) {
      expect(
        surface.hasMatch(e.value['description'] as String),
        isTrue,
        reason: e.key,
      );
    }
    // ar/he carry every key with a value (they have no metadata).
    for (final locale in <String>['ar', 'he']) {
      final arb = _arb(locale);
      for (final key in _orderEditKeys.keys) {
        expect(arb[key], isA<String>(), reason: '$locale $key');
        expect((arb[key] as String).trim(), isNotEmpty, reason: '$locale $key');
      }
    }
  });

  test('every key resolves non-empty in en, ar and he', () async {
    for (final locale in <String>['en', 'ar', 'he']) {
      final resolved = _resolveAll(await _load(locale), '7', 7);
      for (final e in resolved.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '$locale ${e.key}');
      }
    }
  });

  test(
    'ar and he are translated: no Latin letters, never the en text',
    () async {
      final en = _resolveAll(await _load('en'), '7', 7);
      final latin = RegExp('[A-Za-z]');
      for (final locale in <String>['ar', 'he']) {
        final resolved = _resolveAll(await _load(locale), '7', 7);
        for (final e in resolved.entries) {
          expect(latin.hasMatch(e.value), isFalse, reason: '$locale ${e.key}');
          if (_symbolOnlyKeys.contains(e.key)) continue;
          expect(e.value, isNot(en[e.key]), reason: '$locale ${e.key}');
        }
      }
    },
  );

  test('every declared placeholder reaches the output', () async {
    final metadata = _orderEditMetadata();
    for (final locale in <String>['en', 'ar', 'he']) {
      final resolved = _resolveAll(await _load(locale), '«Q»', 97531);
      for (final e in metadata.entries) {
        final placeholders =
            (e.value['placeholders'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
        final types = placeholders.values
            .map((p) => (p as Map<String, dynamic>)['type'])
            .toSet();
        if (types.contains('String')) {
          expect(resolved[e.key], contains('«Q»'), reason: '$locale ${e.key}');
        }
        if (types.contains('int')) {
          expect(
            resolved[e.key],
            contains('97531'),
            reason: '$locale ${e.key}',
          );
        }
      }
    }
  });

  test('no 001C string uses the money-change words (الباقي / עודף)', () async {
    for (final locale in <String>['ar', 'he']) {
      final l = await _load(locale);
      final resolved = _resolveAll(l, '7', 7);
      for (final e in resolved.entries) {
        expect(e.value, isNot(contains('الباقي')), reason: '$locale ${e.key}');
        expect(e.value, isNot(contains('עודף')), reason: '$locale ${e.key}');
      }
      // The edit "change" words are never the receipt's money "change".
      for (final s in <String>[
        l.kitchenEditChangeNumber(2),
        l.kitchenChangeSlipChangeLabel,
        l.kitchenChangeSlipTitle,
        l.ordersEditTimelineTitle,
      ]) {
        expect(s, isNot(contains(l.posReceiptChange)), reason: s);
        expect(s, isNot(contains(l.ordersChangeLabel)), reason: s);
      }
    }
  });

  test('the totals footer arrow follows the reading direction', () async {
    final en = await _load('en');
    expect(
      en.posOrderEditTotalsChange('₪85.00', '₪78.00', '−₪7.00'),
      'Was ₪85.00 → Now ₪78.00 (−₪7.00)',
    );
    for (final locale in <String>['ar', 'he']) {
      final s = (await _load(locale)).posOrderEditTotalsChange('1', '2', '3');
      expect(s, contains('←'), reason: locale);
      expect(s, isNot(contains('→')), reason: locale);
    }
  });

  test('the remake toast pluralizes at 1, 2, 3 and 11', () async {
    final en = await _load('en');
    expect(
      en.posOrderEditResultRemake(1),
      'Already cooked: 1 dish will be remade',
    );
    expect(
      en.posOrderEditResultRemake(2),
      'Already cooked: 2 dishes will be remade',
    );
    expect(
      en.posOrderEditResultRemake(3),
      'Already cooked: 3 dishes will be remade',
    );
    expect(
      en.posOrderEditResultRemake(11),
      'Already cooked: 11 dishes will be remade',
    );

    final ar = await _load('ar');
    const arPrefix = 'تم تحضيره مسبقًا: سيُعاد تحضير ';
    expect(ar.posOrderEditResultRemake(1), '${arPrefix}طبق واحد');
    expect(ar.posOrderEditResultRemake(2), '${arPrefix}طبقين');
    expect(ar.posOrderEditResultRemake(3), '${arPrefix}3 أطباق');
    expect(ar.posOrderEditResultRemake(11), '${arPrefix}11 طبقًا');
    expect(ar.posOrderEditResultRemake(100), '${arPrefix}100 طبق');

    final he = await _load('he');
    expect(he.posOrderEditResultRemake(1), 'כבר הוכן: מנה אחת תוכן מחדש');
    expect(he.posOrderEditResultRemake(2), 'כבר הוכן: שתי מנות יוכנו מחדש');
    expect(he.posOrderEditResultRemake(3), 'כבר הוכן: 3 מנות יוכנו מחדש');
    expect(he.posOrderEditResultRemake(11), 'כבר הוכן: 11 מנות יוכנו מחדש');
  });

  test('the printer-only note is the exact design text', () async {
    final en = await _load('en');
    expect(
      en.dashboardOrderEditFinishedFoodPrinterOnlyNote,
      'No effect without a kitchen screen: the system cannot tell when food '
      'is ready',
    );
  });

  test('the change slip and kitchen chrome labels (en)', () async {
    final en = await _load('en');
    expect(en.kitchenEditChangeNumber(1), 'Change 1');
    expect(en.kitchenEditRemovedLabel, 'REMOVED');
    expect(en.kitchenChangeSlipTitle, 'ORDER CHANGED');
    expect(en.kitchenChangeSlipChangeLabel, 'CHANGE');
    expect(en.kitchenChangeSlipAddLabel, 'ADD');
    expect(en.kitchenChangeSlipWasLabel, 'Was');
    expect(en.kitchenChangeSlipNowLabel, 'Now');
    expect(en.kitchenChangeSlipOrderNow, 'ORDER NOW');
    expect(
      en.kitchenChangeSlipFooter('#A1B2C3'),
      'Replaces earlier tickets for #A1B2C3',
    );
    expect(en.kitchenChangeSlipStaffLabel, 'Staff');
    expect(en.kitchenChangeSlipReasonLabel, 'Reason');
    expect(en.kdsEditAlsoConfirms('1, 2'), 'Also confirms change 1, 2');
    expect(en.kdsEditRemadeInRound(3), 'Remade in Round 3');
  });

  group('orderEditReasonLabel', () {
    test('the codes are the server CHECK list, in order', () {
      const expected = <String>[
        'customer_changed_mind',
        'entry_mistake',
        'item_unavailable',
        'kitchen_issue',
        'other',
      ];
      expect(kOrderEditReasonCodes, expected);

      // Cross-check against the 001A schema migration's CHECK constraint.
      const name = '20261008170000_order_edit_001a_schema.sql';
      final file = <String>[
        '../../supabase/migrations/$name',
        'supabase/migrations/$name',
      ].map(File.new).where((f) => f.existsSync()).firstOrNull;
      if (file == null) fail('Could not locate $name');
      final check = RegExp(
        r'reason_code in \(([^)]*)\)',
      ).firstMatch(file.readAsStringSync());
      expect(check, isNotNull);
      final serverCodes = check!
          .group(1)!
          .split(',')
          .map((c) => c.trim().replaceAll("'", ''))
          .toList();
      expect(kOrderEditReasonCodes, serverCodes);
    });

    test('every code maps to its own non-audit label in each locale', () async {
      for (final locale in <String>['en', 'ar', 'he']) {
        final l = await _load(locale);
        final labels = <String, String?>{
          for (final c in kOrderEditReasonCodes) c: orderEditReasonLabel(l, c),
        };
        expect(labels.values, everyElement(isNotNull), reason: locale);
        expect(labels.values.toSet(), hasLength(5), reason: locale);
        expect(labels, <String, String>{
          'customer_changed_mind': l.orderEditReasonCustomerChangedMind,
          'entry_mistake': l.orderEditReasonEntryMistake,
          'item_unavailable': l.orderEditReasonItemUnavailable,
          'kitchen_issue': l.orderEditReasonKitchenIssue,
          'other': l.orderEditReasonOther,
        });
      }
    });

    test('an unknown or absent code has no label', () async {
      final l = await _load('en');
      for (final code in <String?>[
        null,
        '',
        'CUSTOMER_CHANGED_MIND',
        'voided',
        ' other',
      ]) {
        expect(orderEditReasonLabel(l, code), isNull, reason: '$code');
      }
    });
  });

  test('ORDER-EDIT-001C adds no audit (activityLog*) strings', () {
    expect(
      _orderEditKeys.keys.where((k) => k.startsWith('activityLog')),
      isEmpty,
    );
    final en = _arb('en');
    final activityLogKeys = en.keys
        .where((k) => k.startsWith('activityLog'))
        .toList();
    expect(
      activityLogKeys,
      hasLength(_activityLogKeyCountSnapshot),
      reason:
          'ORDER-EDIT-001C must not add activityLog* keys; a later audit '
          'ticket updates _activityLogKeyCountSnapshot.',
    );
    for (final key in activityLogKeys) {
      final meta = en['@$key'];
      final description = meta is Map<String, dynamic>
          ? meta['description'] as String? ?? ''
          : '';
      expect(description, isNot(contains('ORDER-EDIT-001C')), reason: key);
    }
  });
}
