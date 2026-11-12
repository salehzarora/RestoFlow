/** Existing card presentation, separate from the orbital menu renderer. */
import type { StorefrontMessages } from '@/i18n/storefront';
import type { MenuItem } from '@/source/types';
import { PlusIcon, ChevronIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Price } from './HomeParts';
import { productCardClass, productFrameClass, productImageClass } from '../contentPresentation';
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
