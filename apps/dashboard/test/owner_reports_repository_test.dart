import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/data/owner_report_source.dart';
import 'package:restoflow_dashboard/src/data/owner_reports_repository.dart';

void main() {
  test('demo repository computes a report from the demo dataset', () async {
    const repo = DemoOwnerReportsRepository();
    final report = await repo.loadReport();
    expect(report.orderCount, 7);
    expect(report.netSalesMinor, 62000);
    expect(report.recentOrders, isNotEmpty);
  });

  test('an injected dataset is used (empty day -> empty report)', () async {
    final repo = DemoOwnerReportsRepository(dataset: emptyOwnerReportDataset());
    final report = await repo.loadReport();
    expect(report.isEmpty, isTrue);
    expect(report.orderCount, 0);
  });

  test('a configured failure surfaces as an OwnerReportsException', () async {
    const repo = DemoOwnerReportsRepository(failureMessage: 'boom');
    expect(repo.loadReport(), throwsA(isA<OwnerReportsException>()));
  });
}
