'use client';

import Link from 'next/link';
import { useEffect } from 'react';
import type { OrderMessages } from '@/i18n/orders';
import { orderSnapshotCopy, orderStatusCopy } from '@/i18n/orderCopy';
import { acceptanceEtaCopy } from '@/i18n/acceptanceEta';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import { menuPath } from '@/routes/routes';
import { useLiveOrder } from '../checkout/LiveOrderProvider';
import { BackLink, Banner, Money } from '../checkout/flowParts';
import { ClockIcon, CheckIcon, CloseIcon, InfoIcon } from '../icons';
import { TenantText } from '../TenantText';
import { RestaurantContact } from '../RestaurantContact';
import type { RequestTenant } from './requestParts';
import s from './liveRequest.module.css';

/** Private status reads only; no cancellation, kitchen timeline or demo state. */
export function LiveRequestRuntime({ locale, copy, slug, origin, tenant, publicPhone, onOrderAgain }: { locale: Locale; copy: OrderMessages; slug: string; origin?: string; tenant: RequestTenant; publicPhone?: string; onOrderAgain: () => void }) {
  const m = storefrontMessages(locale);
  const { controller, snapshot } = useLiveOrder(origin);
  const result = snapshot.result;
  const status = result?.status;
  const busy = snapshot.phase === 'submitting' || snapshot.phase === 'reconciling';
  useEffect(() => {
    if (!controller || (status !== 'pending' && snapshot.phase !== 'unknown')) return;
    const refresh = () => { if (document.visibilityState !== 'hidden') void controller.refresh(); };
    const timer = window.setInterval(refresh, 10_000);
    document.addEventListener('visibilitychange', refresh);
    window.addEventListener('online', refresh);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', refresh); window.removeEventListener('online', refresh); };
  }, [controller, status, snapshot.phase]);
  const current = result ? orderStatusCopy(result.status, copy) : null;
  const eta = status === 'accepted' && result?.acceptance_eta ? acceptanceEtaCopy(result.acceptance_eta, locale, copy) : null;
  const message = controller === null ? copy.noRecovery : orderSnapshotCopy(snapshot, copy) ?? (result === null ? copy.noRecovery : null);
  const tone = status === 'accepted' ? s.toneOk : status === 'rejected' ? s.toneBad : status === 'expired' ? s.toneNeutral : s.toneInfo;
  return <div className={s.screen} data-sf-screen="status" data-sf-web-order="status" data-sf-live-status={status ?? snapshot.phase}>
    <header className={s.head}><BackLink href={menuPath(locale, slug)} label={m.back} /><span className={s.headLogo} aria-hidden="true"><span className={s.logoInner}>{tenant.logo === null ? <span className={s.logoInitial}>{tenant.name.trim().slice(0, 1)}</span> : /* eslint-disable-next-line @next/next/no-img-element */ <img src={tenant.logo} alt="" width={40} height={40} decoding="async" />}</span></span><div className={s.headText}><div className={s.headCode}>{copy.status}</div><div className={s.headSub}><TenantText>{tenant.name}</TenantText> · {m.pickup}</div></div></header>
    <div className={s.body}>
      {current ? <div className={`${s.card} ${tone}`} data-sf-status-card={status}>
        <span className={s.cardIcon} aria-hidden="true">{status === 'accepted' ? <CheckIcon /> : status === 'rejected' ? <CloseIcon /> : <ClockIcon />}</span>
        <div className={s.cardText} role="status" aria-live="polite"><h1 className={s.cardTitle}>{current.title}</h1><p className={s.cardBody}>{current.body}</p>{status === 'rejected' && result?.customer_rejection_reason ? <p className={`${s.cardBody} ${s.customerReason}`} data-sf-customer-rejection-reason="">{copy.rejectionReasonLabel} <TenantText>{result.customer_rejection_reason}</TenantText></p> : null}</div>
      </div> : null}
      {eta ? <div className={s.statusSummary} data-sf-acceptance-eta=""><p className={s.cardBody}>{eta.duration}</p><p className={s.cardBody}>{eta.ready} <bdi>{eta.timezone}</bdi></p></div> : null}
      {message ? <Banner tone="info" icon={<InfoIcon />} title={message} testId={`status-${snapshot.phase}`} alert={!busy} /> : null}
      <RestaurantContact publicPhone={publicPhone} label={m.callRestaurant} className={s.chatOutline} />
      {controller ? <div className={s.actions}><button className={s.chatOutline} type="button" disabled={busy} onClick={() => { void (snapshot.canRetry ? controller.retry() : controller.refresh()); }} data-sf-status-action={snapshot.canRetry ? 'retry-original' : 'refresh'}>{snapshot.canRetry ? copy.retry : copy.refresh}</button></div> : null}
      {result ? <div className={s.statusSummary} data-sf-server-totals=""><div className={s.lineRow}><span>{m.subtotal}</span><Money minor={result.totals.subtotal_minor} /></div><div className={s.lineRow}><span>{copy.taxTotal}</span><Money minor={result.totals.tax_total_minor} /></div><div className={s.totalRow}><span>{m.total} · {copy.payAtPickup}</span><Money minor={result.totals.grand_total_minor} /></div></div> : null}
      {status && status !== 'pending' ? <div className={s.actions}><button className={s.chatOutline} type="button" disabled={busy} onClick={onOrderAgain} data-sf-status-action="order-again">{m.orderAgain}</button></div> : null}
      <div className={s.actions}><Link className={s.chatOutline} href={menuPath(locale, slug)} prefetch={false}>{m.browseMenu}</Link></div>
    </div>
  </div>;
}
