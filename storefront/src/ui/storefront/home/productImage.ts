import type { MenuItem } from '@/source/types';

/** c4 responsive copies of one selected input, never encoded from each other. */
export function carouselImageSources(item: MenuItem, selected: boolean) {
  const variants = item.imageVariants;
  if (!variants?.length) return {};
  const image = variants[0];
  const ratio = image.width / image.height;
  const scale = selected ? 1 : .57;
  // object-fit:contain is height-limited for portraits. Requesting the full
  // button width would unnecessarily download the large copy on mobile.
  const number = (value: number) => Math.ceil(value * 100) / 100;
  const px = (height: number) => `${number(height * ratio * scale)}px`;
  // Match the shipped page gutters and the mobile stage's -10px margins:
  // mobile stage = viewport - 16px; desktop carousel <= min(viewport - 80px, 820px).
  const mobileWidth = `calc(${number(74 * scale)}vw - ${number(11.84 * scale)}px)`;
  const desktopWidth = `calc(${number(69 * scale)}vw - ${number(55.2 * scale)}px)`;
  return {
    srcSet: variants.map(v => `${v.url} ${v.width}w`).join(', '),
    sizes: `(max-width:365px) min(${mobileWidth}, ${px(210)}), (max-width:650px) min(${mobileWidth}, ${px(240)}), min(${desktopWidth}, ${number(565.8 * scale)}px, ${px(336)})`,
  };
}
