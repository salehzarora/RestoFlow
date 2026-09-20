/**
 * Product cards, the popular rail and the per-category menu sections.
 *
 * Cards are rendered as DISABLED buttons in Phase B: the product sheet they
 * open is a later phase, so the affordance is honest about not being wired yet
 * rather than linking somewhere that does not exist. Sold-out cards are
 * `aria-disabled` and never tappable, which is the designed behaviour.
 */
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { CardMode, Category, MenuItem } from '@/source/types';
import { PlusIcon, ChevronIcon, FlameIcon } from '../icons';
import { Price } from './HomeParts';
import styles from './home.module.css';

function Media({
  item,
  shape,
  m,
  rank,
}: {
  item: MenuItem;
  shape: 'featured' | 'popular' | 'grid' | 'row';
  m: StorefrontMessages;
  rank?: number;
}) {
  const cls =
    shape === 'featured'
      ? styles.cardMediaFeatured
      : shape === 'popular'
        ? styles.cardMediaPopular
        : shape === 'grid'
          ? styles.cardMediaGrid
          : styles.rowMedia;
  const badgeText =
    item.badge === 'new' ? m.badgeNew : item.badge === 'deal' ? m.badgeDeal : null;

  return (
    <div className={cls}>
      {item.image === null ? (
        <span className={styles.cardNoImage} aria-hidden="true">
          {item.name.slice(0, 1)}
        </span>
      ) : (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img
          className={styles.cardImg}
          src={item.image}
          alt=""
          width={600}
          height={600}
          loading="lazy"
          decoding="async"
        />
      )}
      {item.soldOut ? (
        <span className={`${styles.badge} ${styles.badgeSoldOut}`}>{m.soldOut}</span>
      ) : badgeText === null ? null : (
        <span className={styles.badge}>{badgeText}</span>
      )}
      {rank === undefined ? null : (
        <span className={styles.rankBadge} aria-hidden="true">
          #{rank}
        </span>
      )}
    </div>
  );
}

function AddControl({ item, m, circle }: { item: MenuItem; m: StorefrontMessages; circle: boolean }) {
  if (item.soldOut) return null;
  const label = `${m.addShort}: ${item.name}`;
  return circle ? (
    <span className={styles.addCircle} role="img" aria-label={label}>
      <PlusIcon />
    </span>
  ) : (
    <span className={styles.addPill} role="img" aria-label={label}>
      {m.addShort}
    </span>
  );
}

function priceOf(item: MenuItem, m: StorefrontMessages) {
  return <Price minor={item.priceMinor} from={item.hasOptions ? m.from : undefined} />;
}

export function FeaturedCard({ item, m }: { item: MenuItem; m: StorefrontMessages }) {
  return (
    <div
      className={`${styles.card} ${item.soldOut ? styles.cardSoldOut : ''}`}
      aria-disabled={item.soldOut ? 'true' : undefined}
    >
      <Media item={item} shape="featured" m={m} />
      <div className={styles.cardBody}>
        <p className={styles.cardName} dir="auto">
          {item.name}
        </p>
        <p className={styles.cardDesc} dir="auto">
          {item.description}
        </p>
        <div className={styles.cardFoot}>
          {priceOf(item, m)}
          <AddControl item={item} m={m} circle={false} />
        </div>
      </div>
    </div>
  );
}

export function PopularCard({
  item,
  m,
  rank,
}: {
  item: MenuItem;
  m: StorefrontMessages;
  rank?: number;
}) {
  return (
    <div className={styles.card}>
      <Media item={item} shape="popular" m={m} rank={rank} />
      <div className={styles.cardBody}>
        <p className={`${styles.cardName} ${styles.cardNameSmall}`} dir="auto">
          {item.name}
        </p>
        <p className={styles.cardDesc} dir="auto">
          {item.description}
        </p>
        <div className={styles.cardFoot}>
          {priceOf(item, m)}
          <AddControl item={item} m={m} circle />
        </div>
      </div>
    </div>
  );
}

export function GridCard({ item, m }: { item: MenuItem; m: StorefrontMessages }) {
  return (
    <div
      className={`${styles.card} ${item.soldOut ? styles.cardSoldOut : ''}`}
      aria-disabled={item.soldOut ? 'true' : undefined}
    >
      <Media item={item} shape="grid" m={m} />
      <div className={styles.cardBody}>
        <p className={`${styles.cardName} ${styles.cardNameSmall}`} dir="auto">
          {item.name}
        </p>
        <div className={styles.cardFoot}>
          {priceOf(item, m)}
          <AddControl item={item} m={m} circle />
        </div>
      </div>
    </div>
  );
}

export function ListRow({ item, m }: { item: MenuItem; m: StorefrontMessages }) {
  return (
    <div
      className={`${styles.row} ${item.soldOut ? styles.cardSoldOut : ''}`}
      aria-disabled={item.soldOut ? 'true' : undefined}
    >
      <div className={styles.rowBody}>
        <p className={styles.cardName} dir="auto">
          {item.name}
        </p>
        <p className={styles.cardDesc} dir="auto">
          {item.description}
        </p>
        <div className={styles.cardFoot}>
          {priceOf(item, m)}
          <AddControl item={item} m={m} circle />
        </div>
      </div>
      <Media item={item} shape="row" m={m} />
    </div>
  );
}

/**
 * The popular rail. `ready` changes what the rail CLAIMS, not merely how it
 * looks: without it there is no ranking, no "#n" badge and no "most ordered"
 * heading, because no count exists to justify them.
 */
export function PopularSection({
  items,
  m,
  ready,
  menuId,
}: {
  items: readonly MenuItem[];
  m: StorefrontMessages;
  ready: boolean;
  menuId: string;
}) {
  // Sold-out items are excluded from the rail entirely.
  const shown = items.filter((i) => i.signature && !i.soldOut).slice(0, 4);
  if (shown.length === 0) return null;

  return (
    <section className={styles.section} aria-labelledby="sf-popular-title">
      <div className={styles.sectionHead}>
        <span className={styles.flameTile} aria-hidden="true">
          <FlameIcon />
        </span>
        <span className={styles.sectionTitle}>
          <h2 className={styles.sectionTitle} id="sf-popular-title">
            {ready ? m.mostOrdered : m.chefPicks}
          </h2>
          {ready ? <span className={styles.sectionSub}>{m.last30}</span> : null}
        </span>
        <a className={styles.seeAll} href={`#${menuId}`}>
          {m.viewAll}
          <ChevronIcon />
        </a>
      </div>
      <div className={styles.popularGrid}>
        {shown.map((item, index) => (
          <PopularCard key={item.id} item={item} m={m} rank={ready ? index + 1 : undefined} />
        ))}
      </div>
    </section>
  );
}

export function MenuSection({
  category,
  items,
  cardMode,
  m,
}: {
  category: Category;
  items: readonly MenuItem[];
  cardMode: CardMode;
  m: StorefrontMessages;
}) {
  if (items.length === 0) return null;
  const featured = items.filter((i) => i.featured);
  const rest = items.filter((i) => !i.featured);
  const titleId = `sf-cat-title-${category.id}`;

  return (
    <section className={styles.section} id={`sf-cat-${category.id}`} aria-labelledby={titleId}>
      <div className={styles.sectionHead}>
        <span className={styles.sectionBar} aria-hidden="true" />
        <h2 className={styles.sectionTitle} id={titleId} dir="auto">
          {category.name}
        </h2>
      </div>
      {category.blurb === null ? null : (
        <p className={styles.sectionBlurb} dir="auto">
          {category.blurb}
        </p>
      )}
      {featured.length === 0 ? null : (
        <div className={styles.listWrap}>
          {featured.map((item) => (
            <FeaturedCard key={item.id} item={item} m={m} />
          ))}
        </div>
      )}
      {rest.length === 0 ? null : (
        <div className={cardMode === 'grid' ? styles.gridWrap : styles.listWrap}>
          {rest.map((item) =>
            cardMode === 'grid' ? (
              <GridCard key={item.id} item={item} m={m} />
            ) : (
              <ListRow key={item.id} item={item} m={m} />
            ),
          )}
        </div>
      )}
    </section>
  );
}

export function rankLabel(m: StorefrontMessages, n: number): string {
  return fill(m.rankN, { n: String(n) });
}
