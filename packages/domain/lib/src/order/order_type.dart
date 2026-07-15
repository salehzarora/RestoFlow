/// Minimal order-type discriminator (RF-032). RESTAURANT-OPERATIONS-V1-001
/// (review B3): the order LIFECYCLE is shared — both types go `ready -> served
/// -> completed` (takeaway's `served` is DISPLAYED as "Picked up"; no
/// persisted `picked_up` state). The type gates SERVICE semantics instead:
/// dine-in requires a table, takeaway forbids one, and UI wording forks on it.
///
/// RF-032 only CONSUMES this value (injected at submit). Order-type selection,
/// table assignment, and the `tables` entity are owned by RF-035.
library;

enum OrderType { dineIn, takeaway }
