import { notFound } from 'next/navigation';
import { cinematicPreviewResolution } from './resolution';

/** Every explicit preview page remains guarded independently of its layout. */
export function requireCinematicPreviewResolution() {
  const resolution = cinematicPreviewResolution();
  if (resolution === null) notFound();
  return resolution;
}
