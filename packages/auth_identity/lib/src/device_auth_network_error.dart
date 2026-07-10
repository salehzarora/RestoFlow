import 'dart:async';

import 'package:supabase/supabase.dart';

/// PILOT-OFFLINE-BOOT-001: is a device-auth bootstrap failure a NETWORK/offline
/// problem (the venue Wi‑Fi is down or slow) rather than a genuine server-side
/// auth rejection (e.g. anonymous sign-ins disabled on the project)?
///
/// The composition root uses this to pick the RIGHT honest state: a network
/// error gets the friendly, retryable offline screen; a real auth/config
/// rejection keeps the existing "sign-in unavailable" help page. It NEVER treats
/// an auth rejection as "just offline" (which would hide a real config problem
/// behind an endless retry).
bool isDeviceAuthNetworkError(Object error) {
  // gotrue's OWN retryable marker — connection failures, timeouts, 5xx, 429.
  // (Subtype of AuthException, so it MUST be checked before the general case.)
  if (error is AuthRetryableFetchException) return true;
  // The server ANSWERED with an auth error (anon disabled, other 4xx). That is
  // a config/auth problem, not a network one — keep the honest help page.
  if (error is AuthException) return false;
  // A request that never got an answer. Match TimeoutException directly; match
  // socket / HTTP-client transport errors by type name so this stays web-safe
  // (web has no dart:io SocketException to import).
  if (error is TimeoutException) return true;
  final typeName = error.runtimeType.toString();
  return typeName.contains('SocketException') ||
      typeName.contains('ClientException') ||
      typeName.contains('HandshakeException') ||
      typeName.contains('ConnectionException') ||
      typeName.contains('HttpException');
}
