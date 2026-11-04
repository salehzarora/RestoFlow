import { preload } from 'react-dom';
import styles from './rubik.module.css';
import latin from './rubik-latin-var.woff2';
import arabic from './rubik-arabic-var.woff2';
import hebrew from './rubik-hebrew-var.woff2';

// Turbopack fingerprints these same source files for both CSS and resource
// hints. No generated filenames, origin, inline CSS, or duplicate font bytes.
const urls = {
  latin,
  arabic,
  hebrew,
};

export function preloadRubikLatin() {
  preload(urls.latin, { as: 'font', type: 'font/woff2', crossOrigin: 'anonymous' });
}

/** Called during server rendering; the third subset remains available on demand. */
export function rubikClass(script?: 'arabic' | 'hebrew') {
  preloadRubikLatin();
  if (script) preload(urls[script], { as: 'font', type: 'font/woff2', crossOrigin: 'anonymous' });
  return styles.variables;
}
