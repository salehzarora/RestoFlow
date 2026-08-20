import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';

/// KIOSK-001 Phase 1 — the flow/idle state machine. Time is deterministic:
/// one controller.tick() == one second; no wall clock is involved.
void main() {
  late ProviderContainer container;
  late KioskFlowController controller;

  KioskState state() => container.read(kioskFlowProvider);

  setUp(() {
    container = ProviderContainer();
    controller = container.read(kioskFlowProvider.notifier);
    addTearDown(container.dispose);
  });

  group('service routing', () {
    test('takeaway skips tables entirely', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      expect(state().screen, KioskScreen.menu);
      expect(state().selectedTable, isNull);
    });

    test('dine-in goes to tables while the device toggle is ON', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      expect(state().screen, KioskScreen.tables);
    });

    test('dine-in with the toggle OFF goes straight to menu, no table', () {
      controller.updateSettings(
        state().settings.copyWith(tablePickerEnabled: false),
      );
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      expect(state().screen, KioskScreen.menu);
      expect(state().selectedTable, isNull);
    });

    test('continue requires a selected table', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      controller.confirmTable();
      expect(state().screen, KioskScreen.tables);
      controller.toggleTable('T4');
      controller.confirmTable();
      expect(state().screen, KioskScreen.menu);
      expect(state().selectedTable, 'T4');
    });

    test('change from the cart re-opens service type with the cart intact', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      controller.openItem('d1');
      controller.submitDraft();
      controller.changeService();
      expect(state().screen, KioskScreen.service);
      expect(state().cart, hasLength(1));
    });
  });

  group('idle engine', () {
    void enterMenu() {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
    }

    test('attract never times out', () {
      for (var i = 0; i < 200; i++) {
        controller.tick();
      }
      expect(state().screen, KioskScreen.attract);
      expect(state().idleSecondsLeft, isNull);
    });

    test('warning appears for the final 10 seconds and then resets', () {
      enterMenu();
      for (var i = 0; i < 49; i++) {
        controller.tick();
      }
      expect(state().idleSecondsLeft, isNull);
      controller.tick(); // second 50 → 10 left
      expect(state().idleSecondsLeft, 10);
      for (var i = 0; i < 9; i++) {
        controller.tick();
      }
      expect(state().idleSecondsLeft, 1);
      controller.tick(); // 60th second → full reset
      expect(state().screen, KioskScreen.attract);
      expect(state().idleSecondsLeft, isNull);
    });

    test('touch resets the countdown and hides the warning', () {
      enterMenu();
      for (var i = 0; i < 55; i++) {
        controller.tick();
      }
      expect(state().idleSecondsLeft, isNotNull);
      controller.touch();
      expect(state().idleSecondsLeft, isNull);
      for (var i = 0; i < 49; i++) {
        controller.tick();
      }
      expect(state().idleSecondsLeft, isNull);
      expect(state().screen, KioskScreen.menu);
    });

    test('the reset clears cart, table, customer fields and language', () {
      controller.setLanguage('en');
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      controller.toggleTable('T4');
      controller.confirmTable();
      controller.openItem('b1');
      controller.submitDraft();
      controller.setCustomerName('Sami');
      controller.setCustomerPhone('050');
      for (var i = 0; i < 60; i++) {
        controller.tick();
      }
      final s = state();
      expect(s.screen, KioskScreen.attract);
      expect(s.cart, isEmpty);
      expect(s.selectedTable, isNull);
      expect(s.customerName, isEmpty);
      expect(s.customerPhone, isEmpty);
      // Language returns to the device default (fixture default: ar).
      expect(s.lang, s.settings.defaultLang);
    });

    test('a shorter configured timeout is honored', () {
      controller.updateSettings(state().settings.copyWith(idleSeconds: 30));
      enterMenu();
      for (var i = 0; i < 30; i++) {
        controller.tick();
      }
      expect(state().screen, KioskScreen.attract);
    });

    test('settings screen is exempt from idle', () {
      controller.staffTap();
      controller.staffTap();
      controller.staffTap();
      for (final d in ['2', '4', '6', '8']) {
        controller.pinPress(d);
      }
      expect(state().screen, KioskScreen.settings);
      for (var i = 0; i < 200; i++) {
        controller.tick();
      }
      expect(state().screen, KioskScreen.settings);
    });
  });

  group('confirmation', () {
    void placeTakeawayOrder() {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      controller.openItem('d1');
      controller.submitDraft();
      controller.placeOrder();
    }

    test('placing an order mints the next fixture daily number', () {
      final before = state().dailySeq;
      placeTakeawayOrder();
      final s = state();
      expect(s.screen, KioskScreen.confirm);
      expect(s.lastOrder!.number, before + 1);
      expect(s.cart, isEmpty);
    });

    test('auto-returns to attract after 24 deterministic seconds', () {
      placeTakeawayOrder();
      for (var i = 0; i < 23; i++) {
        controller.tick();
      }
      expect(state().screen, KioskScreen.confirm);
      controller.tick();
      expect(state().screen, KioskScreen.attract);
    });

    test('the snapshot freezes table + name', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.dineIn);
      controller.toggleTable('T6');
      controller.confirmTable();
      controller.openItem('b1');
      controller.submitDraft();
      controller.setCustomerName('  Dana ');
      controller.placeOrder();
      final order = state().lastOrder!;
      expect(order.table, 'T6');
      expect(order.customerName, 'Dana');
      expect(order.totalMinor, 4000);
    });
  });

  group('staff path (fixture only)', () {
    test('triple-tap inside the window opens the PIN gate', () {
      controller.staffTap();
      controller.staffTap();
      expect(state().sheet, isNull);
      controller.staffTap();
      expect(state().sheet, KioskSheet.pin);
    });

    test('slow taps decay and never open the gate', () {
      controller.staffTap();
      controller.tick();
      controller.tick();
      controller.staffTap();
      controller.tick();
      controller.tick();
      controller.staffTap();
      expect(state().sheet, isNull);
    });

    test('the fixture PIN opens settings; a wrong PIN shakes and clears', () {
      controller.staffTap();
      controller.staffTap();
      controller.staffTap();
      for (final d in ['1', '1', '1', '1']) {
        controller.pinPress(d);
      }
      expect(state().pinError, isTrue);
      controller.tick();
      expect(state().pinError, isFalse);
      expect(state().pinEntry, isEmpty);
      for (final d in ['2', '4', '6', '8']) {
        controller.pinPress(d);
      }
      expect(state().screen, KioskScreen.settings);
      expect(state().sheet, isNull);
    });
  });

  group('toast', () {
    test('the added toast decays after its ticks', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      controller.openItem('d1');
      controller.submitDraft();
      expect(state().toast, 'added');
      controller.tick();
      controller.tick();
      controller.tick();
      expect(state().toast, isNull);
    });
  });

  group('cart editing', () {
    test('editing a line updates in place and returns to the cart sheet', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      controller.openItem('b1');
      controller.submitDraft(); // 4000 (included weight)
      final lineId = state().cart.single.lineId;
      controller.editCartLine(lineId);
      expect(state().draft?.editingLineId, lineId);
      controller.toggleOption('weight', 'w360');
      controller.submitDraft();
      final s = state();
      expect(s.sheet, KioskSheet.cart);
      expect(s.cart.single.lineId, lineId);
      expect(s.cart.single.unitMinor, 6500);
    });

    test('steppers clamp at one and remove deletes the line', () {
      controller.startFromAttract();
      controller.pickService(KioskServiceType.takeaway);
      controller.openItem('d1');
      controller.submitDraft();
      final lineId = state().cart.single.lineId;
      controller.decrementLine(lineId);
      expect(state().cart.single.quantity, 1);
      controller.incrementLine(lineId);
      expect(state().cart.single.quantity, 2);
      controller.removeLine(lineId);
      expect(state().cart, isEmpty);
    });
  });
}
