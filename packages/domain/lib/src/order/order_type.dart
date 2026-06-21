/// Minimal order-type discriminator consumed by the order state machine to
/// gate the `served` step (RF-032). Takeaway skips `served` (`ready ->
/// completed`); dine-in goes `ready -> served -> completed`.
///
/// RF-032 only CONSUMES this value (injected at submit). Order-type selection,
/// table assignment, and the `tables` entity are owned by RF-035.
library;

enum OrderType { dineIn, takeaway }
