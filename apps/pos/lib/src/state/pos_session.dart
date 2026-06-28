import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The current authenticated POS sync session - the `(pinSessionId, deviceId)`
/// tuple needed to call `public.sync_push` (RF-126) in real mode.
///
/// It is **null until the platform's PIN/device sign-in flow establishes one**
/// (an authenticated JWT + a valid `start_pin_session` result on a paired,
/// active device). That sign-in flow is NOT wired yet, so this provider stays
/// null and the real-mode write repositories (e.g. [RealOutboxRepository]) fail
/// closed - there is no path to a false "live" submit. When the sign-in flow
/// lands it overrides this provider with the real [SyncSession]; nothing else in
/// the write path changes.
final posSyncSessionProvider = Provider<SyncSession?>((ref) => null);
