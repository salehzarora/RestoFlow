/// DASHBOARD-OWNER-ANALYTICS-F0.5 — the ONE localized payment-method label.
///
/// Three copies of this mapping existed, and they had diverged in the way that
/// matters:
///
///   * `order_detail_sheet.dart` and `order_preview_builders.dart` each held a
///     PRIVATE, complete cash/card/bit/external mapper — identical to each
///     other, invisible to everyone else;
///   * the Overview payment summary and the payment-mix donut each held a
///     CASH-ONLY version (`m == 'cash' ? … : m`), so a card, Bit or external
///     tender rendered its raw wire token straight into the owner's dashboard.
///
/// The owner therefore saw "Card" inside an order sheet and the bare string
/// `card` on the Overview, for the same tender, in the same app. That is not a
/// styling inconsistency — it is a wire token leaking into a financial surface,
/// and it gets worse the moment Phase A widens the payment filters to card /
/// bit / external and those tokens start appearing in more places.
///
/// This module is deliberately tiny and presentation-only. It changes no data
/// semantics: the wire token remains the identity everywhere, and only its
/// DISPLAY is resolved here. It reuses the existing `posPaymentMethod*` keys,
/// which already ship in en/ar/he, so no new localization is required.
library;

import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Localizes a payment-method wire token (`cash` / `card` / `bit` /
/// `external`).
///
/// An UNKNOWN token falls back to the raw string rather than throwing or
/// rendering an empty cell. That is deliberate: a new server-side method must
/// degrade to something an owner can still read and report, not vanish from a
/// money breakdown whose parts must sum to the whole. The fallback is the
/// signal that a localization is missing — it should never be the normal path
/// for the four known methods.
String paymentMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'cash' => l10n.posPaymentMethodCash,
      'card' => l10n.posPaymentMethodCard,
      'bit' => l10n.posPaymentMethodBit,
      'external' => l10n.posPaymentMethodExternal,
      _ => method,
    };

/// The payment-method wire tokens the platform actually persists, in the order
/// analytics surfaces should present them.
///
/// Exposed so a chart legend, a filter list and a breakdown table cannot drift
/// into three different orderings or, worse, three different ideas of which
/// methods exist.
const List<String> kPaymentMethodWireTokens = <String>[
  'cash',
  'card',
  'bit',
  'external',
];

/// True when [method] is a token this app knows how to localize.
///
/// Useful for asserting in tests that a breakdown returned by the server is
/// fully presentable, without hard-coding the list at each call site.
bool isKnownPaymentMethod(String method) =>
    kPaymentMethodWireTokens.contains(method);
