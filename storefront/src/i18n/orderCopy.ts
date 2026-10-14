import type { OrderMessages } from './orders';
import type { OrderSnapshot, WebOrderErrorCode, WebOrderStatus } from '@/orders/contract';

export function orderStatusCopy(status: WebOrderStatus, m: OrderMessages) {
  return { title: m[status], body: m[`${status}Body`] };
}
export function orderErrorCopy(error: WebOrderErrorCode | null, m: OrderMessages): string {
  switch (error) {
    case 'ordering_unavailable': return m.orderingUnavailable;
    case 'item_unavailable': case 'modifier_selection_invalid': case 'menu_unavailable': return m.menuChanged;
    case 'invalid_request': case 'payload_too_large': return m.invalid;
    case 'rate_limited': case 'capacity_reached': return m.rateLimited;
    case 'storage_unavailable': return m.recoveryUnavailable;
    case 'configuration_invalid': case 'crypto_unavailable': return m.unsupported;
    case 'recovery_expired': case 'recovery_invalid': return m.noRecovery;
    default: return m.serviceUnavailable;
  }
}
export function orderSnapshotCopy(snapshot: OrderSnapshot, m: OrderMessages): string | null {
  switch (snapshot.phase) {
    case 'submitting': case 'reconciling': return m.checking;
    case 'unknown': return m.unknown;
    case 'not_found': return snapshot.canRetry ? m.notFound : m.noRecovery;
    case 'unavailable': return m.unavailable;
    case 'failure': return orderErrorCopy(snapshot.error, m);
    default: return null;
  }
}
