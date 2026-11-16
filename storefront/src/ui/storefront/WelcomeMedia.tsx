'use client';

import { useState } from 'react';
import type { Tenant } from '@/source/types';

/** One explicitly selected published resource; no original access or processing. */
export function WelcomeMedia({ video, image, label }: {
  video?: Tenant['welcomeVideo']; image: string | null; label: string;
}) {
  const [failedVideo, setFailedVideo] = useState<string | null>(null);
  const [failedImage, setFailedImage] = useState<string | null>(null);
  const playable = video && video.url !== failedVideo;
  return <figure data-sf-welcome-media={playable ? 'video' : 'image'}>
    {playable ? <video key={video.url} src={video.url} poster={image ?? undefined}
      width={video.width} height={video.height} controls muted playsInline preload="metadata"
      aria-label={label} onError={() => setFailedVideo(video.url)} /> : image && image !== failedImage ? (
      /* eslint-disable-next-line @next/next/no-img-element */
      <img src={image} alt="" width={960} height={540} decoding="async" onError={() => setFailedImage(image)} />
    ) : <div aria-hidden="true" />}
  </figure>;
}
