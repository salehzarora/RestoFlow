import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/ids.dart';
import '../data/void_repository.dart';
import 'pos_session.dart';

/// MONEY-VOID-001: the order-cancellation (void) repository. Selects by client
/// runtime mode: the in-memory [DemoVoidStore] in demo mode (the DEFAULT), or the
/// real [RealVoidRepository] in real mode, which posts an `order.void` op to
/// `public.sync_push` over the shared [posAuthTransportProvider] transport and
/// [posSyncSessionProvider] session; with no transport or no session it fails
/// closed (no backend contact, no fake local success). Tests can override this
/// provider, [runtimeConfigProvider], [posAuthTransportProvider], or
/// [posSyncSessionProvider] to force a mode.
final voidRepositoryProvider = Provider<VoidRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return const DemoVoidStore();
  return RealVoidRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});
