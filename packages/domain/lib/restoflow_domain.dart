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
library;

export 'src/entity.dart';
