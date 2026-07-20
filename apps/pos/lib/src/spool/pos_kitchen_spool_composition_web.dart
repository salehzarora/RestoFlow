import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pos_kitchen_spool_hooks.dart';

/// KITCHEN-MODE-001C2B — the WEB composition branch: fail closed by
/// construction.
///
/// This file is what the Flutter WEB compiler links (the conditional import
/// in `pos_kitchen_spool_composition.dart` defaults here; only
/// `dart.library.io` platforms get the native branch). It has NO native
/// imports — no dart:io, no drift/NativeDatabase/sqlite3, no path_provider,
/// no secure spool storage, no data_local, no pull/ack repositories — so
/// web POS cannot construct the spool runtime, open the dedicated database,
/// touch the documents directory, provision keys, pull, or acknowledge.
/// There is deliberately NO browser/localStorage fallback of any kind.
PosKitchenSpoolLifecycleHooks? buildPosKitchenSpoolRuntime(Ref ref) => null;
