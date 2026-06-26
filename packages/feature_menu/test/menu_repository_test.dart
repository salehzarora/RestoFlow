import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

void main() {
  group('MenuManagementRepository', () {
    test('load delegates to the read source', () async {
      final store = buildDemoMenuStore();
      final repository = MenuManagementRepository(
        readSource: store,
        writer: store,
      );
      final snapshot = await repository.load(demoMenuScope);
      expect(snapshot.isEmpty, isFalse);
      expect(snapshot.visibleCategories(), isNotEmpty);
    });

    test(
      'a successful write delegates to the writer and is observable on reload',
      () async {
        final store = buildDemoMenuStore();
        final repository = MenuManagementRepository(
          readSource: store,
          writer: store,
        );

        final outcome = await repository.upsertCategory(
          scope: demoMenuScope,
          name: 'Specials',
        );
        expect(
          outcome.fold((v) => v.entity, (_) => null),
          MenuEntityType.category,
        );

        final snapshot = await repository.load(demoMenuScope);
        expect(
          snapshot.visibleCategories().any((c) => c.name == 'Specials'),
          isTrue,
        );
      },
    );

    test(
      'a denied writer surfaces the failure without changing data',
      () async {
        final readStore = buildDemoMenuStore();
        final repository = MenuManagementRepository(
          readSource: readStore,
          writer: buildDemoMenuStore(readOnly: true),
        );

        final outcome = await repository.upsertItem(
          scope: demoMenuScope,
          menuCategoryId: 'cat-hot',
          name: 'Mocha',
          basePriceMinor: 500,
          currencyCode: 'USD',
        );
        expect(
          outcome.fold((_) => null, (f) => f),
          isA<MenuPermissionDenied>(),
        );

        final snapshot = await repository.load(demoMenuScope);
        expect(
          snapshot.itemsForCategory('cat-hot').any((i) => i.name == 'Mocha'),
          isFalse,
        );
      },
    );
  });
}
