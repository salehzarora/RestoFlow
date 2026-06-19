/// Marker base for a domain **entity** - a domain object distinguished by a
/// stable identity rather than by its attribute values.
///
/// Neutral foundation only: it encodes no restaurant/POS rules. Concrete
/// entities (organization, restaurant, order, ...) implement this in later
/// tickets. The concrete identity type is chosen by subclasses (a UUID string
/// in the data layer per DECISION D-017).
abstract interface class Entity {
  /// The stable identity of this entity.
  Object get id;
}
