/// RestoFlow currency package (OPS-043 Phase 1) — the ONE shared ISO-4217
/// catalog, display formatter, and major->minor parser.
///
/// Before this package there were FIVE independent implementations: the POS
/// `MoneyFormatter`, a copy of it in the dashboard, `ReceiptMoneyFormat` in
/// packages/printing, `feature_menu`'s `minor_money`, and the POS
/// `parseCashToMinor` — with three different exponent tables that could (and
/// did) drift. Two of them assumed two decimals everywhere, which for JPY/KWD
/// corrupts real amounts by 100x/10x rather than merely mis-displaying them.
///
/// D2 (OPS-043) fixes the order of work: this module lands FIRST, every
/// duplicated site is replaced against it SECOND (Phase 2), and only THEN does
/// the full ISO list become selectable — see [kCurrencySelectorScope], the
/// in-code gate.
///
/// Pure Dart: no Flutter, no `dart:ui`, no `intl`, no IO. It runs in the CI
/// `dart test` lane alongside core/domain/data_local/money/auth_identity.
///
/// Money stays integer minor units end to end (DECISION D-007). Nothing here
/// rounds — a value that does not fit the currency's exponent is rejected.
library;

export 'src/currency_catalog.dart';
export 'src/currency_format.dart';
export 'src/currency_selection.dart';
