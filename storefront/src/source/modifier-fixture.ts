/**
 * MODIFIER GROUPS — fixture layer only.
 *
 * Transcribed from the approved prototype's data
 * (prototype/storefront-data.js `GROUPS`), which is the authoritative shape:
 * every group id, option id and integer price delta matches it exactly.
 *
 * TWO OWNER-APPROVED NAME CORRECTIONS, and only these two. The prototype names
 * the sauce group "اختر الصوص" and the drink group "اختر المشروب" — each
 * already starting with the verb "اختر" (choose). The blocked CTA template is
 * `اختر {group} للمتابعة` and the inline alert is `يرجى اختيار {group}`, so
 * those names render as "اختر اختر الصوص للمتابعة" and "يرجى اختيار اختر
 * الصوص" — the doubling visible in the approved
 * screenshots/product__ar__dark__required-missing__390x844.png.
 * OPEN_QUESTIONS.md:13 records this and recommends the fix taken here:
 * "**Recommendation: rename the group**, because the inline alert above it has
 * the same doubling. No layout change either way."
 * So the groups are nouns: `الصوص` and `المشروب`. Nothing else changed.
 *
 * Deltas are INTEGER MINOR UNITS (agorot). A zero delta renders as the approved
 * "included" copy, except in a `removal` group where it renders blank.
 */
import type { ModifierGroup } from './types';

export const MODIFIER_GROUPS: readonly ModifierGroup[] = [
  {
    id: 'bun',
    name: 'نوع الخبز',
    required: true,
    single: true,
    options: [
      { id: 'classic', name: 'خبز كلاسيك', priceDeltaMinor: 0 },
      { id: 'brioche', name: 'بريوش', priceDeltaMinor: 500 },
      { id: 'lettuce', name: 'بدون خبز (لفّة خس)', priceDeltaMinor: 0 },
    ],
  },
  {
    id: 'extras',
    name: 'إضافات',
    required: false,
    single: false,
    max: 3,
    options: [
      { id: 'cheese', name: 'جبنة إضافية', priceDeltaMinor: 600 },
      { id: 'bacon', name: 'بيكون بقري', priceDeltaMinor: 800 },
      { id: 'egg', name: 'بيض', priceDeltaMinor: 500 },
      { id: 'jal', name: 'هالبينو', priceDeltaMinor: 300 },
      { id: 'avo', name: 'أفوكادو', priceDeltaMinor: 700 },
    ],
  },
  {
    id: 'remove',
    name: 'إزالة مكونات',
    required: false,
    single: false,
    removal: true,
    options: [
      { id: 'onion', name: 'بصل', priceDeltaMinor: 0 },
      { id: 'pickle', name: 'مخلل', priceDeltaMinor: 0 },
      { id: 'tomato', name: 'طماطم', priceDeltaMinor: 0 },
      { id: 'sauce', name: 'الصوص', priceDeltaMinor: 0 },
    ],
  },
  {
    // Prototype name: "اختر الصوص". Renamed to the noun per OPEN_QUESTIONS.md:13.
    id: 'sauce',
    name: 'الصوص',
    required: true,
    single: true,
    options: [
      { id: 'ketchup', name: 'كاتشب', priceDeltaMinor: 0 },
      { id: 'garlic', name: 'مايونيز ثوم', priceDeltaMinor: 0 },
      { id: 'bbq', name: 'باربكيو', priceDeltaMinor: 0 },
      { id: 'ranch', name: 'رانش', priceDeltaMinor: 200 },
    ],
  },
  {
    // Prototype name: "اختر المشروب". Renamed to the noun per OPEN_QUESTIONS.md:13.
    id: 'meal',
    name: 'المشروب',
    required: true,
    single: true,
    options: [
      { id: 'cola', name: 'كولا', priceDeltaMinor: 0 },
      { id: 'sprite', name: 'سبرايت', priceDeltaMinor: 0 },
      { id: 'water', name: 'ماء', priceDeltaMinor: 0 },
      { id: 'lemon', name: 'ليموناضة نعناع', priceDeltaMinor: 500 },
    ],
  },
];

const BY_ID: ReadonlyMap<string, ModifierGroup> = new Map(
  MODIFIER_GROUPS.map((g) => [g.id, g]),
);

export function findGroup(id: string): ModifierGroup | null {
  return BY_ID.get(id) ?? null;
}

/** The groups an item offers, in display order, skipping any unknown id. */
export function groupsFor(groupIds: readonly string[]): readonly ModifierGroup[] {
  const out: ModifierGroup[] = [];
  for (const id of groupIds) {
    const group = BY_ID.get(id);
    if (group !== undefined) out.push(group);
  }
  return out;
}

export const MODIFIER_GROUP_IDS: readonly string[] = MODIFIER_GROUPS.map((g) => g.id);
