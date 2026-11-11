/** Menu presentation. Delegated product opening belongs to StorefrontRuntime. */
import { type StorefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import type { CardMode, Category, MenuItem } from '@/source/types';
import { TenantText } from '../TenantText';
import { GridCard } from './GridCard';
import { ProductCarousel } from './ProductCarousel';
import { sectionGridClass, sectionLayout } from '../contentPresentation';
import contentStyles from '../storefront.module.css';
import styles from './home.module.css';

export { GridCard } from './GridCard';

/** Manager-selected picks only; no sales ranking or inferred tag authority. */
export function PopularSection({ items, m }: { items: readonly MenuItem[]; m: StorefrontMessages; ready?: boolean; menuId?: string }) {
  const shown = items.filter((i) => i.featured && !i.soldOut);
  return shown.length ? <section className={styles.section} data-sf-module="popular"><h2>{m.chefPicks}</h2><div className={`${styles.popularGrid} ${sectionGridClass(sectionLayout('grid', shown), contentStyles.cutoutGrid)}`}>{shown.map(item => <GridCard key={item.id} item={item} m={m} />)}</div></section> : null;
}
export function MenuSection({ category, items, m, locale }: { category: Category; items: readonly MenuItem[]; cardMode: CardMode; m: StorefrontMessages; locale: Locale }) {
  return <section className={styles.section} id={`sf-cat-${category.id}`} aria-labelledby={`sf-cat-title-${category.id}`} data-sf-module="sections">
    <div className={styles.sectionHead}><h3 id={`sf-cat-title-${category.id}`} tabIndex={-1}><span className={styles.categoryTitle}><svg viewBox="0 0 24 24" aria-hidden="true"><path d={category.iconPath} /></svg><TenantText>{category.heading ?? category.name}</TenantText></span></h3>{category.blurb ? <p className={styles.sectionBlurb}><TenantText>{category.blurb}</TenantText></p> : null}</div>
    {items.length ? <ProductCarousel items={items} m={m} locale={locale} label={category.name} /> : <p className={styles.sectionBlurb}>{m.emptyMenu}</p>}
  </section>;
}
