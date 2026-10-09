import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show SupabaseKitchenDispatchAckRepository;

/// ORDER-EDIT-001F — the device-token client the DIRECT change-slip print
/// reports its `order_edit` dispatch through (design §7.3): `transport_accepted`
/// once the slip reached the printer, `failed_retryable` (with a safe code)
/// when it did not. The dispatch is born claimed by THIS till, and only the
/// claim holder may acknowledge it.
///
/// Typed and closed: the POS never names the RPC itself — the raw
/// acknowledgement RPC stays inside `restoflow_feature_auth`
/// (`SupabaseKitchenDispatchAckRepository`).
///
/// Null by default (demo mode / tests: no acknowledgement is ever sent);
/// `main.dart` overrides it from the device seams, built on the SAME
/// device-session secret store and authenticated transport as every other
/// device-token repository.
final posKitchenDispatchAckProvider =
    Provider<SupabaseKitchenDispatchAckRepository?>((_) => null);
