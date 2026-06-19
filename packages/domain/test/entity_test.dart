import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:test/test.dart';

// A throwaway concrete entity used only to prove the package's public surface
// (the `Entity` marker) is exported and usable. Not a domain model.
class _SampleEntity implements Entity {
  const _SampleEntity(this.id);

  @override
  final String id;
}

void main() {
  test('Entity marker is exported and exposes a stable identity', () {
    const Entity e = _SampleEntity('org-123');
    expect(e.id, 'org-123');
  });
}
