import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// EGRESS-REMEDIATION-001 — end-to-end URL reuse through the REAL menu
/// provider.
///
/// The business contract this pins: `ref.invalidate(posMenuProvider)` (the
/// exact call the resume/reconnect/availability paths make) KEEPS refetching
/// menu data — freshness is untouched — while unchanged image paths keep
/// their previous signed URL, so no image-cache layer is busted and no bytes
/// re-download. A CHANGED (versioned) image path resolves fresh immediately
/// through the very same refresh, proving an edited image needs no restart.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  int calls = 0;
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls += 1;
    return _handler(function, params);
  }
}

class _CountingResolver implements DeviceImageUrlResolver {
  int signCalls = 0;
  int token = 0;
  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    signCalls += 1;
    token += 1;
    return {
      for (final k in objectKeys) k: 'https://signed.example/$k?token=t$token',
    };
  }
}

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

Map<String, dynamic> _menuEnvelope(String colaImagePath) => {
  'ok': true,
  'currency_code': 'ILS',
  'categories': [
    {'id': 'drinks', 'name': 'Drinks'},
  ],
  'items': [
    {
      'id': 'cola',
      'name': 'Cola',
      'base_price_minor': 900,
      'menu_category_id': 'drinks',
      'image_path': colaImagePath,
      'availability': 'available',
    },
    {
      'id': 'soda',
      'name': 'Soda',
      'base_price_minor': 800,
      'menu_category_id': 'drinks',
      'image_path': 'menu/soda-v1.png',
      'availability': 'available',
    },
  ],
};

void main() {
  test('menu refresh with UNCHANGED image paths refetches business data but '
      'reuses the previous signed URLs (zero new signing)', () async {
    var colaPath = 'menu/cola-v1.png';
    final transport = _FakeTransport((fn, p) => _menuEnvelope(colaPath));
    final inner = _CountingResolver();
    final caching = CachingDeviceImageUrlResolver(inner);
    final c = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posAuthTransportProvider.overrideWithValue(transport),
        posSyncSessionProvider.overrideWithValue(_session),
        posImageUrlResolverProvider.overrideWithValue(caching),
      ],
    );
    addTearDown(c.dispose);

    final first = await c.read(posMenuProvider.future);
    final firstColaUrl = first.items.firstWhere((i) => i.id == 'cola').imageUrl;
    expect(transport.calls, 1);
    expect(inner.signCalls, 1);
    expect(firstColaUrl, contains('token=t1'));

    // THE RESUME PATH'S EXACT CALL: business data must refresh; media must
    // not churn.
    c.invalidate(posMenuProvider);
    final second = await c.read(posMenuProvider.future);
    final secondColaUrl = second.items
        .firstWhere((i) => i.id == 'cola')
        .imageUrl;
    expect(transport.calls, 2, reason: 'menu freshness is untouched');
    expect(inner.signCalls, 1, reason: 'no re-sign for unchanged paths');
    expect(
      secondColaUrl,
      firstColaUrl,
      reason: 'identical URL string = every image-cache layer stays hot',
    );

    // An EDITED image arrives as a NEW versioned path via the ordinary
    // refresh — it must resolve immediately, no restart, no cache clearing.
    colaPath = 'menu/cola-v2.png';
    c.invalidate(posMenuProvider);
    final third = await c.read(posMenuProvider.future);
    final thirdColaUrl = third.items.firstWhere((i) => i.id == 'cola').imageUrl;
    final thirdSodaUrl = third.items.firstWhere((i) => i.id == 'soda').imageUrl;
    expect(inner.signCalls, 2, reason: 'exactly the new path signs');
    expect(thirdColaUrl, contains('cola-v2.png'));
    expect(thirdColaUrl, isNot(firstColaUrl));
    expect(
      thirdSodaUrl,
      contains('token=t1'),
      reason: 'the untouched item keeps its original URL',
    );
  });
}
