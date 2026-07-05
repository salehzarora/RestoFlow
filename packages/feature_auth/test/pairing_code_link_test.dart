import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

/// LIVE-DEVICE-001 — `?pair=CODE` URL prefill parsing (UI-only; no backend).
void main() {
  group('pairingCodeFromUri', () {
    test('reads the pair query param from a hosted /pos link', () {
      expect(
        pairingCodeFromUri(Uri.parse('https://app.example/pos?pair=ABC123')),
        'ABC123',
      );
    });

    test('reads it from a /kds link too (with a base-href subpath)', () {
      expect(
        pairingCodeFromUri(Uri.parse('https://app.example/kds/?pair=XYZ-9')),
        'XYZ-9',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        pairingCodeFromUri(Uri.parse('https://app.example/pos?pair=%20ABC%20')),
        'ABC',
      );
    });

    test('null when the param is absent', () {
      expect(pairingCodeFromUri(Uri.parse('https://app.example/pos')), isNull);
    });

    test('null when the param is blank', () {
      expect(
        pairingCodeFromUri(Uri.parse('https://app.example/pos?pair=')),
        isNull,
      );
    });

    test('ignores other query params', () {
      expect(
        pairingCodeFromUri(
          Uri.parse('https://app.example/pos?lang=ar&pair=CODE&x=1'),
        ),
        'CODE',
      );
    });
  });

  test('pairingCodeFromUrl() returns null off-web (non-web test VM)', () {
    // kIsWeb is false in the Dart VM test host, so there is no URL prefill.
    expect(pairingCodeFromUrl(), isNull);
  });
}
