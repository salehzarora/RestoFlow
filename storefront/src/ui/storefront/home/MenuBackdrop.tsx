import type { menuBackground } from './menuBackground';
import styles from './home.module.css';

const ROWS = [8, 16, 32, 64] as const;
const ROW_CLASS = { 8: '', 16: styles.sceneRows16, 32: styles.sceneRows32, 64: styles.sceneRows64 };

/** Reuse the selected photograph through the menu, without enlarging it to document height. */
export function MenuBackdrop({ background, sectionCount = 0, itemCount = 0 }: {
  background: ReturnType<typeof menuBackground>; sectionCount?: number; itemCount?: number;
}) {
  const target = Math.max(8, sectionCount * 2 + Math.ceil(itemCount / 4));
  const rows = ROWS.find(count => count >= target) ?? 64;
  const image = background.image;
  return <div className={background.kind === 'legacy' ? styles.sceneBackdrop : styles.menuBackdrop}
    data-sf-menu-background={background.kind === 'custom' ? 'custom' : undefined} aria-hidden="true">
    {image === null ? null : <>
      <div className={`${styles.menuSceneContinuation} ${ROW_CLASS[rows]}`} data-sf-menu-continuation="">
        {Array.from({ length: rows }, (_, index) => <span className={styles.menuSceneStrip} data-sf-scene-strip="" key={index}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={image} srcSet={background.srcSet} sizes={background.sizes} alt="" decoding="async" fetchPriority="low" />
        </span>)}
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img data-sf-menu-primary="" src={image} srcSet={background.srcSet} sizes={background.sizes} alt="" decoding="async" fetchPriority="high" />
    </>}
  </div>;
}
