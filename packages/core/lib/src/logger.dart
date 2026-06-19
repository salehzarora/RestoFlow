/// Severity of a log record, from most to least verbose.
enum LogLevel { debug, info, warning, error }

/// A minimal logging hook interface.
///
/// Apps provide concrete implementations; packages depend only on this
/// interface. Implementations MUST redact secrets, tokens, full PINs, and
/// personal data, and log money only as integer minor units
/// (docs/SECURITY_AND_THREAT_MODEL.md section 12). This interface holds no logic.
abstract interface class RestoLogger {
  /// Records a single log entry.
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  });
}
