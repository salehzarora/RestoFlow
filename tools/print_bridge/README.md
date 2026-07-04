# RestoFlow reference print bridge (RF-115)

A tiny, self-contained, **loopback-only** HTTP companion service that turns
prepared ESC/POS print jobs from the RestoFlow POS/KDS web apps into a **real**
(or demo-sink) print.

The web apps cannot open a raw TCP/USB socket to a receipt printer, so the
honest path to a physical printer is a **local bridge**: the app POSTs a job to
`http://127.0.0.1:8787`, and this service either forwards the bytes to a
configured RAW 9100 printer or accepts them into a demo sink.

## Why "sent to the printer" is not "confirmed printed"

ESC/POS over a socket has **no paper-level acknowledgement**. The strongest
truthful terminal state this bridge can report is `sent` — the bytes were
written to the printer's transport. It can go wrong *after* that (paper out,
cover open) with no signal back. So the bridge reports `sent` (delivery
confirmed), never "printed", and the app labels it **"Sent to the printer (not
confirmed printed)"**. A demo sink is even more explicit: `accepted_sink`
("accepted — not sent to hardware").

## Security

- Binds `127.0.0.1` **only** — never `0.0.0.0`.
- The printer LAN target (host:port) lives **only** in this bridge's local
  flags/config. The app and the server never learn the printer IP (this mirrors
  `get_device_printer_assignments`, which deliberately omits `connection_config`).
- No secrets. The examples/tests use RFC-5737 documentation IPs (`192.0.2.x`).

## Run

```sh
# Show all options and exit (does NOT start the server):
dart run print_bridge --help

# Demo SINK mode (no printer needed) — accepts jobs, does NOT reach hardware:
dart run print_bridge --demo            # (same as no args)

# Forward to ONE network RAW 9100 printer:
dart run print_bridge --target 192.0.2.10:9100

# Named / multiple printers:
dart run print_bridge --target receipt=192.0.2.10:9100 --target kitchen=192.0.2.20:9100

# From a JSON config (see bridge.config.example.json):
dart run print_bridge --config bridge.config.example.json --port 8787
```

**Stop it:** press **Ctrl+C** — the bridge closes the server and exits cleanly.

Flags:

| Flag | Meaning |
|---|---|
| `-h`, `--help` | Print usage and exit 0 (no server). |
| `--demo`, `--sink` | Explicit demo sink (default when no `--target`). Prints nothing. Cannot be combined with `--target`. |
| `--target host:port` | A network printer; named by `--printer-name` (default `default`). |
| `--target name=host:port` | A named network printer (repeatable). |
| `--printer-name <name>` | Name for an unnamed `--target`. |
| `--host <addr>` | Loopback bind address (default `127.0.0.1`). **Local-only**: `127.0.0.1` / `localhost` / `::1` only. |
| `--port <n>` | Bind port (default `8787`). |
| `--config <path.json>` | Load targets/port from JSON. |
| `--max-bytes <n>` | Reject payloads larger than n bytes (default `1048576`). |

An unknown flag (or a non-loopback `--host`) fails loudly with exit `64` and does
**not** start a mis-configured server.

The startup banner states the mode (DEMO SINK vs TCP), the loopback URL, the
configured printers, the exact `--dart-define` to point the POS/KDS at it, and —
in sink mode — a warning that nothing prints.

## HTTP API

### `GET /health`
```json
{ "ok": true, "mode": "sink" | "tcp", "printers": ["receipt", "kitchen"] }
```

### `POST /print`
Request:
```json
{ "format": "escpos", "role": "receipt", "payloadBase64": "<base64 ESC/POS>" }
```
Responses:
```json
{ "ok": true, "status": "sent", "mode": "tcp" }            // forwarded to printer
{ "ok": true, "status": "accepted_sink", "mode": "sink" }  // demo sink — NOT hardware
{ "ok": false, "error": "...", "category": "unreachable" } // connection refused/timeout
```
`category` ∈ `unreachable | unsupported | paper_out | cover_open | unknown`.

CORS: permissive for local origins; `OPTIONS` preflight answered.

## App wiring

The apps are OFF by default (no physical print path — jobs stay `prepared`).
Turn the bridge on at build/run time with a **loopback** URL:

```sh
flutter run -d chrome --dart-define=RESTOFLOW_PRINT_BRIDGE_URL=http://127.0.0.1:8787
```

The app's client enforces loopback (`assertLoopbackBridgeUrl`); a non-loopback
URL is rejected and the bridge stays dormant.

## Test

```sh
dart pub get
dart test
dart analyze
```
