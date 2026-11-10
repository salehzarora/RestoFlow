'use client';

import { useLayoutEffect, useRef, useState, type PointerEvent } from 'react';
import type { Locale } from '@/i18n/locales';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { MenuItem } from '@/source/types';
import { PlusIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Price } from './HomeParts';
import { carouselDragPosition, carouselOrbit, carouselPosition, cycleIndex, swipeIntent, swipeStep } from './carousel';
import { carouselImageSources } from './productImage';
import styles from './carousel.module.css';

const COPY = {
  ar: { previous: 'المنتج السابق', next: 'المنتج التالي', swipe: 'اسحب لاختيار وجبتك', gallery: 'عارض المنتجات' },
  he: { previous: 'המוצר הקודם', next: 'המוצר הבא', swipe: 'החליקו לבחירת המנה', gallery: 'גלריית מוצרים' },
  en: { previous: 'Previous product', next: 'Next product', swipe: 'Swipe to find your favourite', gallery: 'Product carousel' },
} as const;
type SlideAnimation = { animations: Animation[]; dragging: boolean };

/** One selection per mounted category; the existing runtime owns product opening. */
export function ProductCarousel({ items, m, locale, label }: {
  items: readonly MenuItem[]; m: StorefrontMessages; locale: Locale; label: string;
}) {
  const [selectedId, setSelectedId] = useState(items[0]?.id ?? '');
  const active = Math.max(0, items.findIndex(item => item.id === selectedId));
  const current = items[active];
  const [drag, setDrag] = useState<{ dx: number; orbit: number } | null>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const slideAnimations = useRef(new Map<HTMLButtonElement, SlideAnimation>());
  const gesture = useRef<{ id: number; x: number; y: number; orbit: number; scope: string; intent: ReturnType<typeof swipeIntent> } | null>(null);
  const suppressClick = useRef(false);
  const copy = COPY[locale];
  const rtl = locale !== 'en';
  const scope = `${current?.id}\0${items.map(item => item.id).join('\0')}`;
  // Animation effects preserve the closed CSP and leave CSSOM theming solely
  // in ThemeScope. A paused effect tracks the finger without inline styles.
  useLayoutEffect(() => {
    const stage = stageRef.current;
    const running = slideAnimations.current;
    if (!stage) {
      for (const entry of running.values()) for (const animation of entry.animations) animation.cancel();
      running.clear();
      return;
    }
    const nodes = [...stage.querySelectorAll<HTMLButtonElement>('[data-sf-carousel-index]')];
    for (const [node, entry] of running) if (!nodes.includes(node)) {
      for (const animation of entry.animations) animation.cancel();
      running.delete(node);
    }
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    // Explicit settles must not compete with the normal arrow CSS transition.
    stage.toggleAttribute('data-sf-settling', !drag && running.size > 0 && !reduced);
    for (const node of nodes) {
      const entry = running.get(node);
      if ((!drag && !entry) || typeof node.animate !== 'function') continue;
      const index = Number(node.dataset.sfCarouselIndex), item = items[index];
      const frame = carouselDragPosition(index, active, items.length, drag?.dx ?? 0, drag?.orbit ?? carouselOrbit(window.innerWidth), rtl);
      const disabled = index === active && item.soldOut;
      const target = {
        transform: `translateX(calc(var(--center) + ${frame.x}px)) translateY(${frame.y}px) scale(${frame.scale})`,
        opacity: String(disabled ? Math.min(.7, frame.opacity) : frame.opacity),
        filter: `brightness(${frame.brightness})${disabled ? ' saturate(.4)' : ''}`,
        visibility: frame.visible ? 'visible' : 'hidden', zIndex: String(frame.zIndex),
      };
      if (drag) {
        const held = { ...target, pointerEvents: 'none' };
        if (entry?.dragging) (entry.animations[0].effect as KeyframeEffect).setKeyframes([held, held]);
        else {
          for (const animation of entry?.animations ?? []) animation.cancel();
          const animation = node.animate([held, held], { duration: 1, fill: 'both' });
          animation.pause(); animation.currentTime = 0;
          running.set(node, { animations: [animation], dragging: true });
        }
      } else if (entry) {
        const computed = getComputedStyle(node);
        const from = { transform: computed.transform, filter: computed.filter, visibility: computed.visibility, zIndex: computed.zIndex };
        const opacity = computed.opacity;
        for (const animation of entry.animations) animation.cancel();
        running.delete(node);
        if (!reduced) {
          const visual = node.animate([from, { transform: target.transform, filter: target.filter, visibility: target.visibility, zIndex: target.zIndex }],
            { duration: 600, easing: 'cubic-bezier(.22,.7,.2,1)' });
          const alpha = node.animate({ opacity: [opacity, target.opacity] }, { duration: 450, easing: 'ease' });
          const next = { animations: [visual, alpha], dragging: false };
          running.set(node, next);
          visual.onfinish = () => {
            if (running.get(node) !== next) return;
            for (const animation of next.animations) animation.cancel();
            running.delete(node);
            if (running.size === 0) stage.removeAttribute('data-sf-settling');
          };
        }
      }
    }
    if (running.size === 0) stage.removeAttribute('data-sf-settling');
  }, [drag, active, items, rtl]);
  useLayoutEffect(() => () => {
    for (const entry of slideAnimations.current.values()) for (const animation of entry.animations) animation.cancel();
    slideAnimations.current.clear();
  }, []);
  const move = (step: number) => {
    gesture.current = null;
    setDrag(null);
    const target = items[cycleIndex(active, step, items.length)];
    if (target) setSelectedId(target.id);
  };
  const start = (event: PointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || event.button !== 0 || items.length < 2) return;
    if ((event.target as Element).closest('[data-sf-carousel-prev],[data-sf-carousel-next]')) return;
    gesture.current = { id: event.pointerId, x: event.clientX, y: event.clientY, orbit: carouselOrbit(window.innerWidth), scope, intent: null };
  };
  const finish = (event: PointerEvent<HTMLDivElement>, cancelled = false) => {
    const from = gesture.current;
    if (!from || from.id !== event.pointerId) return;
    gesture.current = null;
    setDrag(null);
    if (from.intent === 'horizontal') {
      // Also consume the synthetic click after a rejected drag or cancellation.
      suppressClick.current = true;
      const step = cancelled || from.scope !== scope ? 0 : swipeStep(event.clientX - from.x, event.clientY - from.y, rtl);
      if (step) move(step);
    }
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
  };
  if (!current) return null;
  return <div className={styles.carousel} role="region" aria-label={label} aria-roledescription={copy.gallery}
    data-sf-carousel="" data-sf-selected={current.id} data-sf-count={items.length}
    onPointerDownCapture={event => { if (event.isPrimary && event.button === 0) suppressClick.current = false; }}
    onClickCapture={event => {
      if (suppressClick.current && event.detail > 0) { event.preventDefault(); event.stopPropagation(); suppressClick.current = false; }
    }}
    onKeyDown={event => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      event.preventDefault(); event.stopPropagation();
      move((event.key === 'ArrowLeft') === rtl ? 1 : -1);
    }}>
    <div ref={stageRef} className={styles.stage} data-sf-carousel-stage="" data-sf-dragging={drag ? '' : undefined} onPointerDown={start} onPointerUp={finish}
      onPointerCancel={event => finish(event, true)}
      onPointerMove={event => {
        const from = gesture.current;
        if (!from || from.id !== event.pointerId) return;
        if (from.scope !== scope) { finish(event, true); return; }
        const dx = event.clientX - from.x, dy = event.clientY - from.y;
        from.intent ??= swipeIntent(dx, dy);
        if (from.intent === 'horizontal') {
          if (!event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.setPointerCapture(event.pointerId);
          if (event.cancelable) event.preventDefault();
          setDrag({ dx, orbit: from.orbit });
        }
      }}>
      <span className={styles.orbit} aria-hidden="true" />
      {items.map((item, index) => {
        const position = carouselPosition(index, active, items.length);
        const selected = position === 'active';
        return <button type="button" key={item.id} className={styles.slide} data-position={position}
          data-sf-carousel-index={index}
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
