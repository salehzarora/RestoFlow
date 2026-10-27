import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The actual pinned async plugin API with a synthetic per-key platform backend.
/// Any broad read, deletion or other preference operation fails the test.
final class PrintNoticeTestPreferences extends SharedPreferencesAsyncPlatform {
  final values = <String, Object>{};
  var writeAttempts = 0;
  bool dropWrites = false, throwWrites = false, throwReads = false;

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async {
    if (throwReads) throw StateError('synthetic_read_failure');
    return values[key] as bool?;
  }

  @override
  Future<void> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {
    writeAttempts++;
    if (throwWrites) throw StateError('synthetic_write_failure');
    if (!dropWrites) values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected_preference_operation');
}

PrintNoticeTestPreferences installPrintNoticePreferences() {
  final platform = PrintNoticeTestPreferences();
  SharedPreferencesAsyncPlatform.instance = platform;
  return platform;
}
