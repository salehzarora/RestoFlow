'use client';

import { StorefrontRuntime } from '../StorefrontRuntime';
import { LiveFlowBody } from './LiveFlowBody';
import type { FlowProps } from './FlowRuntime';

/** Selected by the server for live menus; fixture machinery stays outside. */
export function LiveFlowRuntime(props: FlowProps) {
  if (!props.orderCopy) throw new Error('Live checkout messages are missing');
  return (
    <StorefrontRuntime
      source="live"
      slug={props.slug}
      menuVersion={props.menuVersion}
      items={props.items}
      groups={props.groups}
      zones={props.zones}
      taxRateBp={props.taxRateBp}
      orderingEnabled={props.tenant.orderingEnabled}
      locale={props.locale}
      motion={props.motion}
      state={props.state}
      opensAt={props.tenant.opensAt}
    >
      <LiveFlowBody {...props} orderCopy={props.orderCopy} />
    </StorefrontRuntime>
  );
}
