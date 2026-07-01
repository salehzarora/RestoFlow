import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/context/device_context.dart';
import 'package:restoflow_dashboard/src/context/selected_context_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceContext / DeviceContextController (RF-152 foundation)', () {
    test('is ABSENT by default and reports no paired device', () {
      final controller = DeviceContextController();
      expect(controller.context, isNull);
      expect(controller.hasPairedDevice, isFalse);
    });

    test('clear() on an absent controller is a no-op (no listeners fired)', () {
      final controller = DeviceContextController();
      var notified = 0;
      controller.addListener(() => notified++);
      controller.clear();
      expect(notified, 0);
      expect(controller.context, isNull);
    });

    test('isPaired is true only with a non-empty deviceId', () {
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
          deviceId: 'device-1',
        ).isPaired,
        isTrue,
      );
    });
  });

  group('SelectedContextStore (RF-152)', () {
    test('InMemory store round-trips then clears', () async {
      final store = InMemorySelectedContextStore();
      expect(await store.readSelectedMembershipId(), isNull);
      await store.writeSelectedMembershipId('m-1');
      expect(await store.readSelectedMembershipId(), 'm-1');
      await store.clear();
      expect(await store.readSelectedMembershipId(), isNull);
    });

    test(
      'SharedPreferences-backed store round-trips then clears (persists only '
      'the non-secret membership id)',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = SharedPreferencesSelectedContextStore();
        expect(await store.readSelectedMembershipId(), isNull);
        await store.writeSelectedMembershipId('m-2');
        expect(await store.readSelectedMembershipId(), 'm-2');
        await store.clear();
        expect(await store.readSelectedMembershipId(), isNull);
      },
    );
  });
}
