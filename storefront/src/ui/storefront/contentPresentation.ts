/** Closed presentation choices only; no menu, cart or order authority. */
import type { CardLayout, CardMode, Category, HeroFormat, MenuItem } from '@/source/types';

export const productImageClass = (item: Pick<MenuItem, 'imageFit'>, className: string): string =>
  item.imageFit === 'whole-image' ? className : '';
export const productFrameClass = productImageClass;
export const productCardClass = (item: Pick<MenuItem, 'cardLayout'>, className: string): string =>
  item.cardLayout === 'cutout' ? className : '';

/** Category owns an ordinary section; aggregate results require ALL cutouts. */
export function sectionLayout(mode: CardMode, items: readonly MenuItem[], category?: Category): 'list' | CardLayout {
  if (mode === 'list') return 'list';
  if (category !== undefined) return category.cardLayout ?? 'standard';
  return items.length > 0 && items.every(item => item.cardLayout === 'cutout') ? 'cutout' : 'standard';
}
export const sectionGridClass = (layout: 'list' | CardLayout, className: string): string =>
  layout === 'cutout' ? className : '';

export interface HeadlinePart { readonly text: string; readonly highlight: boolean; readonly breakBefore: boolean }
/** Validated scalar offsets; leave every saved space/mark/symbol untouched. */
export function headlineParts(text: string, format: HeroFormat | null | undefined): readonly HeadlinePart[] {
  if (format == null) return [{ text, highlight: false, breakBefore: false }];
  if (format.text !== text) throw new Error('invalid Hero format binding');
  const cp = Array.from(text);
  const offsets = [0, cp.length, format.highlight?.start, format.highlight?.end, format.break_before]
    .filter((n): n is number => n !== undefined && n !== null);
  if (offsets.some(n => !Number.isInteger(n) || n < 0 || n > cp.length)) throw new Error('invalid Hero scalar offset');
  const boundaries = [...new Set(offsets)].sort((a, b) => a - b);
  return boundaries.slice(0, -1).map((start, index) => ({
    text: cp.slice(start, boundaries[index + 1]).join(''),
    highlight: format.highlight !== null && start >= format.highlight.start && start < format.highlight.end,
    breakBefore: start === format.break_before,
  }));
}
