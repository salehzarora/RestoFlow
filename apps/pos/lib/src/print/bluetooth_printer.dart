/// ANDROID-004: the Bluetooth Classic (SPP) stack moved into the shared
/// `restoflow_native_printing` package (reused by POS + KDS). This re-export
/// keeps the POS's historical import path + names resolving unchanged.
export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        BluetoothClassicPrintTransport,
        BluetoothDeviceInfo,
        BluetoothPairedResult,
        BluetoothPrinterConnector,
        BluetoothPrinterError,
        bluetoothPrinterConnectorProvider;
