/** Presentation adapter for cart/details/review only. Payment never enters it. */
import type { ReactNode } from 'react';
import type { Tenant } from '@/source/types';
import { buildSiteTheme, siteThemeClass } from '@/theme/buildSiteTheme';
import type { ThemeTokens } from '@/theme/buildTheme';
import { ThemeScope } from '../ThemeScope';
import shell from '../storefront.module.css';
import s from './journey.module.css';
import appearance from '../siteAppearance.module.css';

export function JourneyAppearance({ tenant, legacyTokens, dir, payment, children }: {
  tenant: Tenant; legacyTokens: ThemeTokens; dir: 'rtl' | 'ltr'; payment: boolean; children: ReactNode;
}) {
  if (payment) return <ThemeScope tokens={legacyTokens} className={shell.root} dir={dir}>{children}</ThemeScope>;
  return <ThemeScope tokens={buildSiteTheme(tenant, legacyTokens)} className={`${shell.root} ${appearance[siteThemeClass(tenant.siteTheme)]}`} dir={dir}>
    <div className={s.journey} data-sf-journey="mobile-ordering">{children}</div>
  </ThemeScope>;
}
