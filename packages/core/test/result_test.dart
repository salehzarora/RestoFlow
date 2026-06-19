import 'package:restoflow_core/restoflow_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Success reports success and folds to the success branch', () {
      const Result<int, String> r = Success(42);
      expect(r.isSuccess, isTrue);
      expect(r.isFailure, isFalse);
      expect(r.fold((v) => 'v:$v', (f) => 'f:$f'), 'v:42');
    });

    test('Failure reports failure and folds to the failure branch', () {
      const Result<int, String> r = Failure('nope');
      expect(r.isSuccess, isFalse);
      expect(r.isFailure, isTrue);
      expect(r.fold((v) => 'v:$v', (f) => 'f:$f'), 'f:nope');
    });
  });

  test('AppEnvironment exposes exactly dev/staging/prod', () {
    expect(AppEnvironment.values, hasLength(3));
    expect(AppEnvironment.values, contains(AppEnvironment.dev));
    expect(AppEnvironment.values, contains(AppEnvironment.staging));
    expect(AppEnvironment.values, contains(AppEnvironment.prod));
  });
}
