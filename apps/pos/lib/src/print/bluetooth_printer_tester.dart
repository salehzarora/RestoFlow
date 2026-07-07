/// ANDROID-004: the Bluetooth "Test print" seam moved into the shared
/// `restoflow_native_printing` package (reused by POS + KDS). This re-export
/// keeps the POS's historical import path + names resolving unchanged. The
/// tester now takes a [BluetoothPrinterConfig] (= `PosBluetoothPrinterConfig`).
export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothPrinterTester,
        DefaultBluetoothPrinterTester,
        bluetoothPrinterTesterProvider;
