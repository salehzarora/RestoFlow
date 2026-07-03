import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:supabase/supabase.dart';

import 'device_image_url_resolver.dart';
import 'supabase_bootstrap_config.dart';

/// Bootstraps the Supabase-backed RPC transport for the auth services
/// (RF-108 Stage 2) from a validated [SupabaseBootstrapConfig].
///
/// The transport construction is INJECTABLE ([transportBuilder]) so unit tests
/// never build a real `SupabaseClient` or touch the network. The default builder
/// is the only place `auth_identity` constructs a `SupabaseClient`, and it runs
/// at app startup (a later stage), not in unit tests.
///
/// SECURITY: the client is constructed from the config's PUBLIC anon key only -
/// the config has already rejected any service-role/secret-looking key
/// (DECISION D-011). Neither the URL nor the anon key is ever logged here. This
/// is a plain object (no global singleton), so the app composition root owns its
/// lifetime and tests can construct it freely.
class SupabaseAuthBootstrap {
  SupabaseAuthBootstrap({
    required SupabaseBootstrapConfig config,
    SyncRpcTransport Function(SupabaseBootstrapConfig config)? transportBuilder,
  }) : _config = config,
       _transportBuilder = transportBuilder ?? _defaultTransportBuilder;

  final SupabaseBootstrapConfig _config;
  final SyncRpcTransport Function(SupabaseBootstrapConfig) _transportBuilder;

  /// Builds the anon-key RPC transport to inject into `AuthContextRepository`
  /// and `PinSessionService`. The same injected transport keeps those services
  /// SDK-agnostic and unit-testable.
  SyncRpcTransport createRpcTransport() => _transportBuilder(_config);

  /// RF-161: builds an anon-key client, signs the DEVICE in ANONYMOUSLY, and
  /// returns the transport carrying that session. This reaches the `authenticated`
  /// grant gate for the device-auth-bridge RPCs (`redeem_device_pairing` etc.)
  /// WITHOUT a service-role key or any membership (DECISION D-011): an anonymous
  /// authenticated principal carries ZERO tenant authority — authorization is the
  /// one-time pairing code / device-session token, verified server-side. Runtime
  /// only (constructs a real client); throws if anonymous sign-in is unavailable,
  /// so the composition root can fall back to a dormant (no-pairing) state.
  Future<SyncRpcTransport> createAnonymousDeviceTransport() async =>
      (await createAnonymousDeviceSession()).transport;

  /// Menu/media sprint: like [createAnonymousDeviceTransport] but ALSO exposes
  /// the device's ONLY storage capability — a read-only signed-URL resolver for
  /// the private RF-110 `menu-images` bucket. Server-side, the resolver is
  /// gated by the `menu_images_device_select` storage policy (an ACTIVE POS
  /// device session bound to this anonymous principal at redeem time; KDS is
  /// excluded — T-014). Anon-key-only, money-free (D-011/T-003).
  Future<
    ({SyncRpcTransport transport, DeviceImageUrlResolver imageUrlResolver})
  >
  createAnonymousDeviceSession() async {
    final client = SupabaseClient(_config.url, _config.anonKey);
    await client.auth.signInAnonymously();
    return (
      transport: SupabaseSyncRpcTransport(client),
      imageUrlResolver: SupabaseDeviceImageUrlResolver(client),
    );
  }
}

/// The real [DeviceImageUrlResolver] over the SAME anonymously-authenticated
/// client as the device transport. Batch-signs via the storage API; keys the
/// device's SELECT policy denies come back as per-key failures and are simply
/// omitted (fail-soft — callers render imageless).
class SupabaseDeviceImageUrlResolver implements DeviceImageUrlResolver {
  SupabaseDeviceImageUrlResolver(this._client);

  /// The RF-110 private bucket id (kept local so this package adds no
  /// feature_menu dependency).
  static const String _bucketId = 'menu-images';

  final SupabaseClient _client;

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    if (objectKeys.isEmpty) return const {};
    final results = await _client.storage
        .from(_bucketId)
        .createSignedUrlsResult(objectKeys, expiresIn.inSeconds);
    return {
      // Per-key failures (policy-denied / missing objects) are dropped —
      // callers fall back to imageless rendering.
      for (final result in results)
        if (result is SignedUrlSuccess) result.path: result.signedUrl,
    };
  }
}

/// The default transport: a real anon-key `SupabaseClient` (pure-Dart `supabase`
/// SDK) wrapped by `SupabaseSyncRpcTransport` (data_remote). The client targets
/// the `public` schema, so only the narrow `public.*` auth wrappers
/// (`get_my_context`, `start_pin_session`) are reachable - the `app` schema
/// stays unexposed. Exercised at runtime only; unit tests inject a fake.
SyncRpcTransport _defaultTransportBuilder(SupabaseBootstrapConfig config) =>
    SupabaseSyncRpcTransport(SupabaseClient(config.url, config.anonKey));
