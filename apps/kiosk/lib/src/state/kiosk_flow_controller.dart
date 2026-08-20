import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kiosk_fixtures.dart';
import '../design/kiosk_theme.dart';

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
  });
  final int lineId;
  final String itemId;
  final int quantity;

  /// group id → selected option ids (insertion order preserved).
  final Map<String, List<String>> selected;
  final String note;

  KioskCartLine copyWith({int? quantity}) => KioskCartLine(
    lineId: lineId,
    itemId: itemId,
    quantity: quantity ?? this.quantity,
    selected: selected,
    note: note,
  );

  int get unitMinor => kioskUnitPriceMinor(kioskItemById(itemId), selected);
  int get lineTotalMinor => unitMinor * quantity;
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

  KioskFixtureItem get item => kioskItemById(itemId);
  int get unitMinor => kioskUnitPriceMinor(item, selected);
  int get totalMinor => unitMinor * quantity;
  List<String> get unmetRequired => kioskUnmetRequiredGroups(item, selected);
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
  });
  final int number;
  final List<KioskCartLine> lines;
  final int totalMinor;
  final KioskServiceType service;
  final String? table;
  final String customerName;
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
  });

  final String lang; // 'en' | 'he' | 'ar'
  final KioskScreen screen;
  final KioskSheet? sheet;
  final KioskServiceType? service;
  final String? selectedTable;
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

  void toggleTable(String label) => state = state.copyWith(
    selectedTable: state.selectedTable == label ? null : label,
  );

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
    final clamped = index.clamp(0, kioskFixtureMenu.length - 1);
    if (clamped != state.categoryIndex) {
      state = state.copyWith(categoryIndex: clamped);
    }
  }

  // ---- item sheet ---------------------------------------------------------

  void openItem(String itemId) {
    final item = kioskItemById(itemId);
    final selected = <String, List<String>>{
      for (final g in item.groupIds) g: [],
    };
    // V2: the included option preselects only where the menu defines one.
    if (item.groupIds.contains('weight')) {
      selected['weight'] = [kioskIncludedWeightOptionId];
    }
    state = state.copyWith(
      sheet: KioskSheet.item,
      draft: KioskItemDraft(
        itemId: itemId,
        quantity: 1,
        selected: selected,
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
    final group = kioskFixtureGroups[groupId]!;
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
  /// required group is unmet — the CTA names the missing groups.
  bool submitDraft() {
    final d = state.draft;
    if (d == null) return false;
    if (d.unmetRequired.isNotEmpty) {
      state = state.copyWith(draft: d.copyWith(showRequiredError: true));
      return false;
    }
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

  void openCart() => state = state.copyWith(sheet: KioskSheet.cart);
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

  /// Phase 1: "Place order" freezes a fixture snapshot and shows the
  /// confirmation. It performs NO backend work of any kind — the real
  /// submit path arrives in a later phase.
  void placeOrder() {
    if (state.cart.isEmpty || state.service == null) return;
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

  // ---- staff path (VISUAL FIXTURE ONLY in Phase 1) ------------------------

  /// The discreet ••• target: three taps inside the decay window open the
  /// PIN gate (the artifact's 1.6s window ≈ 2 ticks).
  void staffTap() {
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
