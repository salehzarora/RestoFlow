import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_admin/src/data/platform_admin_repository.dart';
import 'package:restoflow_admin/src/data/platform_admin_source.dart';

void main() {
  test('demo repository computes an overview from the demo dataset', () async {
    const repo = DemoPlatformAdminRepository();
    final overview = await repo.loadOverview();
    expect(overview.organizationCount, 3);
    expect(overview.branchCount, 6);
    expect(overview.activity, isNotEmpty);
  });

  test(
    'an injected dataset is used (empty platform -> empty overview)',
    () async {
      final repo = DemoPlatformAdminRepository(dataset: emptyPlatformDataset());
      final overview = await repo.loadOverview();
      expect(overview.isEmpty, isTrue);
      expect(overview.organizationCount, 0);
    },
  );

  test('a configured failure surfaces as a PlatformAdminException', () async {
    const repo = DemoPlatformAdminRepository(failureMessage: 'boom');
    expect(repo.loadOverview(), throwsA(isA<PlatformAdminException>()));
  });
}
