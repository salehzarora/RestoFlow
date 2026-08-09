import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/analytics/analytics_labels.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// DASHBOARD-OWNER-ANALYTICS-F0.5 — payment-method label honesty.
///
/// The defect being pinned: the Overview payment summary and the payment-mix
/// donut each localized ONLY cash, so `card`, `bit` and `external` rendered as
/// raw wire tokens on a financial surface — while the order sheet, two screens
/// away, localized all four correctly. These tests assert the four known tokens
/// never render as themselves in any supported language.
Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void main() {
  group('F0.5 paymentMethodLabel', () {
    test('every known token is localized — never the raw wire value', () async {
      for (final code in ['en', 'ar', 'he']) {
        final l10n = await _l10n(code);
        for (final token in kPaymentMethodWireTokens) {
          final label = paymentMethodLabel(l10n, token);
          expect(
            label,
            isNotEmpty,
            reason: '$code/$token produced an empty label',
          );
          expect(
            label,
            isNot(token),
            reason:
                '$code/$token leaked the raw wire token — this is exactly the '
                'Overview bug',
          );
        }
      }
    });

    test('the four persisted methods are the known set', () {
      expect(kPaymentMethodWireTokens, ['cash', 'card', 'bit', 'external']);
      for (final t in kPaymentMethodWireTokens) {
        expect(isKnownPaymentMethod(t), isTrue);
      }
      expect(isKnownPaymentMethod('cheque'), isFalse);
      expect(isKnownPaymentMethod(''), isFalse);
    });

    test(
      'an UNKNOWN token degrades to the raw value rather than vanishing',
      () async {
        final l10n = await _l10n('en');
        // Deliberate: a money breakdown whose parts must sum to the whole must
        // never silently drop a row. The raw value is the missing-localization
        // signal, not a normal path.
        expect(paymentMethodLabel(l10n, 'crypto'), 'crypto');
        expect(paymentMethodLabel(l10n, ''), '');
      },
    );

    test('en labels are the expected human words', () async {
      final l10n = await _l10n('en');
      expect(paymentMethodLabel(l10n, 'cash'), l10n.posPaymentMethodCash);
      expect(paymentMethodLabel(l10n, 'card'), l10n.posPaymentMethodCard);
      expect(paymentMethodLabel(l10n, 'bit'), l10n.posPaymentMethodBit);
      expect(
        paymentMethodLabel(l10n, 'external'),
        l10n.posPaymentMethodExternal,
      );
    });

    test('ar and he differ from en for at least one method, proving real '
        'translations rather than English fallbacks', () async {
      final en = await _l10n('en');
      for (final code in ['ar', 'he']) {
        final other = await _l10n(code);
        final differs = kPaymentMethodWireTokens.any(
          (t) => paymentMethodLabel(other, t) != paymentMethodLabel(en, t),
        );
        expect(
          differs,
          isTrue,
          reason: '$code appears to fall back to English for every method',
        );
      }
    });
  });
}
