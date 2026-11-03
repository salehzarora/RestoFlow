import { SceneBackdrop } from './SceneBackdrop';
import type { menuBackground } from './menuBackground';
import styles from './home.module.css';

/** One full-document decorative layer. Product images and controls are siblings. */
export function MenuBackdrop({ background }: { background: ReturnType<typeof menuBackground> }) {
  if (background.kind === 'legacy') return <SceneBackdrop image={background.image} />;
  return <div className={styles.menuBackdrop} data-sf-menu-background="custom" aria-hidden="true">
    {/* eslint-disable-next-line @next/next/no-img-element */}
    <img src={background.image!} alt="" decoding="async" fetchPriority="high" />
  </div>;
}
