import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show displayOrderCode;

import '../data/kiosk_fixtures.dart';
import '../data/kiosk_menu_data.dart';
import '../data/kiosk_order_submit.dart';
import '../design/kiosk_theme.dart';
import 'kiosk_live_runtime.dart';

/// KIOSK-001-REAL-SUBMIT-092 — where one Place-Order attempt currently
/// stands. [unconfirmed] means delivery is UNKNOWN (the server may have
/// committed): the frozen attempt is retained in memory and the customer may
/// retry the SAME identity; nothing is persisted (ONLINE-REQUIRED phase).
enum KioskSubmitPhase { idle, inFlight, unconfirmed }

/// KIOSK-001 Phase 1 — the kiosk-local flow state machine.
///
/// One state owner drives screens, sheets, the fixture cart, the idle engine
/// and the fixture device settings — mirroring the approved prototype's
/// single-component model. Everything is in-memory; "Place order" only mints
/// the next FIXTURE daily number and shows the confirmation. Time advances
/// exclusively through [KioskFlowController.tick] (one call ≈ one second), so
/// every timer behavior is deterministic in tests; production wiring calls it
/// from a 1s periodic timer.
enum KioskScreen { attract, service, tables, menu, confirm, settings }

enum KioskSheet { item, cart, pin }

enum KioskServiceType { dineIn, takeaway }

enum KioskAttractMode { photos, promo, video }

@immutable
class KioskCartLine {
  const KioskCartLine({
    required this.lineId,
    required this.itemId,
    required this.quantity,
    required this.selected,
    required this.note,
    required this.capturedUnitMinor,
  });
  final int lineId;
  final String itemId;
  final int quantity;

  /// group id → selected option ids (insertion order preserved).
  final Map<String, List<String>> selected;
  final String note;

  /// The unit price CAPTURED when the customer accepted this line — the cart
  /// always shows what was accepted. A later menu refresh that would price
  /// this line differently marks the cart STALE instead of silently changing
  /// the number (owner rule; the server enforces canonical prices at submit).
  final int capturedUnitMinor;

  KioskCartLine copyWith({int? quantity}) => KioskCartLine(
    lineId: lineId,
    itemId: itemId,
    quantity: quantity ?? this.quantity,
    selected: selected,
    note: note,
    capturedUnitMinor: capturedUnitMinor,
  );

  int get unitMinor => capturedUnitMinor;
  int get lineTotalMinor => capturedUnitMinor * quantity;
}

/// The item sheet's working draft (add or edit).
@immutable
class KioskItemDraft {
  const KioskItemDraft({
    required this.itemId,
    required this.quantity,
    required this.selected,
    required this.note,
    this.editingLineId,
    this.showRequiredError = false,
  });
  final String itemId;
  final int quantity;
  final Map<String, List<String>> selected;
  final String note;

  /// Non-null when the sheet re-opened an existing cart line ("Update item").
  final int? editingLineId;

  /// True after a blocked Add attempt — drives the shake + red badges.
  final bool showRequiredError;

  KioskItemDraft copyWith({
    int? quantity,
    Map<String, List<String>>? selected,
    String? note,
    bool? showRequiredError,
  }) => KioskItemDraft(
    itemId: itemId,
    quantity: quantity ?? this.quantity,
    selected: selected ?? this.selected,
    note: note ?? this.note,
    editingLineId: editingLineId,
    showRequiredError: showRequiredError ?? this.showRequiredError,
  );

  KioskFixtureItem itemIn(KioskMenuData menu) => menu.itemById(itemId);
  int unitMinorIn(KioskMenuData menu) =>
      menu.unitPriceMinor(itemIn(menu), selected);
  int totalMinorIn(KioskMenuData menu) => unitMinorIn(menu) * quantity;
  List<String> unmetRequiredIn(KioskMenuData menu) =>
      menu.unmetRequiredGroups(itemIn(menu), selected);
}

/// Fixture device settings (in-memory only in Phase 1 — deliberately no
/// persistence: real settings storage arrives with the device phase).
@immutable
class KioskDeviceSettings {
  const KioskDeviceSettings({
    this.tablePickerEnabled = true,
    this.idleSeconds = KioskTiming.idleDefaultSeconds,
    this.attractMode = KioskAttractMode.photos,
    this.boundPrinterId = 'p1',
    this.defaultLang = 'ar',
  });
  final bool tablePickerEnabled;
  final int idleSeconds;
  final KioskAttractMode attractMode;
  final String boundPrinterId;
  final String defaultLang;

  KioskDeviceSettings copyWith({
    bool? tablePickerEnabled,
    int? idleSeconds,
    KioskAttractMode? attractMode,
    String? boundPrinterId,
    String? defaultLang,
  }) => KioskDeviceSettings(
    tablePickerEnabled: tablePickerEnabled ?? this.tablePickerEnabled,
    idleSeconds: idleSeconds ?? this.idleSeconds,
    attractMode: attractMode ?? this.attractMode,
    boundPrinterId: boundPrinterId ?? this.boundPrinterId,
    defaultLang: defaultLang ?? this.defaultLang,
  );
}

/// Snapshot shown on the confirmation slip (frozen at place time).
@immutable
class KioskOrderSnapshot {
  const KioskOrderSnapshot({
    required this.number,
    required this.lines,
    required this.totalMinor,
    required this.service,
    required this.table,
    required this.customerName,
    this.code,
    this.subtotalMinor,
    this.taxMinor,
    this.taxInclusive = false,
  });
  final int number;
  final List<KioskCartLine> lines;
  final int totalMinor;
  final KioskServiceType service;
  final String? table;
  final String customerName;

  /// REAL mode: the shared cross-surface display code derived from the
  /// ACCEPTED order id ([displayOrderCode]) — the SAME label POS/KDS show.
  /// Null in demo mode (the fixture daily number renders instead).
  final String? code;

  /// REAL mode with tax enabled: the frozen subtotal/tax figures behind
  /// [totalMinor] (exclusive: total = subtotal + tax; inclusive: total =
  /// subtotal with [taxMinor] already inside it).
  final int? subtotalMinor;
  final int? taxMinor;
  final bool taxInclusive;
}

@immutable
class KioskState {
  const KioskState({
    this.lang = 'ar',
    this.screen = KioskScreen.attract,
    this.sheet,
    this.service,
    this.selectedTable,
    this.cart = const [],
    this.customerName = '',
    this.customerPhone = '',
    this.draft,
    this.pinEntry = '',
    this.pinError = false,
    this.categoryIndex = 0,
    this.settings = const KioskDeviceSettings(),
    this.dailySeq = 38,
    this.lastOrder,
    this.confirmSecondsLeft = KioskTiming.confirmReturnSeconds,
    this.idleSecondsLeft,
    this.secondsSinceActivity = 0,
    this.toast,
    this.toastTicksLeft = 0,
    this.busyFloor = true,
    this.cartStale = false,
    this.selectedTableId,
    this.branchTax,
    this.submitPhase = KioskSubmitPhase.idle,
    this.submitErrorKey,
  });

  final String lang; // 'en' | 'he' | 'ar'
  final KioskScreen screen;
  final KioskSheet? sheet;
  final KioskServiceType? service;

  /// The DISPLAY label of the selected table ("T1"). Copy only — never sent
  /// to the server (labels may repeat across zones).
  final String? selectedTable;

  /// KIOSK-001-REAL-SUBMIT-092: the AUTHORITATIVE table UUID behind
  /// [selectedTable] — the only value a real submit sends. Fixture tables
  /// carry deterministic ids so demo stays identical.
  final String? selectedTableId;

  /// The last successfully loaded branch tax policy (real mode; refreshed
  /// before every submit and on cart open). Null until read / in demo.
  final KioskBranchTax? branchTax;

  /// Where the current real Place-Order attempt stands (single-flight guard
  /// + the unconfirmed-delivery UX).
  final KioskSubmitPhase submitPhase;

  /// A stable recovery-message key for the cart sheet ('table-taken',
  /// 'phone-invalid', 'tax-unavailable', 'submit-failed'); localized at
  /// render time, never raw backend text.
  final String? submitErrorKey;
  final List<KioskCartLine> cart;
  final String customerName;
  final String customerPhone;
  final KioskItemDraft? draft;
  final String pinEntry;
  final bool pinError;
  final int categoryIndex;
  final KioskDeviceSettings settings;
  final int dailySeq;
  final KioskOrderSnapshot? lastOrder;
  final int confirmSecondsLeft;

  /// Non-null while the "Still there?" warning overlay counts down.
  final int? idleSecondsLeft;
  final int secondsSinceActivity;
  final String? toast;
  final int toastTicksLeft;

  /// Fixture switch matching the board's busy-floor preset.
  final bool busyFloor;

  /// True when a live menu refresh priced (or removed) something already in
  /// the cart — the customer must reconfirm before ordering can continue;
  /// prices are never changed silently.
  final bool cartStale;

  bool get rtl => lang != 'en';
  int get cartCount => cart.fold(0, (a, l) => a + l.quantity);
  int get cartTotalMinor => cart.fold(0, (a, l) => a + l.lineTotalMinor);

  KioskState copyWith({
    String? lang,
    KioskScreen? screen,
    Object? sheet = _sentinel,
    Object? service = _sentinel,
    Object? selectedTable = _sentinel,
    List<KioskCartLine>? cart,
    String? customerName,
    String? customerPhone,
    Object? draft = _sentinel,
    String? pinEntry,
    bool? pinError,
    int? categoryIndex,
    KioskDeviceSettings? settings,
    int? dailySeq,
    Object? lastOrder = _sentinel,
    int? confirmSecondsLeft,
    Object? idleSecondsLeft = _sentinel,
    int? secondsSinceActivity,
    Object? toast = _sentinel,
    int? toastTicksLeft,
    bool? busyFloor,
    bool? cartStale,
    Object? selectedTableId = _sentinel,
    Object? branchTax = _sentinel,
    KioskSubmitPhase? submitPhase,
    Object? submitErrorKey = _sentinel,
  }) => KioskState(
    lang: lang ?? this.lang,
    screen: screen ?? this.screen,
    sheet: identical(sheet, _sentinel) ? this.sheet : sheet as KioskSheet?,
    service: identical(service, _sentinel)
        ? this.service
        : service as KioskServiceType?,
    selectedTable: identical(selectedTable, _sentinel)
        ? this.selectedTable
        : selectedTable as String?,
    cart: cart ?? this.cart,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    draft: identical(draft, _sentinel) ? this.draft : draft as KioskItemDraft?,
    pinEntry: pinEntry ?? this.pinEntry,
    pinError: pinError ?? this.pinError,
    categoryIndex: categoryIndex ?? this.categoryIndex,
    settings: settings ?? this.settings,
    dailySeq: dailySeq ?? this.dailySeq,
    lastOrder: identical(lastOrder, _sentinel)
        ? this.lastOrder
        : lastOrder as KioskOrderSnapshot?,
    confirmSecondsLeft: confirmSecondsLeft ?? this.confirmSecondsLeft,
    idleSecondsLeft: identical(idleSecondsLeft, _sentinel)
        ? this.idleSecondsLeft
        : idleSecondsLeft as int?,
    secondsSinceActivity: secondsSinceActivity ?? this.secondsSinceActivity,
    toast: identical(toast, _sentinel) ? this.toast : toast as String?,
    toastTicksLeft: toastTicksLeft ?? this.toastTicksLeft,
    busyFloor: busyFloor ?? this.busyFloor,
    cartStale: cartStale ?? this.cartStale,
    selectedTableId: identical(selectedTableId, _sentinel)
        ? this.selectedTableId
        : selectedTableId as String?,
    branchTax: identical(branchTax, _sentinel)
        ? this.branchTax
        : branchTax as KioskBranchTax?,
    submitPhase: submitPhase ?? this.submitPhase,
    submitErrorKey: identical(submitErrorKey, _sentinel)
        ? this.submitErrorKey
        : submitErrorKey as String?,
  );

  static const _sentinel = Object();
}

final kioskFlowProvider = NotifierProvider<KioskFlowController, KioskState>(
  KioskFlowController.new,
);

class KioskFlowController extends Notifier<KioskState> {
  int _nextLineId = 1;
  int _staffTaps = 0;
  int _staffTapTicks = 0;
  int _pinErrorTicks = 0;

  @override
  KioskState build() =>
      KioskState(lang: const KioskDeviceSettings().defaultLang);

  /// The current menu snapshot (fixtures in demo mode, the live read in real
  /// mode). Read per action — a menu refresh mid-flow is picked up naturally.
  KioskMenuData get _menu => ref.read(kioskMenuDataProvider);

  // ---- activity / idle engine --------------------------------------------

  /// Any customer pointer contact (root Listener) — resets the idle counter.
  void touch() {
    if (state.secondsSinceActivity != 0 || state.idleSecondsLeft != null) {
      state = state.copyWith(secondsSinceActivity: 0, idleSecondsLeft: null);
    } else {
      state = state.copyWith(secondsSinceActivity: 0);
    }
  }

  /// Advances all clocks by one second. V2 rules: attract + settings are
  /// exempt from idle; the confirmation runs its own auto-return countdown;
  /// the last [KioskTiming.idleWarningSeconds] show the warning overlay.
  void tick() {
    // Staff triple-tap window decay (1.6s in the artifact ≈ 2 ticks).
    if (_staffTapTicks > 0 && --_staffTapTicks == 0) _staffTaps = 0;
    if (_pinErrorTicks > 0 && --_pinErrorTicks == 0 && state.pinError) {
      state = state.copyWith(pinError: false, pinEntry: '');
    }
    if (state.toastTicksLeft > 0) {
      final left = state.toastTicksLeft - 1;
      state = state.copyWith(
        toastTicksLeft: left,
        toast: left == 0 ? null : state.toast,
      );
    }
    if (state.screen == KioskScreen.confirm) {
      final left = state.confirmSecondsLeft - 1;
      if (left <= 0) {
        reset();
      } else {
        state = state.copyWith(confirmSecondsLeft: left);
      }
      return;
    }
    final exempt =
        state.screen == KioskScreen.attract ||
        state.screen == KioskScreen.settings;
    if (exempt) return;
    final elapsed = state.secondsSinceActivity + 1;
    final left = state.settings.idleSeconds - elapsed;
    if (left <= 0) {
      reset();
    } else if (left <= KioskTiming.idleWarningSeconds) {
      state = state.copyWith(
        secondsSinceActivity: elapsed,
        idleSecondsLeft: left,
      );
    } else {
      state = state.copyWith(
        secondsSinceActivity: elapsed,
        idleSecondsLeft: null,
      );
    }
  }

  /// Full session reset back to attract (idle timeout, Start over, exit
  /// settings, confirmation auto-return). Clears cart/customer/table/flow and
  /// returns the language to the device default — the next guest starts clean.
  void reset() {
    final settings = state.settings;
    final seq = state.dailySeq;
    final busy = state.busyFloor;
    // A reset abandons any unconfirmed submit handle (in-memory only by
    // design); the server-side outcome, if any, stands for staff surfaces.
    _pendingAttempt = null;
    state = KioskState(
      lang: settings.defaultLang,
      settings: settings,
      dailySeq: seq,
      busyFloor: busy,
    );
  }

  void dismissIdleWarning() =>
      state = state.copyWith(secondsSinceActivity: 0, idleSecondsLeft: null);

  // ---- language / navigation ---------------------------------------------

  void setLanguage(String lang) => state = state.copyWith(lang: lang);

  void startFromAttract() =>
      state = state.copyWith(screen: KioskScreen.service);

  void backToAttract() => reset();

  void pickService(KioskServiceType service) {
    if (service == KioskServiceType.takeaway) {
      state = state.copyWith(
        service: service,
        selectedTable: null,
        selectedTableId: null,
        screen: KioskScreen.menu,
      );
    } else {
      state = state.copyWith(
        service: service,
        screen: state.settings.tablePickerEnabled
            ? KioskScreen.tables
            : KioskScreen.menu,
      );
    }
  }

  void backFromTables() => state = state.copyWith(screen: KioskScreen.service);

  /// Selects/deselects a table. [id] is the AUTHORITATIVE identity (the real
  /// submit sends only this); [label] is display copy. A live table without
  /// an id can never be selected for a real order — the picker passes both.
  void toggleTable(String label, {String? id}) {
    final deselect =
        state.selectedTable == label && state.selectedTableId == id;
    state = state.copyWith(
      selectedTable: deselect ? null : label,
      selectedTableId: deselect ? null : id,
    );
  }

  void confirmTable() {
    if (state.selectedTable == null) return;
    state = state.copyWith(screen: KioskScreen.menu);
  }

  void backFromMenu() => state = state.copyWith(
    screen:
        state.settings.tablePickerEnabled &&
            state.service == KioskServiceType.dineIn
        ? KioskScreen.tables
        : KioskScreen.service,
  );

  /// "Change" — re-opens service type; the cart survives (V2 rule).
  void changeService() =>
      state = state.copyWith(screen: KioskScreen.service, sheet: null);

  void setCategoryIndex(int index) {
    final count = _menu.categories.length;
    final clamped = count == 0 ? 0 : index.clamp(0, count - 1);
    if (clamped != state.categoryIndex) {
      state = state.copyWith(categoryIndex: clamped);
    }
  }

  // ---- item sheet ---------------------------------------------------------

  void openItem(String itemId) {
    final menu = _menu;
    final item = menu.tryItem(itemId);
    // A sold-out/unreadable item stays visible but can never be configured
    // or added — the card is disabled; this guard is the belt behind it.
    if (item == null || !item.available) return;
    state = state.copyWith(
      sheet: KioskSheet.item,
      draft: KioskItemDraft(
        itemId: itemId,
        quantity: 1,
        // V2: the included option preselects only where the menu defines one
        // (fixtures); a LIVE menu defines no defaults and none is invented.
        selected: menu.defaultSelectionFor(item),
        note: '',
      ),
    );
  }

  void editCartLine(int lineId) {
    final line = state.cart.firstWhere((l) => l.lineId == lineId);
    state = state.copyWith(
      sheet: KioskSheet.item,
      draft: KioskItemDraft(
        itemId: line.itemId,
        quantity: line.quantity,
        selected: {
          for (final e in line.selected.entries) e.key: [...e.value],
        },
        note: line.note,
        editingLineId: line.lineId,
      ),
    );
  }

  void closeItemSheet() => state = state.copyWith(sheet: null, draft: null);

  void setDraftQuantity(int quantity) {
    final d = state.draft;
    if (d == null) return;
    state = state.copyWith(draft: d.copyWith(quantity: quantity.clamp(1, 99)));
  }

  void setDraftNote(String note) {
    final d = state.draft;
    if (d == null) return;
    state = state.copyWith(draft: d.copyWith(note: note));
  }

  /// V2 selection semantics: single-select groups swap (required groups keep
  /// one selection — tapping the selected option of a required group keeps
  /// it); multi groups toggle up to maxSelect.
  void toggleOption(String groupId, String optionId) {
    final d = state.draft;
    if (d == null) return;
    final group = _menu.group(groupId);
    if (group == null) return; // menu refreshed the group away mid-draft
    final selected = {
      for (final e in d.selected.entries) e.key: [...e.value],
    };
    final current = selected[groupId] ?? [];
    if (group.type == KioskGroupType.single) {
      if (current.length == 1 && current.single == optionId) {
        selected[groupId] = group.isRequired ? [optionId] : [];
      } else {
        selected[groupId] = [optionId];
      }
    } else {
      if (current.contains(optionId)) {
        selected[groupId] = current.where((o) => o != optionId).toList();
      } else {
        if (current.length >= (group.maxSelect ?? 99)) return;
        selected[groupId] = [...current, optionId];
      }
    }
    state = state.copyWith(
      draft: d.copyWith(selected: selected, showRequiredError: false),
    );
  }

  /// Add-to-order / Update-item. Blocked (with the shake flag) while a
  /// required group is unmet — the CTA names the missing groups. The unit
  /// price is CAPTURED here (what the customer accepted); later menu changes
  /// mark the cart stale instead of silently repricing.
  bool submitDraft() {
    final d = state.draft;
    if (d == null) return false;
    final menu = _menu;
    if (menu.tryItem(d.itemId) == null) {
      // The menu refreshed the item away mid-draft — nothing to add.
      state = state.copyWith(sheet: null, draft: null);
      return false;
    }
    if (d.unmetRequiredIn(menu).isNotEmpty) {
      state = state.copyWith(draft: d.copyWith(showRequiredError: true));
      return false;
    }
    final captured = d.unitMinorIn(menu);
    if (d.editingLineId != null) {
      state = state.copyWith(
        cart: [
          for (final l in state.cart)
            if (l.lineId == d.editingLineId)
              KioskCartLine(
                lineId: l.lineId,
                itemId: d.itemId,
                quantity: d.quantity,
                selected: d.selected,
                note: d.note,
                capturedUnitMinor: captured,
              )
            else
              l,
        ],
        sheet: KioskSheet.cart,
        draft: null,
      );
    } else {
      state = state.copyWith(
        cart: [
          ...state.cart,
          KioskCartLine(
            lineId: _nextLineId++,
            itemId: d.itemId,
            quantity: d.quantity,
            selected: d.selected,
            note: d.note,
            capturedUnitMinor: captured,
          ),
        ],
        sheet: null,
        draft: null,
      );
      _showToastTicks();
    }
    return true;
  }

  void _showToastTicks() {
    state = state.copyWith(toast: 'added', toastTicksLeft: 3);
  }

  // ---- cart ---------------------------------------------------------------

  void openCart() {
    state = state.copyWith(sheet: KioskSheet.cart);
    // 092: real mode shows the server-validated totals — refresh the branch
    // tax when the checkout opens (no-op in demo).
    unawaited(refreshBranchTax());
  }

  void closeCart() => state = state.copyWith(sheet: null);

  void incrementLine(int lineId) => _mutateLine(lineId, 1);
  void decrementLine(int lineId) => _mutateLine(lineId, -1);

  void _mutateLine(int lineId, int delta) {
    state = state.copyWith(
      cart: [
        for (final l in state.cart)
          if (l.lineId == lineId)
            l.copyWith(quantity: (l.quantity + delta).clamp(1, 99))
          else
            l,
      ],
    );
  }

  void removeLine(int lineId) => state = state.copyWith(
    cart: state.cart.where((l) => l.lineId != lineId).toList(),
  );

  void setCustomerName(String v) => state = state.copyWith(customerName: v);
  void setCustomerPhone(String v) => state = state.copyWith(customerPhone: v);

  /// "Place order". DEMO mode (no submitter wired) freezes the Phase-1
  /// FIXTURE snapshot and shows the confirmation — no backend work. REAL mode
  /// (KIOSK-001-REAL-SUBMIT-092) runs the ONLINE-REQUIRED submit flow against
  /// the hardened kiosk submit RPC via [_placeOrderReal].
  void placeOrder() {
    if (state.cart.isEmpty || state.service == null) return;
    if (!ref.read(kioskOrderingEnabledProvider)) {
      state = state.copyWith(toast: 'ordering-unavailable', toastTicksLeft: 3);
      return;
    }
    if (state.cartStale) {
      state = state.copyWith(toast: 'cart-stale', toastTicksLeft: 3);
      return;
    }
    if (ref.read(kioskOrderSubmitterProvider) != null) {
      _placeOrderReal();
      return;
    }
    final seq = state.dailySeq + 1;
    state = state.copyWith(
      dailySeq: seq,
      lastOrder: KioskOrderSnapshot(
        number: seq,
        lines: state.cart,
        totalMinor: state.cartTotalMinor,
        service: state.service!,
        table: state.selectedTable,
        customerName: state.customerName.trim(),
      ),
      cart: const [],
      sheet: null,
      screen: KioskScreen.confirm,
      confirmSecondsLeft: KioskTiming.confirmReturnSeconds,
    );
  }

  void newOrder() => reset();

  // ---- REAL submit (KIOSK-001-REAL-SUBMIT-092) ----------------------------

  /// The frozen in-flight/unconfirmed attempt. IN MEMORY ONLY (this phase is
  /// deliberately offline-free): closing the app during an uncertain submit
  /// loses the retry handle — the server outcome stands and staff surfaces
  /// show it. One customer Place-Order action mints exactly one identity.
  KioskSubmitAttempt? _pendingAttempt;

  @visibleForTesting
  KioskSubmitAttempt? get debugPendingAttempt => _pendingAttempt;

  Future<void> _placeOrderReal() async {
    if (state.submitPhase != KioskSubmitPhase.idle) return; // single-flight
    state = state.copyWith(
      submitPhase: KioskSubmitPhase.inFlight,
      submitErrorKey: null,
    );
    final live = ref.read(kioskLiveProvider.notifier);
    // 1-2. Fresh menu; loadMenu revalidates the cart against it.
    await live.loadMenu();
    if (ref.read(kioskLiveProvider).sessionInvalid) {
      _abortSubmit(null); // the pairing gate takes over
      return;
    }
    if (ref.read(kioskLiveProvider).menu == null) {
      _abortSubmit('submit-failed');
      return;
    }
    if (state.cartStale) {
      _abortSubmit('cart-stale-toast');
      return;
    }

    // 3. Table gate (authoritative UUID; fresh floor truth).
    String? tableId;
    if (state.service == KioskServiceType.dineIn &&
        state.settings.tablePickerEnabled) {
      if (live.tablesStale) await live.refreshTables();
      if (ref.read(kioskLiveProvider).sessionInvalid) {
        _abortSubmit(null);
        return;
      }
      final zones = ref.read(kioskLiveProvider).zones;
      final id = state.selectedTableId;
      final stillAvailable =
          id != null &&
          zones != null &&
          zones.any(
            (z) => z.tables.any(
              (t) => t.id == id && t.state == KioskTableState.available,
            ),
          );
      if (!stillAvailable) {
        _recoverTableTaken();
        return;
      }
      tableId = id;
    }

    // 10-11. Authoritative branch tax — a failed read BLOCKS (never guesses
    // OFF: a wrong guess is a guaranteed tax_mismatch or an under-display).
    final taxReader = ref.read(kioskBranchTaxReaderProvider);
    final tax = taxReader == null ? null : await taxReader.load();
    if (tax == null) {
      _abortSubmit('tax-unavailable');
      return;
    }
    state = state.copyWith(branchTax: tax);

    // Freeze ONE attempt (order id + D-022 identity + payload bytes).
    final KioskSubmitAttempt attempt;
    try {
      attempt = buildKioskSubmitAttempt(
        menu: ref.read(kioskMenuDataProvider),
        cart: state.cart,
        service: state.service!,
        tableId: tableId,
        tax: tax,
        customerName: state.customerName,
        customerPhone: state.customerPhone,
        clientCreatedAt: ref.read(kioskClockProvider)(),
      );
    } on KioskCartOutOfSyncError {
      state = state.copyWith(cartStale: true);
      _abortSubmit('cart-stale-toast');
      return;
    }
    _pendingAttempt = attempt;
    await _dispatchAttempt(attempt);
  }

  /// The customer's retry of an UNCONFIRMED delivery: the SAME frozen
  /// identity + payload go out again; D-022 replays the terminal result.
  Future<void> retrySubmit() async {
    final attempt = _pendingAttempt;
    if (attempt == null || state.submitPhase != KioskSubmitPhase.unconfirmed) {
      return;
    }
    state = state.copyWith(
      submitPhase: KioskSubmitPhase.inFlight,
      submitErrorKey: null,
    );
    await _dispatchAttempt(attempt);
  }

  Future<void> _dispatchAttempt(KioskSubmitAttempt attempt) async {
    final submitter = ref.read(kioskOrderSubmitterProvider);
    if (submitter == null) {
      _pendingAttempt = null;
      _abortSubmit('submit-failed');
      return;
    }
    final result = await submitter.submit(attempt);
    switch (result) {
      case KioskSubmitAccepted(:final orderId):
        _confirmAccepted(orderId, attempt);
      case KioskSubmitRejected(:final code, :final invalidField):
        // Terminal server refusal: this identity is spent — a later
        // deliberate re-order mints a NEW one.
        _pendingAttempt = null;
        _recoverRejected(code, invalidField);
      case KioskSubmitUnconfirmed():
        // Delivery unknown — keep the attempt, offer retry.
        state = state.copyWith(submitPhase: KioskSubmitPhase.unconfirmed);
      case KioskSubmitInvalidSession():
        _pendingAttempt = null;
        state = state.copyWith(submitPhase: KioskSubmitPhase.idle);
        ref.read(kioskLiveProvider.notifier).signalSessionInvalid();
    }
  }

  void _confirmAccepted(String orderId, KioskSubmitAttempt attempt) {
    _pendingAttempt = null;
    final grand = attempt.params['p_client_grand_total_minor'] as int;
    final subtotal = attempt.params['p_client_subtotal_minor'] as int;
    final taxMinor = attempt.params['p_client_tax_total_minor'] as int;
    final inclusive = state.branchTax?.isInclusive ?? false;
    state = state.copyWith(
      lastOrder: KioskOrderSnapshot(
        number: state.dailySeq,
        code: displayOrderCode(orderId),
        lines: state.cart,
        totalMinor: grand,
        subtotalMinor: subtotal,
        taxMinor: taxMinor,
        taxInclusive: inclusive,
        service: state.service!,
        table: state.selectedTable,
        customerName: state.customerName.trim(),
      ),
      cart: const [],
      customerName: '',
      customerPhone: '',
      selectedTable: null,
      selectedTableId: null,
      sheet: null,
      screen: KioskScreen.confirm,
      confirmSecondsLeft: KioskTiming.confirmReturnSeconds,
      submitPhase: KioskSubmitPhase.idle,
      submitErrorKey: null,
    );
  }

  void _recoverRejected(String code, String? invalidField) {
    switch (code) {
      case 'table_no_longer_available' || 'table_not_available':
        _recoverTableTaken();
      case 'item_unavailable' ||
          'menu_price_changed' ||
          'modifier_selection_invalid' ||
          'modifier_option_not_in_scope' ||
          'modifier_prep_snapshot_stale' ||
          'currency_mismatch' ||
          'tax_mismatch':
        // Menu/price/tax drift: reload truth, require visible reconfirmation.
        // Never silently reprice-and-resubmit.
        unawaited(ref.read(kioskLiveProvider.notifier).loadMenu());
        state = state.copyWith(
          cartStale: true,
          branchTax: null,
          submitPhase: KioskSubmitPhase.idle,
          submitErrorKey: null,
          toast: 'cart-stale',
          toastTicksLeft: 3,
        );
      case 'invalid_payload' when invalidField == 'customer_phone':
        state = state.copyWith(
          submitPhase: KioskSubmitPhase.idle,
          submitErrorKey: 'phone-invalid',
        );
      default:
        state = state.copyWith(
          submitPhase: KioskSubmitPhase.idle,
          submitErrorKey: 'submit-failed',
        );
    }
  }

  /// The selected table is gone (pre-flight or server race): honest recovery
  /// — cart/customer kept, invalid identity cleared, fresh floor, picker
  /// shown. Never a silent different table, never a success claim.
  void _recoverTableTaken() {
    unawaited(ref.read(kioskLiveProvider.notifier).refreshTables());
    state = state.copyWith(
      selectedTable: null,
      selectedTableId: null,
      submitPhase: KioskSubmitPhase.idle,
      submitErrorKey: null,
      sheet: null,
      screen: state.settings.tablePickerEnabled
          ? KioskScreen.tables
          : state.screen,
      toast: 'table-taken',
      toastTicksLeft: 3,
    );
  }

  void _abortSubmit(String? errorKey) {
    state = state.copyWith(
      submitPhase: KioskSubmitPhase.idle,
      submitErrorKey: (errorKey == null || errorKey == 'cart-stale-toast')
          ? null
          : errorKey,
      toast: errorKey == 'cart-stale-toast' ? 'cart-stale' : state.toast,
      toastTicksLeft: errorKey == 'cart-stale-toast' ? 3 : state.toastTicksLeft,
    );
  }

  /// Cart-sheet open in REAL mode also refreshes the branch tax so the
  /// summary shows the figures the server will validate.
  Future<void> refreshBranchTax() async {
    final reader = ref.read(kioskBranchTaxReaderProvider);
    if (reader == null) return;
    final tax = await reader.load();
    if (tax != null && tax != state.branchTax) {
      state = state.copyWith(branchTax: tax);
    }
  }

  // ---- live-menu cart integrity (Phase 3) ---------------------------------

  /// Re-checks every cart line against a FRESH menu snapshot. Any line whose
  /// item vanished, went unavailable, lost a selected option, or would price
  /// differently marks the whole cart STALE — shown to the customer, never
  /// silently repriced. Called by the live controller after each successful
  /// menu read.
  void revalidateCart(KioskMenuData menu) {
    if (state.cart.isEmpty) {
      if (state.cartStale) state = state.copyWith(cartStale: false);
      return;
    }
    final stale = state.cart.any((l) => _lineIsStale(l, menu));
    if (stale != state.cartStale) state = state.copyWith(cartStale: stale);
  }

  bool _lineIsStale(KioskCartLine line, KioskMenuData menu) {
    final item = menu.tryItem(line.itemId);
    if (item == null || !item.available) return true;
    for (final entry in line.selected.entries) {
      final group = menu.group(entry.key);
      if (entry.value.isEmpty) continue;
      if (group == null) return true;
      for (final oid in entry.value) {
        if (!group.options.any((o) => o.id == oid)) return true;
      }
    }
    return menu.unitPriceMinor(item, line.selected) != line.capturedUnitMinor;
  }

  /// The customer's reconfirm action on a stale cart: rebuilds the cart
  /// against the CURRENT menu — lines whose item is gone/unavailable are
  /// dropped, vanished option ids are dropped, and prices are re-captured at
  /// today's values (visibly — this runs only from the stale banner).
  void refreshCartAgainstMenu() {
    final menu = _menu;
    final rebuilt = <KioskCartLine>[];
    for (final line in state.cart) {
      final item = menu.tryItem(line.itemId);
      if (item == null || !item.available) continue;
      final selected = <String, List<String>>{};
      for (final gid in item.groupIds) {
        final group = menu.group(gid);
        if (group == null) continue;
        selected[gid] = [
          for (final oid in line.selected[gid] ?? const <String>[])
            if (group.options.any((o) => o.id == oid)) oid,
        ];
      }
      rebuilt.add(
        KioskCartLine(
          lineId: line.lineId,
          itemId: line.itemId,
          quantity: line.quantity,
          selected: selected,
          note: line.note,
          capturedUnitMinor: menu.unitPriceMinor(item, selected),
        ),
      );
    }
    state = state.copyWith(cart: rebuilt, cartStale: false);
  }

  // ---- staff path (VISUAL FIXTURE ONLY in Phase 1) ------------------------

  /// The discreet ••• target: three taps inside the decay window open the
  /// PIN gate (the artifact's 1.6s window ≈ 2 ticks). In REAL mode the whole
  /// unlock is DISABLED (KIOSK-001-REAL-SUBMIT-092 §18): the fixture PIN is a
  /// demo/design surface, never a production security boundary — REAL STAFF
  /// SETTINGS/PIN AUTH REMAINS A SEPARATE PHASE.
  void staffTap() {
    if (!ref.read(kioskStaffSettingsEnabledProvider)) return;
    _staffTaps += 1;
    _staffTapTicks = 2;
    if (_staffTaps >= 3) {
      _staffTaps = 0;
      state = state.copyWith(
        sheet: KioskSheet.pin,
        pinEntry: '',
        pinError: false,
      );
    }
  }

  void pinPress(String digit) {
    if (state.pinError) return;
    final entry = state.pinEntry + digit;
    if (entry.length < 4) {
      state = state.copyWith(pinEntry: entry);
      return;
    }
    // FIXTURE check only — not authentication (see kioskFixturePin).
    if (entry == kioskFixturePin) {
      state = state.copyWith(
        pinEntry: '',
        sheet: null,
        screen: KioskScreen.settings,
      );
    } else {
      state = state.copyWith(pinEntry: entry, pinError: true);
      _pinErrorTicks = 1;
    }
  }

  void pinBackspace() {
    if (state.pinEntry.isEmpty) return;
    state = state.copyWith(
      pinEntry: state.pinEntry.substring(0, state.pinEntry.length - 1),
    );
  }

  void pinCancel() =>
      state = state.copyWith(sheet: null, pinEntry: '', pinError: false);

  void exitSettings() => reset();

  // ---- fixture settings ---------------------------------------------------

  void updateSettings(KioskDeviceSettings settings) =>
      state = state.copyWith(settings: settings);

  void showStaffToast(String message) =>
      state = state.copyWith(toast: message, toastTicksLeft: 3);
}
