import { restaurantPhoneHref } from '@/source/publicPhone';
import { PhoneIcon } from './icons';

/** A plain user-activated link; no dialer API, order state or private fallback. */
export function RestaurantContact({ publicPhone, label, className, iconOnly = false }: { publicPhone: string | null | undefined; label: string; className: string; iconOnly?: boolean }) {
  const href = restaurantPhoneHref(publicPhone);
  if (href === null) return null;
  return (
    <a className={className} href={href} data-sf-restaurant-contact="" aria-label={iconOnly ? label : undefined}>
      {iconOnly ? <PhoneIcon /> : <span>{label}{' '}<bdi dir="ltr">{publicPhone}</bdi></span>}
    </a>
  );
}
