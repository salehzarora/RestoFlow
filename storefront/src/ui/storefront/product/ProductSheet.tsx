'use client';

/**
 * PRODUCT SHEET - screen 4 of the approved handoff.
 *
 * TWO SEPARATE BOOLEANS, not one. This is the single most misread rule in the
 * screen, and the canonical screenshots settle it:
 *
 *   `blocked`   = some REQUIRED group has no selection. Live from the moment
 *                 the sheet opens: it greys the CTA and relabels it
 *                 "choose {group} to continue". G17 is named "configured" yet
 *                 already shows the grey, relabelled CTA with NO alert.
 *   `showError` = a submit has been ATTEMPTED and refused. Only this turns the
 *                 group badge red, renders the role="alert" bar, shakes it and
 *                 scrolls to the first unmet group. G18 is the proof.
 *
 * Collapsing them would make the sheet shout at a visitor who has not yet done
 * anything wrong. See prototype/Storefront.dc.html:807-810.
 *
 * PRICING. The price beside the name is the item's BASE price and never moves.
 * The live unit x quantity total lives on the CTA. Every figure is integer
 * minor units end to end; nothing here divides by 100.
 *
 * DIALOG SEMANTICS (`role="dialog" aria-modal="true"`, Esc, focus trap, focus
 * restore) come from COMPONENT_INVENTORY.md:114 and the execution packet. The
 * approved prototype implements NONE of the keyboard parts - they are an
 * addition this build makes deliberately, recorded in the Phase C report.
 */
import { useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import { MAX_NOTE, MAX_QTY, MIN_QTY, clampQty, unitPriceMinor } from '@/money/pricing';
import { sanitizeText } from '@/theme/sanitize';
import type { MenuItem, ModifierGroup, ModifierSelections, MotionMode } from '@/source/types';
import { AlertIcon, CheckIcon, CloseIcon, MinusIcon, PlusIcon } from '../icons';
import { TenantText } from '../TenantText';
import shell from '../storefront.module.css';
import styles from './product.module.css';

export interface SheetDraft {
  readonly qty: number;
  readonly selections: ModifierSelections;
  readonly note: string;
}

/** Required groups with nothing chosen, in display order. */
function unmetGroups(
  groups: readonly ModifierGroup[],
  selections: ModifierSelections,
): readonly ModifierGroup[] {
  return groups.filter((g) => g.required && (selections[g.id] ?? []).length === 0);
}

function badgeText(group: ModifierGroup, m: StorefrontMessages): string {
  const limit = group.max === undefined ? '' : ` · ${fill(m.upTo, { n: String(group.max) })}`;
  if (group.required) return group.single ? `${m.required} · ${m.chooseOne}` : `${m.required}${limit}`;
  return `${m.optional}${limit}`;
}

/**
 * "+₪5" for a paid option, "included" for a free one - never "+₪0". A REMOVAL
 * group shows nothing at all: "included" would be nonsense beside "no onion".
 */
function deltaText(group: ModifierGroup, deltaMinor: number, m: StorefrontMessages): string {
  if (deltaMinor > 0) return `+${formatMoney(deltaMinor)}`;
  return group.removal === true ? '' : m.included;
}

export function ProductSheet({
  item,
  groups,
  m,
  motion,
  initial,
  editing,
  onClose,
  onSubmit,
  onToast,
}: {
  item: MenuItem;
  groups: readonly ModifierGroup[];
  m: StorefrontMessages;
  motion: MotionMode;
  /** Pre-filled when editing an existing cart line. */
  initial?: SheetDraft;
  editing: boolean;
  onClose: () => void;
  onSubmit: (draft: SheetDraft) => void;
  onToast: (text: string) => void;
}) {
  const [selections, setSelections] = useState<ModifierSelections>(initial?.selections ?? {});
  const [qty, setQty] = useState(initial === undefined ? MIN_QTY : clampQty(initial.qty));
  const [note, setNote] = useState(initial?.note ?? '');
  const [showError, setShowError] = useState(false);

  const titleId = useId();
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const groupRefs = useRef(new Map<string, HTMLElement>());

  const unmet = useMemo(() => unmetGroups(groups, selections), [groups, selections]);
  const blocked = unmet.length > 0;
  const unitMinor = unitPriceMinor(item, groups, selections);
  const totalMinor = unitMinor * qty;

  // --- focus: trap inside the sheet, restore to the opener on close ---------
  useLayoutEffect(() => {
    const opener = document.activeElement;
    sheetRef.current?.focus();
    return () => {
      if (opener instanceof HTMLElement && opener.isConnected) opener.focus();
    };
  }, []);

  const onKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== 'Tab') return;
      const root = sheetRef.current;
      if (root === null) return;
      const focusable = Array.from(
        root.querySelectorAll<HTMLElement>('button, textarea, [href], [tabindex]:not([tabindex="-1"])'),
      ).filter((el) => !el.hasAttribute('disabled'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      const active = document.activeElement;
      if (event.shiftKey && (active === first || active === root)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    },
    [onClose],
  );

  // The page behind must not scroll while a modal sheet is open. A class, not
  // an inline style: see the .bodyLock comment in product.module.css.
  useEffect(() => {
    const { body } = document;
    body.classList.add(styles.bodyLock);
    return () => {
      body.classList.remove(styles.bodyLock);
    };
  }, []);

  // --- selection ------------------------------------------------------------
  /**
   * The cap is checked against the CURRENT state OUTSIDE the updater.
   *
   * `onToast` is a setState on the PARENT. Calling it from inside this
   * component's own updater means updating another component while this one is
   * rendering - React warns about exactly that, and under StrictMode the
   * updater runs twice, so the toast would fire twice as well. The updater must
   * stay a pure function of its input.
   */
  const toggle = useCallback(
    (group: ModifierGroup, optionId: string) => {
      const chosen = selections[group.id] ?? [];
      if (!group.single && !chosen.includes(optionId)) {
        if (group.max !== undefined && chosen.length >= group.max) {
          // At the cap the tap is REFUSED and answered with the approved toast.
          // The option stays operable on purpose: a disabled control would give
          // the visitor no explanation at all.
          onToast(fill(m.maxReached, { n: String(group.max) }));
          return;
        }
      }
      setSelections((current) => {
        const now = current[group.id] ?? [];
        if (group.single) return { ...current, [group.id]: [optionId] };
        if (now.includes(optionId)) {
          return { ...current, [group.id]: now.filter((id) => id !== optionId) };
        }
        if (group.max !== undefined && now.length >= group.max) return current;
        return { ...current, [group.id]: [...now, optionId] };
      });
    },
    [m.maxReached, onToast, selections],
  );

  const submit = useCallback(() => {
    if (blocked) {
      setShowError(true);
      const target = groupRefs.current.get(unmet[0].id);
      // 'auto', never 'instant': pre-2023 engines throw a TypeError on
      // 'instant', and 'auto' defers to the element's computed scroll-behavior,
      // which this module deliberately leaves at the initial value.
      target?.scrollIntoView({ block: 'center', behavior: 'auto' });
      return;
    }
    onSubmit({ qty, selections, note: sanitizeText(note, MAX_NOTE) });
  }, [blocked, note, onSubmit, qty, selections, unmet]);

  const ctaLabel = blocked
    ? fill(m.chooseToContinue, { g: unmet[0].name })
    : editing
      ? m.updateItem
      : m.addToCart;

  const motionClass = motion === 'calm' ? '' : motion === 'lively' ? styles.motionLively : styles.motionFull;

  return (
    <div className={`${styles.host} ${motionClass}`}>
      <button className={styles.scrim} type="button" aria-label={m.close} onClick={onClose} />

      {/* eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions */}
      <div
        className={styles.sheet}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        ref={sheetRef}
        onKeyDown={onKeyDown}
        data-sf-sheet="product"
      >
        <div className={styles.media}>
          {item.image === null ? (
            <span className={styles.mediaNone} aria-hidden="true">
              {item.name.trim().slice(0, 1)}
            </span>
          ) : (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img className={styles.mediaImg} src={item.image} alt="" decoding="async" />
          )}
          <span className={styles.mediaFade} aria-hidden="true" />
          <span className={styles.handle} aria-hidden="true" />
          <button className={styles.close} type="button" aria-label={m.close} onClick={onClose}>
            <CloseIcon />
          </button>
        </div>

        <div className={styles.body}>
          <div className={styles.head}>
            <div className={styles.nameRow}>
              <h2 className={styles.name} id={titleId}>
                <TenantText>{item.name}</TenantText>
              </h2>
              <span className={`${styles.basePrice} ${shell.ltr}`} dir="ltr">
                {formatMoney(item.priceMinor)}
              </span>
            </div>
            <p className={styles.desc}>
              <TenantText>{item.description}</TenantText>
            </p>
          </div>

          {groups.map((group) => {
            const chosen = selections[group.id] ?? [];
            const failed = showError && group.required && chosen.length === 0;
            const full = group.max !== undefined && chosen.length >= group.max;
            const headId = `${titleId}-g-${group.id}`;
            return (
              <section
                className={styles.group}
                key={group.id}
                data-sf-group={group.id}
                ref={(el) => {
                  if (el === null) groupRefs.current.delete(group.id);
                  else groupRefs.current.set(group.id, el);
                }}
              >
                <div className={styles.groupHead}>
                  <h3 className={styles.groupName} id={headId}>
                    <TenantText>{group.name}</TenantText>
                  </h3>
                  <span
                    className={`${styles.badge} ${
                      failed ? styles.badgeBad : group.required ? styles.badgeReq : styles.badgeOpt
                    }`}
                  >
                    {badgeText(group, m)}
                  </span>
                </div>

                {failed ? (
                  <p className={styles.alert} role="alert">
                    <AlertIcon />
                    {fill(m.requiredError, { g: group.name })}
                  </p>
                ) : null}

                <div
                  className={styles.options}
                  role={group.single ? 'radiogroup' : 'group'}
                  aria-labelledby={headId}
                >
                  {group.options.map((option) => {
                    const on = chosen.includes(option.id);
                    const delta = deltaText(group, option.priceDeltaMinor, m);
                    return (
                      <button
                        className={`${styles.option} ${on ? styles.optionOn : ''} ${
                          !on && full ? styles.optionFull : ''
                        }`}
                        key={option.id}
                        type="button"
                        role={group.single ? 'radio' : 'checkbox'}
                        aria-checked={on}
                        onClick={() => toggle(group, option.id)}
                      >
                        <span
                          className={`${styles.control} ${
                            group.single ? styles.controlRadio : styles.controlCheck
                          }`}
                          aria-hidden="true"
                        >
                          <CheckIcon />
                        </span>
                        <span className={styles.optionName}>
                          <TenantText>{option.name}</TenantText>
                        </span>
                        {delta === '' ? null : (
                          <span
                            className={`${styles.delta} ${
                              option.priceDeltaMinor > 0 ? '' : styles.deltaFree
                            } ${shell.ltr}`}
                            dir="ltr"
                          >
                            {delta}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              </section>
            );
          })}

          <div className={styles.note}>
            <label className={styles.noteHead} htmlFor={`${titleId}-note`}>
              <span className={styles.noteLabel}>{m.notes}</span>
              <span className={styles.noteOptional}>· {m.optional}</span>
            </label>
            <textarea
              className={styles.noteField}
              id={`${titleId}-note`}
              rows={2}
              maxLength={MAX_NOTE}
              placeholder={m.notesHint}
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>
        </div>

        <div className={styles.foot}>
          <div className={styles.stepper}>
            <button
              className={styles.step}
              type="button"
              aria-label={m.decrease}
              data-sf-step="dec"
              disabled={qty <= MIN_QTY}
              onClick={() => setQty((q) => clampQty(q - 1))}
            >
              <MinusIcon />
            </button>
            <span className={`${styles.stepValue} ${shell.ltr}`} dir="ltr" aria-live="polite">
              {qty}
            </span>
            <button
              className={`${styles.step} ${styles.stepPlus}`}
              type="button"
              aria-label={m.increase}
              data-sf-step="inc"
              disabled={qty >= MAX_QTY}
              onClick={() => setQty((q) => clampQty(q + 1))}
            >
              <PlusIcon />
            </button>
          </div>

          {/* Blocked, but NOT `disabled`: tapping it is how the visitor is told
              which group is missing (SCREEN_MAP.json:174). */}
          <button
            className={`${styles.cta} ${blocked ? styles.ctaBlocked : ''}`}
            type="button"
            aria-disabled={blocked}
            onClick={submit}
            data-sf-cta="product"
          >
            <span className={styles.ctaLabel}>{ctaLabel}</span>
            <span className={`${styles.ctaPrice} ${shell.ltr}`} dir="ltr">
              {formatMoney(totalMinor)}
            </span>
          </button>
        </div>
      </div>
    </div>
  );
}
