import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import { rubikPreloadArabic } from '@/fonts/rubik-preload-arabic';
import { CinematicPreviewLayout } from '@/preview/cinematic/PreviewLayout';

export const dynamic = 'force-dynamic';
export const metadata: Metadata = { title: 'BIZBOT · Design Preview', robots: { index: false, follow: false } };

export default function Layout({ children }: { children: ReactNode }) {
  return <CinematicPreviewLayout fontClassName={rubikPreloadArabic()}>{children}</CinematicPreviewLayout>;
}
