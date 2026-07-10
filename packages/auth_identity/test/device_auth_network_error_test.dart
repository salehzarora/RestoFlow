import 'dart:async';
import 'dart:io';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

/// PILOT-OFFLINE-BOOT-001: only genuine NETWORK failures are classified as
/// "offline" (the retryable screen). A server-side auth rejection (e.g.
/// anonymous sign-ins disabled) is NOT offline — it keeps the honest config
/// help page — so a real config problem is never hidden behind endless retries.
void main() {
  group('isDeviceAuthNetworkError', () {
    test('gotrue AuthRetryableFetchException is a network error', () {
      expect(
        isDeviceAuthNetworkError(
          AuthRetryableFetchException(message: 'connection failed'),
        ),
        isTrue,
      );
    });

    test('a server auth rejection (anon disabled) is NOT a network error', () {
      // AuthApiException = the server answered with an auth error. This must map
      // to the config help page, NOT the offline retry screen.
      expect(
        isDeviceAuthNetworkError(
          AuthApiException(
            'Anonymous sign-ins are disabled',
            statusCode: '422',
          ),
        ),
        isFalse,
      );
      expect(
        isDeviceAuthNetworkError(const AuthException('bad request')),
        isFalse,
      );
    });

    test('a socket error is a network error', () {
      expect(
        isDeviceAuthNetworkError(
          const SocketException('Network is unreachable'),
        ),
        isTrue,
      );
    });

    test('a timeout is a network error', () {
      expect(isDeviceAuthNetworkError(TimeoutException('timed out')), isTrue);
    });

    test('an unknown/other error is NOT treated as offline (conservative)', () {
      // We do not guess: only clearly-network errors get the offline screen; an
      // ambiguous error keeps the existing (config help) behaviour.
      expect(isDeviceAuthNetworkError(StateError('boom')), isFalse);
      expect(isDeviceAuthNetworkError(FormatException('nope')), isFalse);
    });
  });
}
