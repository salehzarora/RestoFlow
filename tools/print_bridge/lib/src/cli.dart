/// CLI help + argument helpers for the reference print bridge (RF-115).
///
/// Kept separate from [BridgeConfig] so `--help` is detected BEFORE any config
/// parsing (help must never start the server), and so the usage text is
/// unit-testable.
library;

/// True when the args request help (`--help` / `-h`), anywhere in the list.
bool isHelpRequested(List<String> args) =>
    args.contains('--help') || args.contains('-h');

/// The `--help` / usage text. Honest about the demo sink and local-only binding.
const String kPrintBridgeUsage = '''
RestoFlow print bridge (RF-115) — a LOCAL-ONLY companion service that receives
ESC/POS print jobs from the POS/KDS over HTTP and forwards them to a printer, or
accepts them into a DEMO SINK that honestly does NOT print.

Usage:
  dart run print_bridge [options]

Options:
  -h, --help                     Show this help and exit.
      --demo, --sink             Demo SINK mode: accept jobs but do NOT print
                                 (this is the default when no --target is given).
                                 Nothing reaches hardware.
      --target <host:port>       A RAW/TCP 9100 ESC/POS printer target. The name
                                 defaults to --printer-name (or "default").
      --target <name=host:port>  A named printer target (repeatable).
      --printer-name <name>      Name for an unnamed --target (default "default").
      --host <addr>              Loopback address to bind (default 127.0.0.1).
                                 LOCAL-ONLY: only 127.0.0.1 / localhost / ::1.
      --port <n>                 Port to bind (default 8787).
      --config <path.json>       Load targets/port from a JSON config file.
      --max-bytes <n>            Reject print payloads larger than n bytes
                                 (default 1048576).

Examples:
  dart run print_bridge --demo
      Demo sink on http://127.0.0.1:8787 — accepts jobs, prints nothing.
  dart run print_bridge --target 192.0.2.10:9100
      Forward jobs to a network ESC/POS printer at 192.0.2.10:9100.
  dart run print_bridge --target receipt=192.0.2.10:9100 --target grill=192.0.2.11:9100
      Two named network printers.

Point the POS/KDS at the bridge (loopback only):
  flutter run -d chrome --dart-define=RESTOFLOW_PRINT_BRIDGE_URL=http://127.0.0.1:8787

The printer's LAN target lives ONLY here, never in the app or the server. A demo
sink NEVER prints hardware; a job only reports "sent to printer" when a real
target confirms the socket write — never a faked physical print.
''';
