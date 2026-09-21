'use client';

/**
 * SEARCH - screen 3 of the approved handoff.
 *
 * MATCHING IS THE PROTOTYPE'S ONE LINE (Storefront.dc.html:789): a
 * case-insensitive SUBSTRING over `name + ' ' + description`, menu order
 * preserved, no ranking, no tokenising, no debounce, no minimum length. An
 * empty query shows the first six items. That filter is PROVEN by the canonical
 * screenshot: query "برجر" returns exactly ids 1, 6, 17 and 22 at 55/48/249/35,
 * which is pixel-for-pixel what G15 shows.
 *
 * THE BACK CHEVRON IS A LINK, not `history.back()`. The prototype's handler
 * goes to the MENU screen unconditionally, and in this build the menu is a
 * different static document - so an anchor is both faithful and works with no
 * JavaScript at all.
 *
 * THE DOCK IS ABSENT HERE. `showCartBar` requires `isMenu` in the prototype
 * (Storefront.dc.html:865) and neither search screenshot shows a dock.
 * COMPONENT_INVENTORY.md:100 says "home (and any menu-like screen)", which
 * would include search; the prototype plus both canonical PNGs outrank it and
 * the divergence is recorded in the Phase C report.
 */
import { useMemo, useRef, useState } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import { searchItems } from '@/source/search';
import type { Category, MenuItem } from '@/source/types';
import { ChevronIcon, CloseIcon, SearchIcon } from '../icons';
import { TenantText } from '../TenantText';
import shell from '../storefront.module.css';
import home from '../home/home.module.css';
import styles from './search.module.css';

/**
 * The longest query this field accepts. The handoff sets no cap and the
 * prototype has none, so a paste of arbitrary length would render at 17px/800
 * inside the no-results title. 80 is four times the longest item name in the
 * fixture; the bound is defensive, not a product rule.
 */
const MAX_QUERY = 80;

/**
 * Render `noResults` with the visitor's query BIDI-ISOLATED.
 *
 * `{q}` is untrusted text dropped into a system sentence. In an RTL sentence a
 * Latin or mixed query reorders the whole line, so the run is wrapped in
 * `<bdi>` - the element that exists for exactly this. The handoff is silent on
 * it and the prototype does nothing; this is a deliberate addition.
 */
function NoResultsTitle({ template, query }: { template: string; query: string }) {
  const marker = '{q}';
  const at = template.indexOf(marker);
  if (at === -1) return <>{template}</>;
  return (
    <>
      {template.slice(0, at)}
      <bdi>{query}</bdi>
      {template.slice(at + marker.length)}
    </>
  );
}

export function SearchScreen({
  items,
  categories,
  m,
  menuHref,
}: {
  items: readonly MenuItem[];
  categories: readonly Category[];
  m: StorefrontMessages;
  menuHref: string;
}) {
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement | null>(null);

  const results = useMemo(() => searchItems(items, query), [items, query]);
  const trimmed = query.trim();
  const noResults = trimmed.length > 0 && results.length === 0;

  const categoryName = useMemo(() => {
    const byId = new Map(categories.map((c) => [c.id, c.name]));
    return (id: string) => byId.get(id) ?? '';
  }, [categories]);

  // Announced politely after each change. Both strings are authored copy: the
  // count reuses the item/items pair, and the empty case reuses `noResults`.
  const announcement = noResults
    ? fill(m.noResults, { q: trimmed })
    : results.length === 1
      ? m.item
      : fill(m.items, { n: String(results.length) });

  return (
    <div className={styles.screen}>
      <div className={styles.header}>
        <a className={styles.back} href={menuHref} aria-label={m.back}>
          <ChevronIcon />
        </a>

        <div className={styles.field} role="search">
          <SearchIcon />
          <input
            className={styles.input}
            ref={inputRef}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={m.searchPh}
            aria-label={m.search}
            maxLength={MAX_QUERY}
            autoComplete="off"
            /* eslint-disable-next-line jsx-a11y/no-autofocus -- DESIGN_HANDOFF.md:90
               specifies an autofocused field; this screen exists only to be typed in. */
            autoFocus
          />
          {/* Shown whenever there IS text, not whenever the TRIMMED text is
              non-empty. The prototype uses the trimmed value, so a
              whitespace-only entry leaves characters in the field with no way
              to clear them; that is a defect and is not reproduced. */}
          {query.length === 0 ? null : (
            <button
              className={styles.clear}
              type="button"
              aria-label={m.close}
              onClick={() => {
                setQuery('');
                inputRef.current?.focus();
              }}
            >
              <CloseIcon />
            </button>
          )}
        </div>
      </div>

      <span className={home.srOnly} role="status" aria-live="polite">
        {announcement}
      </span>

      <div className={styles.list}>
        {noResults ? (
          <div className={styles.empty}>
            <p className={styles.emptyTitle}>
              <NoResultsTitle template={m.noResults} query={trimmed} />
            </p>
            <p className={styles.emptyBody}>{m.tryOther}</p>
          </div>
        ) : (
          results.map((item) => (
            <div
              className={`${styles.row} ${item.soldOut ? styles.rowSoldOut : ''}`}
              key={item.id}
              role="button"
              tabIndex={item.soldOut ? -1 : 0}
              data-sf-item={item.id}
              aria-disabled={item.soldOut ? 'true' : undefined}
            >
              <span className={styles.thumb}>
                {item.image === null ? (
                  <span className={styles.thumbNone} aria-hidden="true">
                    {item.name.trim().slice(0, 1)}
                  </span>
                ) : (
                  /* eslint-disable-next-line @next/next/no-img-element */
                  <img
                    className={styles.thumbImg}
                    src={item.image}
                    alt=""
                    width={112}
                    height={112}
                    loading="lazy"
                    decoding="async"
                  />
                )}
              </span>

              <span className={styles.rowBody}>
                <span className={styles.rowName}>
                  <TenantText>{item.name}</TenantText>
                </span>
                <span className={styles.rowCat}>
                  <TenantText>{categoryName(item.categoryId)}</TenantText>
                </span>
              </span>

              {/* A sold-out row is dimmed in the canonical design but carries no
                  badge slot, so the reason is given to assistive technology
                  only - it adds no pixels and invents no visual element. */}
              {item.soldOut ? <span className={home.srOnly}>{m.soldOut}</span> : null}

              <span className={`${styles.rowPrice} ${shell.ltr}`} dir="ltr">
                {formatMoney(item.priceMinor)}
              </span>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
