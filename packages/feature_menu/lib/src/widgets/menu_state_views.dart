import 'package:flutter/material.dart';

/// A centered loading spinner (RF-111). Note: an infinite spinner — widget tests
/// should `pump()` once, never `pumpAndSettle()`, while it is shown. The rich
/// empty/error/no-results state lives in `MenuStateView` (menu_components.dart).
class MenuLoadingView extends StatelessWidget {
  const MenuLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
