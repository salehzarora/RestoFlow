/// A RAW 9100 printer target: a host + TCP port the bridge writes bytes to.
///
/// Kept ONLY in the bridge's local config (RF-115) — never in the app/server.
class PrinterTarget {
  const PrinterTarget(this.host, this.port);

  final String host;
  final int port;

  /// Parses `host:port` (e.g. `192.0.2.50:9100`). Throws [FormatException] on a
  /// malformed value.
  factory PrinterTarget.parse(String value) {
    final idx = value.lastIndexOf(':');
    if (idx <= 0 || idx == value.length - 1) {
      throw FormatException('expected host:port', value);
    }
    final host = value.substring(0, idx);
    final port = int.tryParse(value.substring(idx + 1));
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('invalid port', value);
    }
    return PrinterTarget(host, port);
  }

  @override
  String toString() => '$host:$port';
}
