import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

CashDrawerSession _countedDrawer({
  required int expected,
  required int counted,
}) {
  final drawer =
      CashDrawerSession(
          cashDrawerSessionId: 'd1',
          shiftId: 's1',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          openingFloatMinor: 10000,
        )
        ..activate()
        ..startCounting();
  drawer.recordCount(expectedCashMinor: expected, countedAmountMinor: counted);
  return drawer;
}

Shift _countedShift({required int expected, required int counted}) {
  final shift =
      Shift(
          shiftId: 's1',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
        )
        ..open()
        ..startClosing();
  shift.closeAndCount(expectedTotalMinor: expected, countedTotalMinor: counted);
  return shift;
}

void main() {
  group('drawer variance = counted - expected (RF-037 AC#2)', () {
    test('counted > expected -> positive (overage)', () {
      expect(
        _countedDrawer(expected: 10000, counted: 10500).varianceMinor,
        500,
      );
    });

    test('counted < expected -> negative (shortage)', () {
      expect(
        _countedDrawer(expected: 10000, counted: 9700).varianceMinor,
        -300,
      );
    });

    test('counted == expected -> zero', () {
      expect(_countedDrawer(expected: 10000, counted: 10000).varianceMinor, 0);
    });

    test('variance + counted/expected are integer minor units', () {
      final drawer = _countedDrawer(expected: 10000, counted: 10500);
      expect(drawer.varianceMinor, isA<int>());
      expect(drawer.expectedCashMinor, isA<int>());
      expect(drawer.countedAmountMinor, isA<int>());
      expect(drawer.openingFloatMinor, isA<int>());
    });

    test('variance is preserved after reconcile', () {
      final drawer = _countedDrawer(expected: 10000, counted: 9800)
        ..reconcile();
      expect(drawer.status, CashDrawerSessionStatus.reconciled);
      expect(drawer.varianceMinor, -200);
    });
  });

  group('shift variance = counted - expected (RF-037 AC#2)', () {
    test('counted > expected -> positive', () {
      expect(_countedShift(expected: 5000, counted: 5250).varianceMinor, 250);
    });

    test('counted < expected -> negative', () {
      expect(_countedShift(expected: 5000, counted: 4900).varianceMinor, -100);
    });

    test('counted == expected -> zero', () {
      expect(_countedShift(expected: 5000, counted: 5000).varianceMinor, 0);
    });

    test('variance is preserved after reconcile', () {
      final shift = _countedShift(expected: 5000, counted: 5300)..reconcile();
      expect(shift.status, ShiftStatus.reconciled);
      expect(shift.varianceMinor, 300);
    });
  });

  group('opening float validation (RF-037)', () {
    test('a negative opening float is rejected', () {
      expect(
        () => CashDrawerSession(
          cashDrawerSessionId: 'd1',
          shiftId: 's1',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          openingFloatMinor: -1,
        ),
        throwsA(isA<InvalidMinorAmountException>()),
      );
    });

    test('a zero opening float is allowed', () {
      final drawer = CashDrawerSession(
        cashDrawerSessionId: 'd1',
        shiftId: 's1',
        organizationId: 'org-1',
        restaurantId: 'rest-1',
        branchId: 'branch-1',
        openingFloatMinor: 0,
      );
      expect(drawer.openingFloatMinor, 0);
    });
  });
}
