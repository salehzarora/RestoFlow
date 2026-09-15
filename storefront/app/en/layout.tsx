import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import '../globals.css';

// Root layout for /en. Sibling root layouts mean crossing between them is a full document load, which is expected for this shell.
export const metadata: Metadata = {
  title: 'BIZBOT',
  description: 'BIZBOT Storefront placeholder.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr">
      <body>{children}</body>
    </html>
  );
}
