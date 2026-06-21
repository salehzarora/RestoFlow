/// RestoFlow domain package - entity & value-object foundations.
///
/// Per docs/ARCHITECTURE.md section 3 this package will own entities, value
/// objects, the PROPOSED state enumerations (DECISION D-018), and pure domain
/// rules. RF-011 provides only a neutral base abstraction; concrete entities
/// and state enums land in later tickets (orgs/restaurants/branches in RF-014,
/// menu in RF-030, order/payment state machines in RF-032).
///
/// MONEY: the integer minor-unit money TYPE is owned by `packages/money`
/// (ticket RF-036), NOT this package (DECISION D-007; ARCHITECTURE section 3).
/// Domain entities will hold money-typed fields backed by that package.
///
/// RF-031 adds the in-memory POS cart / draft-order model (`src/cart/`): a
/// `Cart` aggregate of `CartLine`s with immutable price snapshots (D-008) and
/// integer minor-unit totals (D-007). It is not persisted, submitted, or synced.
library;

export 'src/cart/cart.dart';
export 'src/cart/cart_exceptions.dart';
export 'src/cart/cart_line.dart';
export 'src/cart/cart_snapshots.dart';
export 'src/entity.dart';
