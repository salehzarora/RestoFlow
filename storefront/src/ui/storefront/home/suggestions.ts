/** Suggestions use only the currently served menu, never names or inferred ranks.
 * Search does not change the selected category. No fallback crosses categories. */
import type { MenuItem } from '@/source/types';

export function suggestionPool(items: readonly MenuItem[], categoryId: string, managerPicks: boolean): readonly MenuItem[] {
  return items.filter(item => !item.soldOut && (managerPicks ? item.featured : item.categoryId === categoryId));
}

/** A sampled item is presentation only; StorefrontRuntime still validates it. */
export function chooseSuggestion(pool: readonly MenuItem[], sample: number): MenuItem | null {
  if (!Number.isFinite(sample) || sample < 0 || sample >= 1) return null;
  return pool[Math.floor(sample * pool.length)] ?? null;
}
