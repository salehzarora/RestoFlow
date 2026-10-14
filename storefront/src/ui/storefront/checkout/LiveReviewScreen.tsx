'use client';

import { useRef, useState } from 'react';
import type { CartApi } from '@/cart/useCart';
import { optionSummary } from '@/cart/cartModel';
import type { OrderController, OrderSnapshot } from '@/orders';
import { orderFromCart } from '@/orders';
import type { OrderMessages } from '@/i18n/orders';
import { orderSnapshotCopy } from '@/i18n/orderCopy';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { Quote } from '@/money/quote';
import type { MotionMode } from '@/source/types';
import type { CheckoutDraft } from './draft';
import type { FlowTenant } from './DetailsScreen';
import { TenantText } from '../TenantText';
import { InfoIcon, PersonIcon, PinIcon } from '../icons';
import { Banner, Bidi, FooterCta, ReviewBlock, StepHeader, Totals } from './flowParts';
import s from './flow.module.css';

export function LiveReviewScreen({ m, copy, cart, draft, quote, tenant, motion, backHref, blockedReason, submittable, controller, snapshot, onEditDetails }: {
  m: StorefrontMessages; copy: OrderMessages; cart: CartApi; draft: CheckoutDraft; quote: Quote; tenant: FlowTenant; motion: MotionMode; backHref: string; blockedReason: string | null; submittable: boolean; controller: OrderController | null; snapshot: OrderSnapshot; onEditDetails: () => void;
}) {
  const [invalid, setInvalid] = useState(false);
  const locked = useRef(false);
  const busy = snapshot.phase === 'submitting' || snapshot.phase === 'reconciling';
  const unresolved = ['unknown', 'not_found', 'unavailable'].includes(snapshot.phase);
  const latest = useRef({ cart, draft, submittable, blockedReason });
  latest.current = { cart, draft, submittable, blockedReason };
  const send = async () => {
    const current = latest.current;
    if (!controller || locked.current || busy || unresolved || current.blockedReason || !current.submittable) return;
    locked.current = true;
    setInvalid(false);
    try {
      // Cart identities, quantities and both note scopes only. Display prices
      // never become request fields; the Edge/SQL quote remains authoritative.
      await controller.submit(orderFromCart(current.cart.state, { name: current.draft.fullName, phone: current.draft.phone }, current.draft.orderNotes));
    } catch { setInvalid(true); }
    finally { locked.current = false; }
  };
  const message = invalid ? copy.invalid : orderSnapshotCopy(snapshot, copy);
  return <div className={`${s.screen} ${motion === 'calm' ? '' : s.motionFull}`} data-sf-screen="review" data-sf-live-checkout="" data-sf-web-order="review">
    <StepHeader m={m} title={m.review} backHref={backHref} step={2} pickupOnly />
    <div className={`${s.body} ${s.bodySteps}`}>
      <div className={s.summary}>
        <ul className={s.summaryList}>{cart.summary.lines.map((line) => <li className={s.summaryLine} key={line.line.lineId}>
          <span className={`${s.qtyChip} ${s.ltr}`} dir="ltr">{line.line.qty}×</span>
          <span className={`${s.summaryText} ${s.liveSummaryText}`}><span className={s.summaryName}><TenantText>{line.item.name}</TenantText></span>
            <span className={s.summaryMods}><TenantText>{optionSummary(line)}</TenantText></span>
            {line.line.note ? <span className={s.summaryNote} data-sf-item-note=""><TenantText>{line.line.note}</TenantText></span> : null}
          </span><span className={`${s.summaryPrice} ${s.ltr}`} dir="ltr">{formatMoney(line.totalMinor)}</span>
        </li>)}</ul>
        <Totals quote={quote} m={m} bare /><p className={s.help} data-sf-estimate="">{copy.estimate}</p>
      </div>
      <div className={s.blocks}>
        <ReviewBlock icon={<PinIcon />} label={m.receive} value={fill(m.pickupAt, { r: tenant.name })} sub={<TenantText>{tenant.address}</TenantText>} editLabel={m.edit} editName={`${m.edit} · ${m.stepDetails}`} onEdit={onEditDetails} testId="receive" />
        <ReviewBlock icon={<PersonIcon />} label={m.customer} value={<Bidi>{draft.fullName}</Bidi>} sub={<span className={s.ltr} dir="ltr">{draft.phone}</span>} editLabel={m.edit} editName={`${m.edit} · ${m.stepDetails}`} onEdit={onEditDetails} testId="contact" />
      </div>
      {draft.orderNotes ? <section className={s.section} data-sf-order-notes=""><h2 className={s.sectionTitle}>{copy.orderNotes}</h2><TenantText>{draft.orderNotes}</TenantText></section> : null}
      <Banner tone="info" alert={false} smallIcon icon={<InfoIcon />} title={copy.payAtPickup} body={copy.sendInfo} testId="truth-notice" />
      {message ? <Banner tone="warn" icon={<InfoIcon />} title={message} testId={`order-${snapshot.phase}`} action={controller && !busy && unresolved ? { label: snapshot.canRetry ? copy.retry : copy.refresh, onAction: () => { void (snapshot.canRetry ? controller.retry() : controller.refresh()); } } : undefined} /> : null}
    </div>
    <FooterCta label={busy ? m.sending : blockedReason ?? m.sendRequest} onActivate={() => { void send(); }} busy={busy} blocked={busy || unresolved || blockedReason !== null || !submittable} dim={blockedReason !== null} centred testId="send" />
  </div>;
}
