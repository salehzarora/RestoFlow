import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

void main() {
  test(
    'platform setup and renewal guidance matches AR/HE/EN resources',
    () async {
      final directory = Directory('lib/l10n').existsSync()
          ? 'lib/l10n'
          : 'packages/l10n/lib/l10n';
      for (final locale in const ['ar', 'he', 'en']) {
        final resource =
            jsonDecode(File('$directory/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;
        final l10n = await AppLocalizations.delegate.load(Locale(locale));
        expect(l10n.storefrontPickupHelp, resource['storefrontPickupHelp']);
        expect(
          l10n.posBackgroundOrderAlertsSignIn,
          resource['posBackgroundOrderAlertsSignIn'],
        );
        expect(l10n.storefrontPickupHelp, isNotEmpty);
        expect(l10n.posBackgroundOrderAlertsSignIn, isNotEmpty);
      }
    },
  );
}
