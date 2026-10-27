import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_cursor_store.dart';

/// Presentation preferences ONLY. Never writes the spool, server, print ACK,
/// reserved reviewed_at column or any operational eligibility/hold state.
class PrintNoticeReviewStore {
  PrintNoticeReviewStore({SharedPreferencesAsync Function()? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync.new;

  final SharedPreferencesAsync Function() _preferences;

  String _key(PosSyncScope scope, String fingerprint) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const FormatException('invalid_print_notice_fingerprint');
    }
    final scopeHash = sha256.convert(
      utf8.encode(
        jsonEncode([
          scope.organizationId,
          scope.restaurantId,
          scope.branchId,
          scope.deviceId,
        ]),
      ),
    );
    return 'restoflow.pos.print_notice_review.v1.$scopeHash.$fingerprint';
  }

  Future<bool> isReviewed(PosSyncScope scope, String fingerprint) async {
    // A targeted backing read, independent of the legacy global preference
    // cache used by operational stores. Never reload/clear that shared cache.
    return await _preferences().getBool(_key(scope, fingerprint)) == true;
  }

  Future<bool> review(
    PosSyncScope scope,
    String fingerprint, {
    required bool Function() isCurrent,
  }) async {
    final prefs = _preferences();
    if (!isCurrent()) return false;
    final key = _key(scope, fingerprint);
    await prefs.setBool(key, true);
    final readback = await prefs.getBool(key);
    // A late completion may have saved the OLD scope's exact preference. It
    // never applies to a new identity/scope or authorizes any print operation.
    return isCurrent() && readback == true;
  }
}
