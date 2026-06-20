/// RestoFlow core package - cross-cutting foundations shared by all packages.
///
/// Owns (per docs/ARCHITECTURE.md section 3): Result/error types, environment
/// selection, and logging hooks. Pure Dart - no Flutter, no IO, and no
/// POS/restaurant business rules. Concrete behaviour lands in later tickets.
library;

export 'src/result.dart';
export 'src/app_environment.dart';
export 'src/logger.dart';
// RF-021 security primitives (pure Dart): secret handling + secure-storage
// contract + fail-closed errors. The platform-backed adapter lives elsewhere
// (deferred); the in-memory test fake is in `package:restoflow_core/testing.dart`.
export 'src/secret_value.dart';
export 'src/secure_key_store.dart';
