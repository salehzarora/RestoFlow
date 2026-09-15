import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import '../globals.css';

// Root layout for `/`. The route group keeps the home route inside a layout while leaving app/layout.tsx absent, which is what makes the sibling locale layouts root layouts of their own.
export const metadata: Metadata = {
  title: 'BIZBOT',
  description: 'BIZBOT Storefront placeholder.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ar" dir="rtl">
      <body>{children}</body>
    </html>
  );
}
