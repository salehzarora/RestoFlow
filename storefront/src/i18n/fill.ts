/**
 * Substitute `{name}` placeholders. An unknown placeholder is left verbatim so
 * a missing value is visible in review rather than silently rendering empty.
 */
export function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (whole, key: string) =>
    Object.prototype.hasOwnProperty.call(values, key) ? values[key] : whole,
  );
}
