import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

Shift _shift({
  String id = 's1',
  String org = 'org-1',
  String rest = 'rest-1',
  String branch = 'branch-1',
}) => Shift(
  shiftId: id,
  organizationId: org,
  restaurantId: rest,
  branchId: branch,
);

CashDrawerSession _drawer({
  String id = 'd1',
  String shiftId = 's1',
  String org = 'org-1',
  String rest = 'rest-1',
  String branch = 'branch-1',
}) => CashDrawerSession(
  cashDrawerSessionId: id,
  shiftId: shiftId,
  organizationId: org,
  restaurantId: rest,
  branchId: branch,
  openingFloatMinor: 10000,
);

void main() {
  group('binding requires exactly one shift (RF-037 AC#1)', () {
    test('a drawer with an empty shiftId cannot be constructed (unbound)', () {
      expect(
        () => CashDrawerSession(
          cashDrawerSessionId: 'd1',
          shiftId: '',
          organizationId: 'org-1',
          restaurantId: 'rest-1',
          branchId: 'branch-1',
          openingFloatMinor: 0,
        ),
        throwsA(isA<UnboundCashDrawerSessionException>()),
      );
    });

    test('a drawer bound to a different shift is rejected', () {
      // Immutable shiftId 's1' cannot be bound to shift 's2'.
      expect(
        () => ShiftCashDrawerBinding().bind(
          shift: _shift(id: 's2'),
          drawer: _drawer(shiftId: 's1'),
        ),
        throwsA(isA<UnboundCashDrawerSessionException>()),
      );
    });
  });

  group('binding tenant match (RF-037)', () {
    test('organization mismatch is rejected', () {
      expect(
        () => ShiftCashDrawerBinding().bind(
          shift: _shift(org: 'org-1'),
          drawer: _drawer(org: 'org-2'),
        ),
        throwsA(isA<ShiftTenantMismatchException>()),
      );
    });

    test('restaurant mismatch is rejected', () {
      expect(
        () => ShiftCashDrawerBinding().bind(
          shift: _shift(rest: 'rest-1'),
          drawer: _drawer(rest: 'rest-2'),
        ),
        throwsA(isA<ShiftTenantMismatchException>()),
      );
    });

    test('branch mismatch is rejected', () {
      expect(
        () => ShiftCashDrawerBinding().bind(
          shift: _shift(branch: 'branch-1'),
          drawer: _drawer(branch: 'branch-2'),
        ),
        throwsA(isA<ShiftTenantMismatchException>()),
      );
    });
  });

  group('one non-terminal drawer per shift (RF-037)', () {
    test('a second open drawer on the same shift is rejected', () {
      final binding = ShiftCashDrawerBinding();
      final shift = _shift();
      binding.bind(
        shift: shift,
        drawer: _drawer(id: 'd1'),
      );
      expect(
        () => binding.bind(
          shift: shift,
          drawer: _drawer(id: 'd2'),
        ),
        throwsA(isA<ShiftAlreadyHasDrawerException>()),
      );
    });

    test('a reconciled (terminal) drawer no longer blocks a new drawer', () {
      final binding = ShiftCashDrawerBinding();
      final shift = _shift();
      final first = _drawer(id: 'd1')
        ..activate()
        ..startCounting()
        ..recordCount(expectedCashMinor: 10000, countedAmountMinor: 10000)
        ..reconcile();
      binding.bind(shift: shift, drawer: first);
      expect(first.isTerminal, isTrue);
      expect(
        () => binding.bind(
          shift: shift,
          drawer: _drawer(id: 'd2'),
        ),
        returnsNormally,
      );
    });

    test('binding a valid drawer records it', () {
      final binding = ShiftCashDrawerBinding();
      binding.bind(shift: _shift(), drawer: _drawer());
      expect(binding.drawers, hasLength(1));
    });
  });
}
