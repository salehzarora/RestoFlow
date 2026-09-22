import type { ReactNode } from 'react';
import type { Metadata } from 'next';
import { RequestHandoffProvider } from '@/ui/storefront/request/RequestHandoffProvider';
import '../globals.css';

// Root layout for `/`. The route group keeps the home route inside a layout while leaving app/layout.tsx absent, which is what makes the sibling locale layouts root layouts of their own.
export const metadata: Metadata = {
  title: 'BIZBOT',
  description: 'BIZBOT Storefront placeholder.',
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  // The D/E handoff provider lives in the root layout: it is the only thing that
  // stays mounted across the soft navigation from /s/:slug/review to /r/:ref.
  return (
    <html lang="ar" dir="rtl">
      {/* The font set is NOT bound here: sibling root layouts share one
          chunk group on the pinned toolchain, so anything a root layout imports
          is linked into every root's documents. It is bound one level down,
          per root - see src/fonts/README.md. */}
      <body>
        <RequestHandoffProvider>{children}</RequestHandoffProvider>
      </body>
    </html>
  );
}
