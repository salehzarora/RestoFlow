import type { CartState } from '@/source/types';
import type { WebOrder } from './contract';
import { invalid, normalizeWebOrder } from './validation';
import { normalizeCheckoutPhone } from './customer';

/** Each cart addition stays its own line; repeated selected IDs encode option quantity. */
export function orderFromCart(cart: CartState, customer: { readonly name: string; readonly phone: string }, notes = ''): WebOrder {
  if (!cart || !Array.isArray(cart.lines)) invalid();
  const phone = normalizeCheckoutPhone(customer?.phone);
  if (phone === null) invalid();
  const items = cart.lines.map((line) => {
    if (!line || !line.selections || typeof line.selections !== 'object' || Array.isArray(line.selections)) invalid();
    const quantities = new Map<string, number>();
    for (const selected of Object.values(line.selections)) {
      // The cart repeats IDs for quantity: 20 distinct options may each have 20 units.
      if (!Array.isArray(selected) || selected.length > 400) invalid();
      for (const id of selected) {
        if (typeof id !== 'string') invalid();
        const canonical = id.toLowerCase();
        quantities.set(canonical, (quantities.get(canonical) ?? 0) + 1);
      }
    }
    return { menu_item_id: line.itemId, quantity: line.qty, modifiers: [...quantities].map(([modifier_option_id, quantity]) => ({ modifier_option_id, quantity })), notes: line.note };
  });
  // Keep the editable draft untouched; freeze only the canonical outgoing copy.
  return normalizeWebOrder({ order_type: 'takeaway', customer: { ...customer, phone }, items, notes });
}
