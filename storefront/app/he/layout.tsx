import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import { RequestHandoffProvider } from '@/ui/storefront/request/RequestHandoffProvider';
import '../globals.css';

// Root layout for /he. Sibling root layouts mean crossing between them is a full document load, which is expected for this shell.
export const metadata: Metadata = {
  title: 'BIZBOT',
  description: 'BIZBOT Storefront placeholder.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  // The D/E handoff provider lives in the root layout: it is the only thing that
  // stays mounted across the soft navigation from /s/:slug/review to /r/:ref.
  return (
    <html lang="he" dir="rtl">
      <body>
        <RequestHandoffProvider>{children}</RequestHandoffProvider>
      </body>
    </html>
  );
}
