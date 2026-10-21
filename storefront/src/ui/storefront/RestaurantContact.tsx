import { restaurantPhoneHref } from '@/source/publicPhone';

/** A plain user-activated link; no dialer API, order state or private fallback. */
export function RestaurantContact({ publicPhone, label, className }: { publicPhone: string | null | undefined; label: string; className: string }) {
  const href = restaurantPhoneHref(publicPhone);
  if (href === null) return null;
  return (
    <a className={className} href={href} data-sf-restaurant-contact="">
      <span>{label}{' '}<bdi dir="ltr">{publicPhone}</bdi></span>
    </a>
  );
}
