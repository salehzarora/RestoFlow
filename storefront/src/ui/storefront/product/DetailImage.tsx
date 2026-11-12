import { useState } from 'react';
import type { MenuItem } from '@/source/types';

/** Mounted only by the open sheet; no original preloading or private paths. */
export function DetailImage({ item, className, placeholderClassName }: {
  item: MenuItem; className: string; placeholderClassName: string;
}) {
  const [failed, setFailed] = useState<readonly string[]>([]);
  const detail = item.detailImage;
  const src = [detail?.url, item.image].find(url => url && !failed.includes(url));
  if (!src) return <span className={placeholderClassName} aria-hidden="true" data-sf-detail-image="placeholder">{item.name.trim().slice(0, 1)}</span>;
  const original = src === detail?.url;
  return <img key={src} className={className} src={src} alt="" decoding="async"
    width={original ? detail?.width : undefined} height={original ? detail?.height : undefined}
    data-sf-detail-image={original ? 'original' : 'selected'}
    onError={() => setFailed(prior => prior.includes(src) ? prior : [...prior, src])} />;
}
