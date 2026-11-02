import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import { rubikPreloadHebrew } from '@/fonts/rubik-preload-hebrew';
import { CinematicPreviewLayout } from '@/preview/cinematic/PreviewLayout';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = { title: 'BIZBOT · Design Preview', robots: { index: false, follow: false } };

export default function Layout({ children }: { children: ReactNode }) {
  return <CinematicPreviewLayout fontClassName={rubikPreloadHebrew.className}>{children}</CinematicPreviewLayout>;
}
