import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_settings_group.dart';

// Existing behavior cases enter groups through the same header as a user.
// Separate disclosure tests verify the initial folded state and focus isolation.
Future<void> openStorefrontSettingsGroups(WidgetTester tester) async {
  final groups = tester
      .widgetList<StorefrontSettingsGroup>(
        find.byType(StorefrontSettingsGroup, skipOffstage: false),
      )
      .toList();
  for (final group in groups) {
    if (group.key == null) continue;
    final container = find.byKey(group.key!, skipOffstage: false);
    if (container.evaluate().isEmpty) continue;
    final tile = find
        .descendant(
          of: container,
          matching: find.byType(ExpansionTile, skipOffstage: false),
        )
        .first;
    if (tester.widget<ExpansionTile>(tile).controller!.isExpanded) continue;
    final title = find
        .descendant(
          of: tile,
          matching: find.text(group.title, skipOffstage: false),
        )
        .first;
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
  }
}
