import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/admin/supabase_settings_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// TIMEZONE-GLOBAL-001 — the real settings repo loads the global catalog from
/// `list_timezones` and surfaces the branch's CURRENT timezone from
/// `list_org_structure` (so the picker can show it). Fails soft to empty/null.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);

  final Object? Function(String fn, Map<String, dynamic> params) _handler;
  final List<String> calls = [];

  @override
  Future<Object?> invoke(String fn, Map<String, dynamic> params) async {
    calls.add(fn);
    return _handler(fn, params);
  }
}

SupabaseSettingsRepository _repo(_FakeTransport t) =>
    SupabaseSettingsRepository(
      transport: t,
      organizationId: 'org-1',
      restaurantId: 'rest-1',
      branchId: 'branch-1',
    );

void main() {
  test('loadTimezones maps list_timezones into canonical options', () async {
    final t = _FakeTransport(
      (fn, _) => fn == 'list_timezones'
          ? <String, dynamic>{
              'ok': true,
              'entity': 'timezones',
              'zones': <Map<String, dynamic>>[
                {'id': 'Asia/Jerusalem', 'offset_minutes': 180},
                {'id': 'Europe/London', 'offset_minutes': 60},
              ],
            }
          : null,
    );
    final zones = await _repo(t).loadTimezones();
    expect(t.calls, contains('list_timezones'));
    expect(zones.map((z) => z.id).toList(), [
      'Asia/Jerusalem',
      'Europe/London',
    ]);
    expect(zones.first.offsetMinutes, 180);
  });

  test('loadTimezones fails soft to empty on a rejected/failed RPC', () async {
    final t = _FakeTransport((_, _) => <String, dynamic>{'ok': false});
    expect(await _repo(t).loadTimezones(), isEmpty);
  });

  test('readPrefill surfaces the branch CURRENT timezone', () async {
    final t = _FakeTransport(
      (fn, _) => fn == 'list_org_structure'
          ? <String, dynamic>{
              'ok': true,
              'restaurants': <Map<String, dynamic>>[
                {
                  'id': 'rest-1',
                  'name': 'Rest 1',
                  'status': 'active',
                  'branches': <Map<String, dynamic>>[
                    {
                      'id': 'branch-1',
                      'name': 'Main',
                      'status': 'active',
                      'timezone': 'UTC',
                    },
                  ],
                },
              ],
            }
          : null,
    );
    final prefill = await _repo(t).readPrefill();
    expect(prefill, isNotNull);
    // The pilot symptom: the branch is on UTC — the picker must be able to SHOW it.
    expect(prefill!.branchTimezone, 'UTC');
    expect(prefill.branchName, 'Main');
  });

  test('readPrefill leaves branchTimezone null when unset', () async {
    final t = _FakeTransport(
      (fn, _) => fn == 'list_org_structure'
          ? <String, dynamic>{
              'ok': true,
              'restaurants': <Map<String, dynamic>>[
                {
                  'id': 'rest-1',
                  'name': 'Rest 1',
                  'branches': <Map<String, dynamic>>[
                    {'id': 'branch-1', 'name': 'Main'},
                  ],
                },
              ],
            }
          : null,
    );
    final prefill = await _repo(t).readPrefill();
    expect(prefill!.branchTimezone, isNull);
  });
}
