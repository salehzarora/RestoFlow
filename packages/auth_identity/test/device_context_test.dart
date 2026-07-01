import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:test/test.dart';

/// A fake [DevicePairingRepository] (no backend) for the seam contract tests.
class _FakePairing implements DevicePairingRepository {
  _FakePairing(this._result);
  final Result<DeviceContext, PairingFailure> _result;
  String? lastCode;
  String? lastDeviceType;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    lastCode = code;
    lastDeviceType = deviceType;
    return _result;
  }
}

void main() {
  group('DeviceContext (RF-153 shared model)', () {
    test('is NOT paired without a non-empty deviceId (never fabricated)', () {
      expect(
        const DeviceContext(organizationId: 'o', branchId: 'b').isPaired,
        isFalse,
      );
      expect(
        const DeviceContext(
          organizationId: 'o',
          branchId: 'b',
          deviceId: '',
        ).isPaired,
        isFalse,
      );
      expect(
        const DeviceContext(
          organizationId: 'o',
          branchId: 'b',
          deviceId: 'd',
        ).isPaired,
        isTrue,
      );
    });

    test('matchesScope compares organization + branch', () {
      const c = DeviceContext(
        organizationId: 'o1',
        branchId: 'b1',
        deviceId: 'd',
      );
      expect(c.matchesScope(organizationId: 'o1', branchId: 'b1'), isTrue);
      expect(c.matchesScope(organizationId: 'o2', branchId: 'b1'), isFalse);
      expect(c.matchesScope(organizationId: 'o1', branchId: 'b2'), isFalse);
    });

    test('copyWith sets device/station fields while keeping the scope', () {
      const base = DeviceContext(
        organizationId: 'o',
        branchId: 'b',
        restaurantId: 'r',
      );
      final paired = base.copyWith(
        deviceId: 'd1',
        deviceType: 'pos',
        stationId: 's1',
        stationType: 'pos',
        displayName: 'Front POS',
      );
      expect(paired.isPaired, isTrue);
      expect(paired.deviceType, 'pos');
      expect(paired.stationId, 's1');
      expect(paired.organizationId, 'o');
      expect(paired.restaurantId, 'r');
    });
  });

  group('DevicePairingRepository seam', () {
    test('a successful pair returns a paired, scope-matched context', () async {
      final repo = _FakePairing(
        const Success(
          DeviceContext(
            organizationId: 'o',
            branchId: 'b',
            deviceId: 'd',
            deviceType: 'pos',
          ),
        ),
      );
      final result = await repo.pairWithCode(code: 'ABC123', deviceType: 'pos');
      expect(repo.lastCode, 'ABC123');
      expect(repo.lastDeviceType, 'pos');
      expect(result.isSuccess, isTrue);
      final ctx = (result as Success<DeviceContext, PairingFailure>).value;
      expect(ctx.isPaired, isTrue);
      expect(ctx.matchesScope(organizationId: 'o', branchId: 'b'), isTrue);
    });

    test(
      'a failed pair yields a safe PairingFailure (no device fabricated)',
      () async {
        final repo = _FakePairing(
          const Failure(PairingFailure(PairingFailureKind.invalidCode)),
        );
        final result = await repo.pairWithCode(code: 'nope', deviceType: 'kds');
        expect(result.isFailure, isTrue);
        expect(
          (result as Failure<DeviceContext, PairingFailure>).failure.kind,
          PairingFailureKind.invalidCode,
        );
      },
    );
  });
}
