'use client';

import { useLayoutEffect, useRef } from 'react';
import type { Tenant } from '@/source/types';

/** Independent editorial media. Focal crop changes presentation, never the asset. */
export function MenuBanner({ banner, className }: { banner: Tenant['menuBanner']; className: string }) {
  const photo = useRef<HTMLImageElement>(null);
  const point = (value: number | undefined) => Number.isInteger(value) && value! >= 0 && value! <= 100 ? value! : 50;
  const x = point(banner?.focalX), y = point(banner?.focalY);
  useLayoutEffect(() => { if (photo.current) photo.current.style.objectPosition = `${x}% ${y}%`; }, [x, y, banner?.image, banner?.enabled]);
  if (!banner?.enabled || !banner.image) return null;
  return <div className={className} data-sf-menu-banner="" aria-hidden="true">
    {/* eslint-disable-next-line @next/next/no-img-element */}
    <img ref={photo} src={banner.image} alt="" width={960} height={420} decoding="async" fetchPriority="high" />
  </div>;
}
