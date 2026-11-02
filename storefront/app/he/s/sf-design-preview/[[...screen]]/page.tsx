import { CinematicPreviewPage, type CinematicPreviewParams } from '@/preview/cinematic/PreviewPage';

export const dynamic = 'force-dynamic';

export default function Page({ params }: { params: CinematicPreviewParams }) {
  return <CinematicPreviewPage locale="he" params={params} />;
}
