/** Menu presentation. Delegated product opening belongs to StorefrontRuntime. */
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { CardMode, Category, MenuItem } from '@/source/types';
import { PlusIcon, ChevronIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Price } from './HomeParts';
import styles from './home.module.css';

function Media({ item, m, rankLabel }: { item: MenuItem; m: StorefrontMessages; rankLabel?: string }) {
  const badge = item.soldOut ? m.soldOut : item.featured ? m.chefPick : item.badge === 'new' ? m.badgeNew : item.badge === 'deal' ? m.badgeDeal : null;
  return <div className={styles.cardMediaGrid}>
    {item.image === null ? <span className={styles.cardNoImage} aria-hidden="true">{item.name.slice(0, 1)}</span> : (
      /* eslint-disable-next-line @next/next/no-img-element */
      <img className={styles.cardImg} src={item.image} alt="" width={600} height={600} loading="lazy" decoding="async" />
    )}
    {rankLabel ? <span className={styles.badge} data-sf-badge="popularity">{rankLabel}</span> : null}
    {badge ? <span className={`${styles.badge} ${item.soldOut ? styles.badgeSoldOut : ''}`} data-sf-badge="item">{badge}</span> : null}
    {!item.soldOut && item.image ? <span className={styles.cardArrow} aria-hidden="true"><ChevronIcon /></span> : null}
  </div>;
}
function Card({ item, m, row = false, rankLabel }: { item: MenuItem; m: StorefrontMessages; row?: boolean; rankLabel?: string }) {
  return <div className={`${row ? styles.row : styles.card} ${item.soldOut ? styles.cardSoldOut : ''}`} role="button" tabIndex={item.soldOut ? -1 : 0} aria-disabled={item.soldOut ? 'true' : undefined} data-sf-item={item.id}>
    <Media item={item} m={m} rankLabel={rankLabel} />
    <div className={styles.cardBody}><div className={styles.cardMain}><p className={styles.cardName}><TenantText>{item.name}</TenantText></p><Price minor={item.priceMinor} from={item.hasOptions ? m.from : undefined} /></div><div className={styles.cardBottom}><p className={styles.cardDesc}><TenantText>{item.description}</TenantText></p>{item.soldOut ? null : <span className={styles.addCircle} role="img" aria-label={`${m.addShort}: ${item.name}`}><PlusIcon /></span>}</div></div>
  </div>;
}
export function GridCard({ item, m }: { item: MenuItem; m: StorefrontMessages }) { return <Card item={item} m={m} />; }
export function FeaturedCard({ item, m }: { item: MenuItem; m: StorefrontMessages }) { return <Card item={item} m={m} />; }
export function ListRow({ item, m }: { item: MenuItem; m: StorefrontMessages }) { return <Card item={item} m={m} row />; }
export function PopularCard({ item, m, rankLabel }: { item: MenuItem; m: StorefrontMessages; rankLabel: string }) { return <Card item={item} m={m} rankLabel={rankLabel} />; }
/** Manager-selected picks only; no sales ranking or inferred tag authority. */
export function PopularSection({ items, m }: { items: readonly MenuItem[]; m: StorefrontMessages; ready?: boolean; menuId?: string }) {
  const shown = items.filter((i) => i.featured && !i.soldOut);
  return shown.length ? <section className={styles.section} data-sf-module="popular"><h2>{m.chefPicks}</h2><div className={styles.popularGrid}>{shown.map(item => <GridCard key={item.id} item={item} m={m} />)}</div></section> : null;
}
export function MenuSection({ category, items, cardMode, m }: { category: Category; items: readonly MenuItem[]; cardMode: CardMode; m: StorefrontMessages }) {
  if (items.length === 0) return null;
  return <section className={styles.section} id={`sf-cat-${category.id}`} aria-labelledby={`sf-cat-title-${category.id}`} data-sf-module="sections">
    <div className={styles.sectionHead}><h3 id={`sf-cat-title-${category.id}`}><TenantText>{category.name}</TenantText></h3>{category.blurb ? <p className={styles.sectionBlurb}><TenantText>{category.blurb}</TenantText></p> : null}<span>{items.length === 1 ? m.item : fill(m.items, {n:String(items.length)})}</span></div>
    <div className={cardMode === 'grid' ? styles.gridWrap : styles.listWrap}>{items.map(item => cardMode === 'grid' ? <GridCard key={item.id} item={item} m={m} /> : <ListRow key={item.id} item={item} m={m} />)}</div>
  </section>;
}
export function rankLabel(m: StorefrontMessages, n: number): string { return fill(m.rankN, {n:String(n)}); }
