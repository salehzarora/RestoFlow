import { notFound } from 'next/navigation';

export const dynamic = 'force-dynamic';

/** Checkout, payment and arbitrary nested preview destinations stay unavailable. */
export default function Page() {
  notFound();
}
