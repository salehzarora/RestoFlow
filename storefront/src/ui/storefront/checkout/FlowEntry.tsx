'use client';

import dynamic from 'next/dynamic';
import type { FlowProps } from './FlowRuntime';

// Literal, bounded entries keep the unused transport/UI out of first-load JS.
// SSR stays enabled so both variants retain their server-rendered frame.
const FixtureFlow = dynamic(() => import('./FlowRuntime').then((module) => module.FlowRuntime), { ssr: true });
const LiveFlow = dynamic(() => import('./LiveFlowRuntime').then((module) => module.LiveFlowRuntime), { ssr: true });

export function FlowEntry(props: FlowProps) {
  return props.source === 'live' ? <LiveFlow {...props} /> : <FixtureFlow {...props} />;
}
