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
  rankLabel,
}: {
  item: MenuItem;
  shape: 'featured' | 'popular' | 'grid' | 'row';
  m: StorefrontMessages;
  /** Popular-rail spotlight text: the localized rankN string, or "kitchen pick". */
  rankLabel?: string;
}) {
  const cls =
    shape === 'featured'
      ? styles.cardMediaFeatured
      : shape === 'popular'
        ? styles.cardMediaPopular
        : shape === 'grid'
          ? styles.cardMediaGrid
          : styles.rowMedia;
  // The popular card carries EXACTLY ONE badge and it is the spotlight label
  // (prototype/Storefront.dc.html:211); new/deal badges belong to the featured,
  // list and grid cards (:237, :255, :278). Same slot, same token, start side.
  const badgeText =
    rankLabel !== undefined
      ? rankLabel
      : item.badge === 'new'
        ? m.badgeNew
        : item.badge === 'deal'
          ? m.badgeDeal
          : null;

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
  rankLabel,
}: {
  item: MenuItem;
  m: StorefrontMessages;
  /** Required, not optional: a popular card without its spotlight label is a defect. */
  rankLabel: string;
}) {
  return (
    <div className={styles.card}>
      <Media item={item} shape="popular" m={m} rankLabel={rankLabel} />
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
 * looks: without it there is no rank number and no "most ordered" heading,
 * because no count exists to justify them. The one badge slot then carries the
 * honest alternative instead - "kitchen pick" (COMPONENT_INVENTORY.md:74).
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
    <section className={styles.section} aria-labelledby="sf-popular-title" data-sf-module="popular">
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
          <PopularCard
            key={item.id}
            item={item}
            m={m}
            rankLabel={ready ? rankLabel(m, index + 1) : m.chefPick}
          />
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
    <section className={styles.section} id={`sf-cat-${category.id}`} aria-labelledby={titleId} data-sf-module="sections">
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
