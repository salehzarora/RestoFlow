import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_native_printing/restoflow_native_printing.dart';
import 'package:restoflow_printing/restoflow_printing.dart';

/// PRINT-LAYOUT-001A (Persistence, test A) — the media profile rides on the saved
/// printer destination config: it round-trips, defaults to continuous80 for
/// legacy/absent/malformed, copies with the config, and is part of equality.
void main() {
  test('the const default id matches MediaProfile.continuous80', () {
    expect(
      const NetworkPrinterConfig(host: 'h').mediaProfile.id,
      MediaProfileId.continuous80,
    );
    expect(
      const BluetoothPrinterConfig(address: 'a').mediaProfile.id,
      MediaProfileId.continuous80,
    );
  });

  group('NetworkPrinterConfig', () {
    test('legacy JSON with no mediaProfile decodes as continuous80', () {
      final c = NetworkPrinterConfig.fromJson({'host': '10.0.0.5', 'port': 9100});
      expect(c, isNotNull);
      expect(c!.mediaProfile.id, MediaProfileId.continuous80);
      // A continuous-80 config serializes to the byte-identical legacy shape
      // (no mediaProfile key).
      expect(c.toJson().containsKey('mediaProfile'), isFalse);
    });

    test('a fixed-label profile round-trips through JSON', () {
      final saved = NetworkPrinterConfig(
        host: '10.0.0.5',
        mediaProfileId: MediaProfile.label50x50.idKey,
      );
      expect(saved.toJson()['mediaProfile'], 'label50x50');
      final restored = NetworkPrinterConfig.fromJson(saved.toJson());
      expect(restored!.mediaProfile.id, MediaProfileId.label50x50);
      expect(restored.host, '10.0.0.5'); // other fields intact
      expect(restored.port, 9100);
    });

    test('a malformed profile id decodes safely to continuous80', () {
      final c = NetworkPrinterConfig.fromJson({
        'host': '10.0.0.5',
        'mediaProfile': 'not_a_real_profile',
      });
      expect(c!.mediaProfile.id, MediaProfileId.continuous80);
      // A non-string malformed value also degrades safely (never a crash).
      final c2 = NetworkPrinterConfig.fromJson({
        'host': '10.0.0.5',
        'mediaProfile': 42,
      });
      expect(c2!.mediaProfile.id, MediaProfileId.continuous80);
    });

    test('copyWith changes ONLY the profile, preserving host/port/name', () {
      const base = NetworkPrinterConfig(host: '10.0.0.5', port: 9101, name: 'Front');
      final copy = base.copyWith(mediaProfileId: MediaProfile.label80x80.idKey);
      expect(copy.host, '10.0.0.5');
      expect(copy.port, 9101);
      expect(copy.name, 'Front');
      expect(copy.mediaProfile.id, MediaProfileId.label80x80);
      // The original is untouched (independent destinations don't cross-edit).
      expect(base.mediaProfile.id, MediaProfileId.continuous80);
    });

    test('profile participates in equality', () {
      const a = NetworkPrinterConfig(host: 'h', mediaProfileId: 'label50x50');
      const b = NetworkPrinterConfig(host: 'h', mediaProfileId: 'label50x50');
      const c = NetworkPrinterConfig(host: 'h', mediaProfileId: 'label80x80');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('BluetoothPrinterConfig', () {
    test('a fixed-label profile round-trips; legacy absent => continuous80', () {
      final saved = BluetoothPrinterConfig(
        address: 'DC:0D:30:AA:BB:CC',
        mediaProfileId: MediaProfile.label80x80.idKey,
      );
      final restored = BluetoothPrinterConfig.fromJson(saved.toJson());
      expect(restored!.mediaProfile.id, MediaProfileId.label80x80);
      expect(restored.address, 'DC:0D:30:AA:BB:CC');

      final legacy = BluetoothPrinterConfig.fromJson({'address': 'DC:0D:30:AA:BB:CC'});
      expect(legacy!.mediaProfile.id, MediaProfileId.continuous80);
      expect(legacy.toJson().containsKey('mediaProfile'), isFalse);
    });

    test('copyWith carries the profile with the whole config (copy action)', () {
      const customer = BluetoothPrinterConfig(
        address: 'DC:0D:30:AA:BB:CC',
        name: 'Star',
        mediaProfileId: 'label50x50',
      );
      // The kitchen slot copying the customer printer keeps its profile too.
      final kitchen = customer.copyWith();
      expect(kitchen.address, customer.address);
      expect(kitchen.name, customer.name);
      expect(kitchen.mediaProfile.id, MediaProfileId.label50x50);
    });
  });
}
