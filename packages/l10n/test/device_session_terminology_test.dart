import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() {
  test(
    'Hebrew device session copy uses the existing revoke terminology',
    () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('he'));
      expect(l10n.adminRevokeConfirm, contains('ההפעלות'));
      expect(l10n.adminNewCodeForDeviceConfirm, contains('ההפעלות'));
      expect(l10n.adminSessionExpired, 'תוקף ההפעלה פג');
      expect(l10n.adminNewCodeForDevice, 'קוד חדש למכשיר הזה');
    },
  );
}
