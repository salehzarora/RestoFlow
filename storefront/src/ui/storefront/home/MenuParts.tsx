/** Menu presentation. Delegated product opening belongs to StorefrontRuntime. */
import { type StorefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import type { CardMode, Category, MenuItem } from '@/source/types';
import { PlusIcon, ChevronIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Price } from './HomeParts';
import { ProductCarousel } from './ProductCarousel';
import { productCardClass, productFrameClass, productImageClass, sectionGridClass, sectionLayout } from '../contentPresentation';
import contentStyles from '../storefront.module.css';
import styles from './home.module.css';

function Media({ item, m }: { item: MenuItem; m: StorefrontMessages }) {
  const badge = item.soldOut ? m.soldOut : item.featured ? m.chefPick : item.badge === 'new' ? m.badgeNew : item.badge === 'deal' ? m.badgeDeal : null;
  return <div className={`${styles.cardMediaGrid} ${productFrameClass(item, contentStyles.wholeFrame)}`} data-sf-image-fit={item.imageFit ?? 'fill'}>
    {item.image === null ? <span className={styles.cardNoImage} aria-hidden="true">{item.name.slice(0, 1)}</span> : (
      /* eslint-disable-next-line @next/next/no-img-element */
      <img className={`${styles.cardImg} ${productImageClass(item, contentStyles.wholeImage)}`} src={item.image} alt="" width={600} height={600} loading="lazy" decoding="async" />
    )}
    {badge ? <span className={`${styles.badge} ${item.soldOut ? styles.badgeSoldOut : ''}`} data-sf-badge="item">{badge}</span> : null}
    {!item.soldOut && item.image ? <span className={styles.cardArrow} aria-hidden="true"><ChevronIcon /></span> : null}
  </div>;
}
function Card({ item, m }: { item: MenuItem; m: StorefrontMessages }) {
  return <div className={`${styles.card} ${item.soldOut ? styles.cardSoldOut : ''} ${productCardClass(item, contentStyles.cutout)}`} data-sf-card-layout={item.cardLayout ?? 'standard'} role="button" tabIndex={item.soldOut ? -1 : 0} aria-disabled={item.soldOut ? 'true' : undefined} data-sf-item={item.id}>
    <Media item={item} m={m} />
    <div className={styles.cardBody}><div className={styles.cardMain}><p className={styles.cardName}><TenantText>{item.name}</TenantText></p><Price minor={item.priceMinor} from={item.hasOptions ? m.from : undefined} /></div><div className={styles.cardBottom}><p className={styles.cardDesc}><TenantText>{item.description}</TenantText></p>{item.soldOut ? null : <span className={styles.addCircle} role="img" aria-label={`${m.addShort}: ${item.name}`}><PlusIcon /></span>}</div></div>
  </div>;
}
export function GridCard({ item, m }: { item: MenuItem; m: StorefrontMessages }) { return <Card item={item} m={m} />; }
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
