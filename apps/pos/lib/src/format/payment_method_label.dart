import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/payment.dart';
import 'tax_math.dart';

/// The localized display label for a [PaymentMethod] (RF-117). Used on the tender
/// selector, the receipt, and the print preview so the tender reads the same
/// everywhere. Money-free — this is chrome, not an amount.
String paymentMethodLabel(AppLocalizations l10n, PaymentMethod method) =>
    switch (method) {
      PaymentMethod.cash => l10n.posPaymentMethodCash,
      PaymentMethod.card => l10n.posPaymentMethodCard,
      PaymentMethod.bit => l10n.posPaymentMethodBit,
      PaymentMethod.externalTender => l10n.posPaymentMethodExternal,
    };

/// The tax line label with the rate, e.g. `"Tax (17%)"` (RF-117). The localized
/// "Tax" word plus a formatted percent built from the integer basis-point rate
/// (no float). Built into a String value (never an inline widget string literal)
/// so it stays localized and clear of the no-hardcoded-strings guard.
String taxLineLabel(AppLocalizations l10n, int rateBp) =>
    '${l10n.posTaxLabel} (${formatRateBpPercent(rateBp)})';
