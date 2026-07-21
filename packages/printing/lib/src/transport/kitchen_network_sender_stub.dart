import 'kitchen_network_sender.dart';

/// Web/default branch: no socket connector exists — the kitchen sender
/// reports `unsupported` and NOTHING silently claims to print. No `dart:io`
/// import may ever appear here.
KitchenSocketConnector? platformKitchenSocketConnector() => null;
