/// RestoFlow shared native on-device printing (ANDROID-004).
///
/// The reusable native (Wi-Fi RAW/TCP + Bluetooth Classic SPP) ESC/POS printing
/// layer shared by the POS and KDS Android apps: config models, a web-safe
/// Bluetooth connector behind a conditional import, device-local config
/// providers (seam-scoped per device + app namespace), test-print seams, a
/// transport resolver + honest send path, and a label-injected settings UI.
///
/// Money-free by construction: it only carries an already-built, render-neutral
/// [PrintDocument] to a transport and never computes or renders money.
library;

export 'src/bluetooth_printer.dart';
export 'src/native_print_target.dart';
export 'src/native_printer_settings.dart';
export 'src/native_printer_store.dart';
export 'src/printer_config.dart';
export 'src/printer_testers.dart';
