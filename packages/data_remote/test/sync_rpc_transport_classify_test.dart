import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// RF-063: the pure error-code classifier (no Supabase SDK needed at test time).
void main() {
  group('classifyPostgrestCode', () {
    test('42501 -> auth (reauth signal)', () {
      expect(classifyPostgrestCode('42501'), SyncTransportErrorKind.auth);
    });

    test('throttling/5xx codes -> transient', () {
      expect(classifyPostgrestCode('429'), SyncTransportErrorKind.transient);
      expect(classifyPostgrestCode('503'), SyncTransportErrorKind.transient);
      expect(classifyPostgrestCode('504'), SyncTransportErrorKind.transient);
    });

    test('null and other codes -> server', () {
      expect(classifyPostgrestCode(null), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('22000'), SyncTransportErrorKind.server);
      expect(classifyPostgrestCode('PGRST116'), SyncTransportErrorKind.server);
    });
  });
}
