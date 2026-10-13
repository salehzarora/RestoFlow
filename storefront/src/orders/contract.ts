/** Private pickup checkout contract. Customer fields and capability stay out of URLs/logs. */
export const WEB_ORDER_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
export const WEB_ORDER_ENDPOINT = `${WEB_ORDER_ORIGIN}/functions/v1/web-order-submit`;
export const RECOVERY_MAX_AGE_MS = 24 * 60 * 60 * 1000;
export const MAX_BODY_BYTES = 32 * 1024;

export interface WebOrderModifier {
  readonly modifier_option_id: string;
  readonly quantity: number;
}
export interface WebOrderItem {
  readonly menu_item_id: string;
  readonly quantity: number;
  readonly modifiers: readonly WebOrderModifier[];
  readonly notes?: string;
}
export interface WebOrder {
  readonly order_type: 'takeaway';
  readonly customer: { readonly name: string; readonly phone: string };
  readonly items: readonly WebOrderItem[];
  readonly notes: string;
}
export interface OrderIdentity {
  readonly slug: string;
  readonly request_id: string;
  readonly status_token: string;
}
export interface RecoveryRecord extends OrderIdentity {
  readonly created_at: number;
  readonly expires_at: number;
}
export type WebOrderStatus = 'pending' | 'accepted' | 'rejected' | 'expired';
/** These amounts are accepted only from a validated server response. */
export interface WebOrderTotals {
  readonly currency_code: 'ILS';
  readonly subtotal_minor: number;
  readonly tax_total_minor: number;
  readonly grand_total_minor: number;
}
export interface WebOrderResult {
  readonly ok: true;
  readonly request_id: string;
  readonly status: WebOrderStatus;
  readonly expires_at: string;
  readonly totals: WebOrderTotals;
  readonly replayed: boolean;
}
export type WebOrderErrorCode =
  | 'invalid_request' | 'not_found' | 'ordering_unavailable' | 'idempotency_conflict'
  | 'item_unavailable' | 'modifier_selection_invalid' | 'menu_unavailable'
  | 'rate_limited' | 'capacity_reached' | 'invalid_json' | 'payload_too_large'
  | 'unsupported_media_type' | 'origin_not_allowed' | 'invalid_preflight'
  | 'method_not_allowed' | 'submission_outcome_unknown' | 'status_unavailable'
  | 'service_unavailable' | 'storage_unavailable' | 'recovery_invalid'
  | 'recovery_expired' | 'configuration_invalid' | 'crypto_unavailable';

export type OrderOutcome =
  | { readonly kind: 'known'; readonly result: WebOrderResult }
  | { readonly kind: 'failure'; readonly error: WebOrderErrorCode }
  | { readonly kind: 'unknown'; readonly error: 'submission_outcome_unknown' }
  | { readonly kind: 'unavailable'; readonly error: 'status_unavailable' };

export interface OrderTransport {
  submit(identity: OrderIdentity, order: WebOrder): Promise<OrderOutcome>;
  status(identity: OrderIdentity): Promise<OrderOutcome>;
}
export interface RecoveryStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface OrderSnapshot {
  readonly phase: 'idle' | 'submitting' | 'reconciling' | 'unknown' | 'not_found' | 'failure' | 'status' | 'unavailable';
  readonly result: WebOrderResult | null;
  readonly error: WebOrderErrorCode | null;
  /** True only after status returned not_found and this tab still has the original body. */
  readonly canRetry: boolean;
  /** Reload recovery can read status; it never reconstructs a submission. */
  readonly recovered: boolean;
}
export interface OrderController {
  getSnapshot(): OrderSnapshot;
  subscribe(listener: () => void): () => void;
  recover(): Promise<OrderSnapshot>;
  submit(order: WebOrder): Promise<OrderSnapshot>;
  refresh(): Promise<OrderSnapshot>;
  retry(): Promise<OrderSnapshot>;
}
