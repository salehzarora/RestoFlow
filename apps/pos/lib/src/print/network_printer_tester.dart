/// ANDROID-004: the network "Test print" seam moved into the shared
/// `restoflow_native_printing` package (reused by POS + KDS). This re-export
/// keeps the POS's historical import path + names resolving unchanged. The
/// tester now takes a [NetworkPrinterConfig] (= `PosNetworkPrinterConfig`).
export 'package:restoflow_native_printing/restoflow_native_printing.dart'
    show
        DefaultNetworkPrinterTester,
        NetworkPrinterTester,
        networkPrinterTesterProvider;
