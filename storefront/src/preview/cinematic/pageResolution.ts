import { notFound } from 'next/navigation';
import { cinematicPreviewResolution } from './resolution';
import { cinematicPreviewScene } from './access';

/** Every explicit preview page remains guarded independently of its layout. */
export function requireCinematicPreviewResolution(scene?: unknown) {
  const resolution = cinematicPreviewResolution(undefined, cinematicPreviewScene(scene));
  if (resolution === null) notFound();
  return resolution;
}
