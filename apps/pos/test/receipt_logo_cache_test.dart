import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_pos/src/data/receipt_logo_raster_cache.dart';

ReceiptLogoCacheKey _key({
  String org = 'org1',
  String restaurant = 'rest1',
  int logoVersion = 3,
  String profileId = 'label80x80',
  int widthDots = 576,
  int prep = 1,
}) => ReceiptLogoCacheKey(
  organizationId: org,
  restaurantId: restaurant,
  logoVersion: logoVersion,
  mediaProfileId: profileId,
  widthDots: widthDots,
  preprocessingVersion: prep,
);

ReceiptLogoCacheEntry _entry() => ReceiptLogoCacheEntry(
  rasterData: Uint8List.fromList(List<int>.generate(72 * 4, (i) => i % 256)),
  widthBytes: 72,
  heightDots: 4,
  sourceBytes: Uint8List.fromList([9, 8, 7, 6]),
  sourceMime: 'image/png',
);

void main() {
  group('ReceiptLogoCacheKey', () {
    test('storageKey includes every identity field', () {
      final k = _key();
      expect(k.storageKey, 'org1|rest1|3|label80x80|576|1');
    });
    test('differs when ANY field differs (no collisions)', () {
      final base = _key().storageKey;
      expect(_key(org: 'org2').storageKey, isNot(base));
      expect(_key(restaurant: 'rest2').storageKey, isNot(base));
      expect(_key(logoVersion: 4).storageKey, isNot(base));
      expect(_key(profileId: 'label50x50').storageKey, isNot(base));
      expect(_key(widthDots: 384).storageKey, isNot(base));
      expect(_key(prep: 2).storageKey, isNot(base));
    });
    test('fileName is stable + filesystem-safe (hashed)', () {
      expect(_key().fileName, _key().fileName);
      expect(_key().fileName.contains('|'), isFalse);
      expect(_key().fileName.endsWith('.logoraster'), isTrue);
    });
  });

  group('envelope codec', () {
    test('round-trips an entry for a matching key', () {
      final k = _key();
      final json = encodeReceiptLogoEnvelope(k, _entry());
      final decoded = decodeReceiptLogoEnvelope(json, k);
      expect(decoded, isNotNull);
      expect(decoded!.rasterData, _entry().rasterData);
      expect(decoded.widthBytes, 72);
      expect(decoded.heightDots, 4);
      expect(decoded.sourceMime, 'image/png');
      expect(decoded.sourceBytes, _entry().sourceBytes);
    });
    test('a DIFFERENT key (version/width/tenant) => miss', () {
      final json = encodeReceiptLogoEnvelope(_key(), _entry());
      expect(decodeReceiptLogoEnvelope(json, _key(logoVersion: 4)), isNull);
      expect(decodeReceiptLogoEnvelope(json, _key(widthDots: 384)), isNull);
      expect(decodeReceiptLogoEnvelope(json, _key(org: 'other')), isNull);
      expect(
        decodeReceiptLogoEnvelope(json, _key(profileId: 'label50x50')),
        isNull,
      );
    });
    test('a corrupt / tampered envelope => miss (checksum guard)', () {
      final json = encodeReceiptLogoEnvelope(_key(), _entry());
      // Flip a character inside the base64 raster payload.
      final tampered = json.replaceFirst('"raster":"', '"raster":"AAAA');
      expect(decodeReceiptLogoEnvelope(tampered, _key()), isNull);
      expect(decodeReceiptLogoEnvelope('not json', _key()), isNull);
      expect(decodeReceiptLogoEnvelope('{}', _key()), isNull);
    });
  });

  group('InMemoryReceiptLogoRasterCache', () {
    test('write then read returns the entry; a version bump misses', () async {
      final cache = InMemoryReceiptLogoRasterCache();
      final k = _key();
      expect(await cache.read(k), isNull); // cold miss
      await cache.write(k, _entry());
      final hit = await cache.read(k);
      expect(hit, isNotNull);
      expect(hit!.rasterData, _entry().rasterData);
      // A new logo version is a clean miss (invalidation).
      expect(await cache.read(_key(logoVersion: 99)), isNull);
    });
  });
}
