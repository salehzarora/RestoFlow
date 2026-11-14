'use client';

import { useLayoutEffect, useRef } from 'react';
import type { Tenant } from '@/source/types';

const point = (n: number | null | undefined) => Number.isInteger(n) && n! >= 0 && n! <= 100 ? n! : 50;
function height(value: number | null | undefined, width: number | null | undefined, naturalHeight: number | null | undefined, low: number, high: number, autoHigh: number) {
  if (Number.isInteger(value) && value! >= low && value! <= high) return `${value}px`;
  return width && naturalHeight && width > 0 && naturalHeight > 0
    ? `clamp(${low}px,calc(100vw * ${naturalHeight} / ${width}),${autoHigh}px)` : `${low}px`;
}

/** Published editorial media only. Legacy merchants retain their existing overlay. */
export function MenuBanner({ banner, className }: { banner: Tenant['menuBanner']; className: string }) {
  const host = useRef<HTMLDivElement>(null), photo = useRef<HTMLImageElement>(null);
  const responsive = banner?.layout === 'responsive';
  useLayoutEffect(() => {
    const el = host.current;
    if (!el) return;
    const focus = `${point(banner?.focalX)}% ${point(banner?.focalY)}%`;
    if (!responsive) { el.style.removeProperty('height'); if (photo.current) photo.current.style.objectPosition = focus; return; }
    // Same CSSOM assignment as the existing focal control, admitted by self-only CSP.
    const media = window.matchMedia('(min-width:651px)'), ownDesktop = !!banner?.desktopImage;
    const apply = () => {
      el.style.height = media.matches
        ? height(banner?.desktopHeightPx, ownDesktop ? banner?.desktopWidth : banner?.width, ownDesktop ? banner?.desktopHeight : banner?.height, 240, 560, 480)
        : height(banner?.mobileHeightPx, banner?.width, banner?.height, 320, 640, 640);
      if (photo.current) photo.current.style.objectPosition = media.matches
        ? `${point(banner?.desktopFocalX)}% ${point(banner?.desktopFocalY)}%` : focus;
    };
    apply(); media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [banner, responsive]);
  if (!banner?.enabled || (!banner.image && (!responsive || !banner.desktopImage))) return null;
  const desktop = banner.desktopImage || banner.image!;
  const desktopSet = banner.desktopImage && banner.desktopVariants?.length
    ? banner.desktopVariants.map(v => `${v.url} ${v.width}w`).join(', ') : desktop;
  // eslint-disable-next-line @next/next/no-img-element
  const image = <img ref={photo} src={banner.image || undefined} alt="" width={responsive ? banner.width || 960 : 960} height={responsive ? banner.height || 420 : 420} decoding="async" fetchPriority="high" />;
  return <div ref={host} className={className} data-sf-menu-banner="" data-sf-phone-empty={responsive && !banner.image ? '' : undefined} data-sf-banner-layout={responsive ? 'responsive' : undefined} aria-hidden="true">
    {responsive ? <picture><source media="(min-width:651px)" srcSet={desktopSet} sizes="100vw" />{image}</picture> : image}
  </div>;
}
