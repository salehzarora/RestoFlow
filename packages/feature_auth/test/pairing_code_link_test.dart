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

  // LIVE-OPS-001 — the inverse: build the hosted pairing link a Dashboard shows.
  group('pairingRouteForDeviceType', () {
    test('maps pos/kds (case + whitespace insensitive), null otherwise', () {
      expect(pairingRouteForDeviceType('pos'), 'pos');
      expect(pairingRouteForDeviceType('kds'), 'kds');
      expect(pairingRouteForDeviceType('POS'), 'pos');
      expect(pairingRouteForDeviceType('  Kds '), 'kds');
      expect(pairingRouteForDeviceType('printer'), isNull);
      expect(pairingRouteForDeviceType(''), isNull);
    });
  });

  group('pairingLinkForDeviceType', () {
    test('POS -> {origin}/pos?pair=CODE', () {
      expect(
        pairingLinkForDeviceType(
          base: Uri.parse('https://app.example/dashboard?x=1'),
          code: 'ABC123',
          deviceType: 'pos',
        ).toString(),
        'https://app.example/pos?pair=ABC123',
      );
    });

    test('KDS -> {origin}/kds?pair=CODE', () {
      expect(
        pairingLinkForDeviceType(
          base: Uri.parse('https://app.example/'),
          code: 'XYZ-9',
          deviceType: 'kds',
        ).toString(),
        'https://app.example/kds?pair=XYZ-9',
      );
    });

    test('preserves the origin scheme/host/PORT (localhost dev)', () {
      expect(
        pairingLinkForDeviceType(
          base: Uri.parse('http://localhost:5541/#/anything'),
          code: 'DEV1',
          deviceType: 'pos',
        ).toString(),
        'http://localhost:5541/pos?pair=DEV1',
      );
    });

    test('drops the Dashboard path/query — only the origin is kept', () {
      final link = pairingLinkForDeviceType(
        base: Uri.parse(
          'https://resto-flow-phi.vercel.app/settings?tab=devices',
        ),
        code: 'C1',
        deviceType: 'kds',
      )!;
      expect(link.host, 'resto-flow-phi.vercel.app');
      expect(link.path, '/kds');
      expect(link.queryParameters, {'pair': 'C1'});
      expect(link.hasPort, isFalse); // https default port not emitted
    });

    test('percent-encodes a code with URL-unsafe characters', () {
      final link = pairingLinkForDeviceType(
        base: Uri.parse('https://app.example/'),
        code: 'a b&c=%',
        deviceType: 'pos',
      )!;
      // Decoded back it is the original code (round-trips safely).
      expect(link.queryParameters['pair'], 'a b&c=%');
      // The raw query is encoded (no bare space/&/= injected).
      expect(link.query.contains(' '), isFalse);
      expect(pairingCodeFromUri(link), 'a b&c=%'); // parser round-trips it
    });

    test('null for an unknown device type or a blank code', () {
      expect(
        pairingLinkForDeviceType(
          base: Uri.parse('https://app.example/'),
          code: 'C1',
          deviceType: 'printer',
        ),
        isNull,
      );
      expect(
        pairingLinkForDeviceType(
          base: Uri.parse('https://app.example/'),
          code: '   ',
          deviceType: 'pos',
        ),
        isNull,
      );
    });
  });

  test(
    'pairingLinkUrlForDeviceType() returns null off-web (non-web test VM)',
    () {
      expect(
        pairingLinkUrlForDeviceType(code: 'C1', deviceType: 'pos'),
        isNull,
      );
    },
  );
}
