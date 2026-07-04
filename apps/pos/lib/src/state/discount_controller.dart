import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';

import '../data/discount_repository.dart';
import '../data/ids.dart';
import 'pos_session.dart';

/// The order-level discount repository (RF-117 part C). Selects by client runtime
/// mode: the in-memory [DemoDiscountStore] in demo mode (the DEFAULT), or the real
/// [RealDiscountRepository] in real mode, which posts an `order.discount` op to
/// `public.sync_push` over the shared [posAuthTransportProvider] transport and
/// [posSyncSessionProvider] session; with no transport or no session it fails
/// closed (no backend contact, no fake local discount). Tests can override this
/// provider, [runtimeConfigProvider], [posAuthTransportProvider], or
/// [posSyncSessionProvider] to force a mode.
final discountRepositoryProvider = Provider<DiscountRepository>((ref) {
  final cfg = ref.watch(runtimeConfigProvider);
  if (cfg.isDemoMode) return const DemoDiscountStore();
  return RealDiscountRepository(
    ref.watch(posAuthTransportProvider),
    ref.watch(posSyncSessionProvider),
    ref.watch(clientIdGeneratorProvider),
  );
});
