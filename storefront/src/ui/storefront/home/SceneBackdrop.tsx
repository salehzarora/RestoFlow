import styles from './home.module.css';

/** One owner-managed photograph under the welcome, navigation and footer.
 * The existing hero media upload remains the only source of this URL. */
export function SceneBackdrop({ image }: { image: string | null }) {
  return <div className={styles.sceneBackdrop} aria-hidden="true">
    {image === null ? null : (
      /* eslint-disable-next-line @next/next/no-img-element */
      <img src={image} alt="" decoding="async" fetchPriority="high" />
    )}
  </div>;
}
