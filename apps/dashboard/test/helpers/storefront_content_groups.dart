import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Open or close through the same visible header an owner uses. Existing
/// workflow tests can reach their controls without rebuilding the editor.
Future<void> setContentGroup(
  WidgetTester tester,
  String name, {
  bool expanded = true,
}) async {
  final group = find.byKey(Key('content-group-$name'));
  final header = find
      .descendant(of: group, matching: find.byType(ListTile))
      .first;
  if (ExpansibleController.of(tester.element(header)).isExpanded == expanded)
    return;
  await tester.ensureVisible(header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}
