import { CinematicPreviewMenu } from '@/preview/cinematic/PreviewMenu';

export const dynamic = 'force-dynamic';

export default function Page({ searchParams }: { searchParams: Promise<{ scene?: string | string[] }> }) {
  return <CinematicPreviewMenu locale="ar" searchParams={searchParams} />;
}
