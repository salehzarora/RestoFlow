'use client';

import { useRef, useState, type PointerEvent } from 'react';
import type { Locale } from '@/i18n/locales';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { MenuItem } from '@/source/types';
import { PlusIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Price } from './HomeParts';
import { carouselPosition, cycleIndex, swipeStep } from './carousel';
import { carouselImageSources } from './productImage';
import styles from './carousel.module.css';

const COPY = {
  ar: { previous: 'المنتج السابق', next: 'المنتج التالي', swipe: 'اسحب لاختيار وجبتك', gallery: 'عارض المنتجات' },
  he: { previous: 'המוצר הקודם', next: 'המוצר הבא', swipe: 'החליקו לבחירת המנה', gallery: 'גלריית מוצרים' },
  en: { previous: 'Previous product', next: 'Next product', swipe: 'Swipe to find your favourite', gallery: 'Product carousel' },
} as const;

/** One selection per mounted category; the existing runtime owns product opening. */
export function ProductCarousel({ items, m, locale, label }: {
  items: readonly MenuItem[]; m: StorefrontMessages; locale: Locale; label: string;
}) {
  const [selectedId, setSelectedId] = useState(items[0]?.id ?? '');
  const active = Math.max(0, items.findIndex(item => item.id === selectedId));
  const current = items[active];
  const gesture = useRef<{ id: number; x: number; y: number } | null>(null);
  const suppressClick = useRef(false);
  const copy = COPY[locale];
  const rtl = locale !== 'en';
  const move = (step: number) => {
    const target = items[cycleIndex(active, step, items.length)];
    if (target) setSelectedId(target.id);
  };
  const start = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || event.button !== 0 || items.length < 2) return;
    suppressClick.current = false;
    gesture.current = { id: event.pointerId, x: event.clientX, y: event.clientY };
  };
  const finish = (event: PointerEvent<HTMLDivElement>) => {
    const from = gesture.current;
    gesture.current = null;
    if (!from || from.id !== event.pointerId) return;
    const step = swipeStep(event.clientX - from.x, event.clientY - from.y, rtl);
    if (step) { suppressClick.current = true; move(step); }
  };
  if (!current) return null;
  return <div className={styles.carousel} role="region" aria-label={label} aria-roledescription={copy.gallery}
    data-sf-carousel="" data-sf-selected={current.id} data-sf-count={items.length}
    onKeyDown={event => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      event.preventDefault(); event.stopPropagation();
      move((event.key === 'ArrowLeft') === rtl ? 1 : -1);
    }}>
    <div className={styles.stage} data-sf-carousel-stage="" onPointerDown={start} onPointerUp={finish}
      onPointerCancel={() => { gesture.current = null; }}
      onPointerMove={event => {
        const from = gesture.current;
        if (!from || from.id !== event.pointerId) return;
        const dx = Math.abs(event.clientX - from.x), dy = Math.abs(event.clientY - from.y);
        if (dx > 12 && dx > dy * 1.25) event.currentTarget.setPointerCapture(event.pointerId);
      }}
      onClickCapture={event => {
        if (suppressClick.current) { event.preventDefault(); event.stopPropagation(); suppressClick.current = false; }
      }}>
      <span className={styles.orbit} aria-hidden="true" />
      {items.map((item, index) => {
        const position = carouselPosition(index, active, items.length);
        const selected = position === 'active';
        return <button type="button" key={item.id} className={styles.slide} data-position={position}
          data-sf-carousel-product={item.id} data-sf-item={selected ? item.id : undefined}
          aria-label={item.name} aria-hidden={position === 'away' ? true : undefined}
          tabIndex={position === 'away' ? -1 : 0} disabled={selected && item.soldOut}
          onClick={selected ? undefined : () => setSelectedId(item.id)}>
          {item.image ? <img src={item.image} {...carouselImageSources(item, selected)} alt="" width={600} height={600} draggable={false}
            loading={position === 'away' ? 'lazy' : 'eager'} decoding="async" />
            : <span className={styles.noImage}>{item.name.slice(0, 1)}</span>}
        </button>;
      })}
      {items.length > 1 ? <div className={styles.controls}>
        <button className={styles.previous} type="button" aria-label={copy.previous} onClick={() => move(-1)} data-sf-carousel-prev="">
          <svg viewBox="0 0 76 42" aria-hidden="true"><path d="M6 5C1 22 23 32 65 34M56 27l10 7-12 4" /></svg>
        </button>
        <button className={styles.next} type="button" aria-label={copy.next} onClick={() => move(1)} data-sf-carousel-next="">
          <svg viewBox="0 0 76 42" aria-hidden="true"><path d="M6 5C1 22 23 32 65 34M56 27l10 7-12 4" /></svg>
        </button>
      </div> : null}
    </div>
    <div className={styles.selection}>
      <div className={styles.details} key={current.id} aria-live="polite" aria-atomic="true">
        <p className={styles.name}><TenantText>{current.name}</TenantText></p>
        <Price minor={current.priceMinor} from={current.hasOptions ? m.from : undefined} />
        {current.soldOut ? <p className={styles.soldOut}>{m.soldOut}</p> : null}
      </div>
      <button type="button" className={styles.add} data-sf-item={current.id} disabled={current.soldOut}
        aria-label={`${m.addShort}: ${current.name}`}><PlusIcon /></button>
    </div>
    {items.length > 1 ? <p className={styles.hint}>{copy.swipe}<span dir="ltr">{String(active + 1).padStart(2, '0')} / {String(items.length).padStart(2, '0')}</span></p> : null}
  </div>;
}
