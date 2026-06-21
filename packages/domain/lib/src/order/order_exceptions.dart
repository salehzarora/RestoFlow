/// Domain exceptions for the local order state machines (RF-032).
///
/// Messages carry only domain values (states, short fixed text) — never
/// secrets or unrelated internal data. Pure Dart.
library;

import 'order_item_status.dart';
import 'order_status.dart';

/// Base type for all order/order-item state failures.
abstract class OrderStateException implements Exception {
  const OrderStateException(this.message);

  /// A short, safe description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// An order transition not present in the allowed table (STATE_MACHINES §1).
class IllegalOrderTransitionException extends OrderStateException {
  IllegalOrderTransitionException(this.from, this.to)
    : super('illegal order transition: ${from.name} -> ${to.name}');

  final OrderStatus from;
  final OrderStatus to;
}

/// An order-item transition not present in the allowed table (STATE_MACHINES §2).
class IllegalOrderItemTransitionException extends OrderStateException {
  IllegalOrderItemTransitionException(this.from, this.to)
    : super('illegal order item transition: ${from.name} -> ${to.name}');

  final OrderItemStatus from;
  final OrderItemStatus to;
}

/// A reason-requiring action (cancel/void) was attempted without a reason.
class MissingReasonException extends OrderStateException {
  const MissingReasonException([
    super.message = 'a non-empty reason is required',
  ]);
}

/// A void was attempted without an authorization that permits voiding.
/// (RF-032 placeholder only; real authorization is RF-050/RF-053.)
class UnauthorizedVoidException extends OrderStateException {
  const UnauthorizedVoidException([
    super.message = 'void requires an authorization that permits voiding',
  ]);
}

/// Cancel was attempted once production had started (an item past `queued`).
class CancelNotAllowedException extends OrderStateException {
  const CancelNotAllowedException(super.message);
}

/// Cancel/void was blocked because the order has a completed payment (D-024;
/// refunds are DEFERRED). The presence of a completed payment is injected.
class CompletedPaymentBlockException extends OrderStateException {
  const CompletedPaymentBlockException([
    super.message =
        'a completed payment blocks cancel/void in MVP (refunds deferred)',
  ]);
}

/// Submission was attempted from an empty cart (needs >= 1 item).
class EmptyOrderException extends OrderStateException {
  const EmptyOrderException([
    super.message = 'cannot submit an order with no items',
  ]);
}

/// Completion was attempted without the injected payment-settled precondition.
/// (RF-032 has no payment model; the real gate is enforced server-side, D-025.)
class PaymentNotSettledException extends OrderStateException {
  const PaymentNotSettledException([
    super.message = 'completion requires a settled payment',
  ]);
}
