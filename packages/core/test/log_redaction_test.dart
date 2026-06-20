import 'package:restoflow_core/restoflow_core.dart';
import 'package:test/test.dart';

/// Captures everything written through the [RestoLogger] contract so the test
/// can assert no raw secret material reaches the log sink.
class _CapturingLogger implements RestoLogger {
  final StringBuffer _buffer = StringBuffer();
  String get output => _buffer.toString();

  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _buffer.writeln('$level $message ${error ?? ''}');
  }
}

void main() {
  test(
    'logging a SecretValue/SecretRef never emits the raw secret (RF-021)',
    () {
      const raw = 'test-secret-placeholder';
      final secret = SecretValue(raw);
      final ref = SecretRef('ref:test-device-secret');
      final logger = _CapturingLogger();

      // Simulate code paths that interpolate a secret + ref into a log/error,
      // including routing a SecretValue through the `error:` channel (which the
      // logger stringifies) and an exception built from a SecretRef.
      logger.log(LogLevel.info, 'stored secret $secret under $ref');
      logger.log(
        LogLevel.error,
        'read failed for $ref',
        error: SecretCorruptedException(ref),
      );
      logger.log(LogLevel.error, 'crypto failure', error: secret);

      final out = logger.output;
      expect(
        out,
        isNot(contains(raw)),
        reason: 'raw secret must never reach the log sink',
      );
      expect(out, contains('***redacted***'));
      expect(out, contains('ref:test-device-secret'));
    },
  );
}
