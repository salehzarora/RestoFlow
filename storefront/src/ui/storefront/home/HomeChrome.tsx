'use client';

import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { markIntroSeen, isAnnouncementDismissed, markAnnouncementDismissed } from '@/session/uiSession';
import { fill, storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import type { CardMode, Category, MenuItem, Tenant } from '@/source/types';
import { searchItems } from '@/source/search';
import { cartPath } from '@/routes/routes';
import { CloseIcon, SearchIcon, TrolleyIcon } from '../icons';
import { TenantText } from '../TenantText';

import { RestaurantContact } from '../RestaurantContact';
import { useCartApi } from '../cart/CartContext';
import { BrandLockup } from './HomeParts';
import { MenuSection, GridCard, ListRow } from './MenuParts';
function NoResultsTitle({ template, query }: { template: string; query: string }) { const at = template.indexOf('{q}'); return at < 0 ? <>{template}</> : <>{template.slice(0, at)}<bdi>{query}</bdi>{template.slice(at + 3)}</>; }
function CategoryIcon({ path }: { path: string }) { return <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d={path} /></svg>; }
import styles from './home.module.css';

/** Presentation state only. Product/cart/order authority stays in StorefrontRuntime. */
export function HomeChrome({ tenant, locale, slug, language, categories, items, cardMode, announcement, hero, service, notice, empty, cart }: {
  tenant: Tenant; locale: Locale; slug: string; language: ReactNode;
  categories: readonly Category[]; items: readonly MenuItem[]; cardMode: CardMode;
  announcement: string | null; hero: ReactNode; service: ReactNode; notice: ReactNode; empty: ReactNode; cart: ReactNode;
}) {
  const m = storefrontMessages(locale);
  const [active, setActive] = useState(categories[0]?.id ?? '');
  const [query, setQuery] = useState('');
  const [picks, setPicks] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [cartOpen, setCartOpen] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const transferringToProduct = useRef(false);
  const search = useRef<HTMLInputElement>(null);
  const cartApi = useCartApi();
  const count = cartApi?.ready ? cartApi.summary.itemCount : 0;
  useEffect(() => { markIntroSeen(slug); }, [slug]);
  useLayoutEffect(() => { setDismissed(isAnnouncementDismissed(slug)); }, [slug]);
  useEffect(() => {
    if (!cartOpen) return;
    const node = dialog.current;
    if (!node) return;
    const opener = document.activeElement;
    node.showModal();
    document.body.classList.add(styles.bodyLock);
    return () => {
      node.close(); document.body.classList.remove(styles.bodyLock);
      if (!transferringToProduct.current && opener instanceof HTMLElement && opener.isConnected) opener.focus();
      transferringToProduct.current = false;
    };
  }, [cartOpen]);
  useEffect(() => {
    const shortcut = (e: KeyboardEvent) => {
      const target = e.target;
      if (e.key === '/' && !e.ctrlKey && !e.metaKey && !e.altKey && target instanceof HTMLElement && !target.closest('input,textarea,[contenteditable="true"],dialog,[role="dialog"],[aria-modal="true"]')) { e.preventDefault(); search.current?.focus(); }
    };
    document.addEventListener('keydown', shortcut);
    return () => document.removeEventListener('keydown', shortcut);
  }, []);
  // A refreshed menu can remove the selected category while this UI is retained.
  const activeCategory = categories.some(c => c.id === active) ? active : categories[0]?.id ?? '';
  const shown = query.trim() ? searchItems(items, query) : picks ? items.filter(i => i.featured && !i.soldOut) : items.filter(i => i.categoryId === activeCategory);
  const selected = categories.find(c => c.id === activeCategory);
  const switchCategory = (id: string) => { setActive(id); setPicks(false); setQuery(''); };
  // Close the native top layer before the existing delegated product opener runs.
  // Enter/Space is intercepted by that opener, so waiting for click is insufficient.
  const transferToProduct = (target: EventTarget | null) => {
    if (!(target instanceof Element) || !target.closest('[data-sf-item]')) return;
    transferringToProduct.current = true;
    dialog.current?.close();
    setCartOpen(false);
  };
  return <>
    <div className={styles.topline}><div className={styles.inner}><TenantText>{tenant.city}</TenantText><TenantText>{tenant.tagline}</TenantText><span>{tenant.service.state === 'open' ? m.openNow : tenant.service.state === 'closed' ? m.closed : m.paused}</span></div></div>
    <header className={styles.header} data-sf-module="compact">
      <div className={`${styles.inner} ${styles.headerInner}`}>
        <a className={styles.brandLink} href="#" aria-label={tenant.displayName}><BrandLockup tenant={tenant} /></a>
        <nav className={styles.headerNav} aria-label={m.menuLabel}><a href="#sf-menu">{m.menuLabel}</a><button type="button" onClick={() => { setPicks(true); setQuery(''); document.getElementById('sf-menu')?.scrollIntoView({block:'start', behavior:'auto'}); }}>{m.chefPicks}</button><a href="#sf-find">{m.findUs}</a></nav>
        <div className={styles.headerActions}><RestaurantContact publicPhone={tenant.phone} label={m.callRestaurant} iconOnly className={styles.headerPhone} />{language}<button className={styles.cartTrigger} data-sf-cart-trigger="" type="button" onClick={() => setCartOpen(true)}><TrolleyIcon /><span>{m.yourChoices}</span><b>{count}</b></button></div>
      </div>
    </header>
    {hero}
    {announcement === null || dismissed ? null : <div className={styles.announce} data-sf-module="announce" role="status"><TenantText>{announcement}</TenantText><button className={styles.announceClose} type="button" aria-label={m.close} onClick={() => { setDismissed(true); markAnnouncementDismissed(slug); }}><CloseIcon /></button></div>}
    {notice}
    {empty ?? <section className={`${styles.inner} ${styles.menu}`} id="sf-menu" aria-label={m.menuLabel}>
      <div className={styles.menuHeading}><div><p className={styles.eyebrow}>{m.menuLabel}</p><h2>{m.menuHeading}</h2></div><form className={styles.searchBox} role="search" onSubmit={e => e.preventDefault()}><SearchIcon /><input ref={search} type="search" autoComplete="off" maxLength={80} value={query} onChange={e => { setQuery(e.target.value); setPicks(false); }} placeholder={m.searchPh} aria-label={m.search} />{query ? <button type="button" aria-label={m.clearSearch} onClick={() => { setQuery(''); search.current?.focus(); }}><CloseIcon /></button> : <kbd aria-hidden="true">/</kbd>}</form></div>
      <div className={styles.categoryWrap}><nav className={styles.rail} aria-label={m.menuLabel} data-sf-module="categories">{categories.map(category => <button className={`${styles.chip} ${category.id === activeCategory && !query && !picks ? styles.chipActive : ''}`} type="button" key={category.id} aria-current={category.id === activeCategory && !query && !picks ? 'true' : undefined} onClick={() => switchCategory(category.id)}><CategoryIcon path={category.iconPath} /><span dir="auto">{category.name}</span><small dir="ltr">{String(items.filter(i => i.categoryId === category.id).length).padStart(2, '0')}</small></button>)}{items.some(item => item.featured && !item.soldOut) ? <button type="button" className={`${styles.chip} ${styles.picksChip} ${picks && !query ? styles.chipActive : ''}`} aria-current={picks && !query ? 'true' : undefined} onClick={() => { setPicks(true); setQuery(''); }}>{m.chefPicks}</button> : null}</nav></div>
      {query.trim() || picks ? <section className={styles.section} data-sf-module="sections" aria-label={query.trim() ? m.search : m.chefPicks}><div className={styles.sectionHead}><h3>{picks ? m.chefPicks : m.search}</h3><span role="status">{shown.length === 1 ? m.item : fill(m.items, {n:String(shown.length)})}</span></div>{shown.length ? <div className={cardMode === 'grid' ? styles.gridWrap : styles.listWrap}>{shown.map(item => cardMode === 'grid' ? <GridCard item={item} m={m} key={item.id} /> : <ListRow item={item} m={m} key={item.id} />)}</div> : <div className={styles.empty} role="status"><SearchIcon /><h3>{query.trim() ? <NoResultsTitle template={m.noResults} query={query.trim()} /> : m.emptyMenu}</h3><p>{m.tryOther}</p><button className={styles.promoCta} type="button" onClick={() => { setQuery(''); setPicks(false); }}>{m.browseMenu}</button></div>}</section> : selected ? <MenuSection category={selected} items={shown} cardMode={cardMode} m={m} /> : null}
    </section>}
    {service}
    {cartOpen ? <dialog className={styles.cartDialog} ref={dialog} aria-label={m.cart} onCancel={() => setCartOpen(false)} onClickCapture={e => transferToProduct(e.target)} onKeyDownCapture={e => { if (e.key === 'Enter' || e.key === ' ') transferToProduct(e.target); }} onClick={e => { if (e.target === e.currentTarget) setCartOpen(false); }}><button className={styles.cartClose} type="button" aria-label={m.close} onClick={() => setCartOpen(false)}><CloseIcon /></button>{cart}<a className={styles.cartEdit} href={cartPath(locale, slug)}>{m.edit}</a></dialog> : null}
  </>;
}
