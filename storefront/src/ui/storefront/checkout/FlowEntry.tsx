'use client';

import dynamic from 'next/dynamic';
import { useMemo } from 'react';
import { unpackStorefrontMessages, type StorefrontMessageValues } from '@/i18n/storefrontValues';
import type { FlowProps } from './FlowRuntime';

// Literal, bounded entries keep the unused transport/UI out of first-load JS.
// SSR stays enabled so both variants retain their server-rendered frame.
const FixtureFlow = dynamic(() => import('./FlowRuntime').then((module) => module.FlowRuntime), { ssr: true });
const LiveFlow = dynamic(() => import('./LiveFlowRuntime').then((module) => module.LiveFlowRuntime), { ssr: true });

export function FlowEntry({ copyValues, ...props }: Omit<FlowProps, 'm'> & { copyValues: StorefrontMessageValues }) {
  const m = useMemo(() => unpackStorefrontMessages(copyValues), [copyValues]);
  return props.source === 'live' ? <LiveFlow {...props} m={m} /> : <FixtureFlow {...props} m={m} />;
}
