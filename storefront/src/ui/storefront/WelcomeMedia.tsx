'use client';

import { useEffect, useRef, useState } from 'react';
import type { Tenant } from '@/source/types';
import styles from './welcome.module.css';

/** A published, owner-selected backdrop. No original access or processing. */
export function WelcomeMedia({ video, image, playLabel, pauseLabel }: {
  video?: Tenant['welcomeVideo']; image: string | null; playLabel: string; pauseLabel: string;
}) {
  const [failedVideo, setFailedVideo] = useState<string | null>(null);
  const [failedImage, setFailedImage] = useState<string | null>(null);
  const [paused, setPaused] = useState(true);
  const player = useRef<HTMLVideoElement>(null);
  const userPaused = useRef(false);
  const activeVideo = video && video.url !== failedVideo ? video : null;
  useEffect(() => {
    const element = player.current;
    if (!element) return;
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    const sync = () => {
      if (preference.matches || userPaused.current) element.pause();
      else void element.play().catch(() => { /* Keep the poster and explicit Play control if autoplay is unavailable. */ });
    };
    sync();
    preference.addEventListener('change', sync);
    return () => preference.removeEventListener('change', sync);
  }, [activeVideo?.url]);
  const toggle = () => {
    const element = player.current;
    if (!element) return;
    userPaused.current = !element.paused;
    if (element.paused) void element.play().catch(() => {});
    else element.pause();
  };
  return <>
    <figure className={styles.backdrop} data-sf-welcome-media={activeVideo ? 'video' : 'image'} aria-hidden="true">
      {activeVideo ? <video ref={player} key={activeVideo.url} id="sf-welcome-background-video"
        src={activeVideo.url} poster={image ?? undefined} width={activeVideo.width} height={activeVideo.height}
        muted loop playsInline preload="metadata" onPlay={() => setPaused(false)} onPause={() => setPaused(true)}
        onError={() => setFailedVideo(activeVideo.url)} /> : image && image !== failedImage ? (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img src={image} alt="" decoding="async" fetchPriority="high" onError={() => setFailedImage(image)} />
      ) : null}
    </figure>
    {activeVideo ? <button className={styles.playback} type="button" data-sf-welcome-playback=""
      aria-label={paused ? playLabel : pauseLabel} aria-controls="sf-welcome-background-video" onClick={toggle}>
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d={paused ? 'M8 5v14l11-7z' : 'M7 5h4v14H7zm6 0h4v14h-4z'} /></svg>
    </button> : null}
  </>;
}
