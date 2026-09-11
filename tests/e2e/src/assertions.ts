import { expect, type Page } from '@playwright/test';
import { isFieldReadOnly, isFieldVisible } from './frappe-ui.js';
import type { ConsoleEntry } from './types.js';

type ViewportName = 'desktop' | 'mobile';
type ExpectedState = 'visible' | 'hidden' | 'enabled' | 'disabled';

const buttonTexts = ['Accept / Start Task', 'Complete', 'Create Dispatch Case', 'View DC', 'Open DC', 'Back', 'Refresh'];

export async function assertNoDuplicateButtons(page: Page, viewport: ViewportName): Promise<void> {
  const zones = viewport === 'mobile' ? ['#task-bottom-actions', '#task-subheader'] : ['.page-head'];

  for (const zone of zones) {
    for (const text of buttonTexts) {
      const count = await page.locator(`${zone} button:has-text("${text}"), ${zone} .btn:has-text("${text}")`).count();
      expect(count, `${text} appears ${count} times in ${zone}`).toBeLessThanOrEqual(1);
    }
  }
}

export async function assertButtonFullyVisible(page: Page, buttonText: string): Promise<void> {
  const button = page.locator(`button:has-text("${buttonText}"), .btn:has-text("${buttonText}")`).first();
  const box = await button.boundingBox();
  const viewport = page.viewportSize();

  expect(box, `${buttonText} has no visible bounding box`).not.toBeNull();
  expect(viewport, 'viewport size is unavailable').not.toBeNull();

  if (!box || !viewport) return;

  expect(box.width, `${buttonText} is too narrow`).toBeGreaterThanOrEqual(20);
  expect(box.height, `${buttonText} is too short`).toBeGreaterThanOrEqual(20);
  expect(box.x, `${buttonText} left edge is outside viewport`).toBeGreaterThanOrEqual(0);
  expect(box.y, `${buttonText} top edge is outside viewport`).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width, `${buttonText} right edge is outside viewport`).toBeLessThanOrEqual(viewport.width);
  expect(box.y + box.height, `${buttonText} bottom edge is outside viewport`).toBeLessThanOrEqual(viewport.height);
}

export async function assertButtonState(page: Page, buttonText: string, expected: ExpectedState, viewport: ViewportName): Promise<void> {
  const zones = viewport === 'mobile' ? ['#task-bottom-actions', '#task-subheader'] : ['.page-head'];
  const selector = zones.map((zone) => `${zone} button:has-text("${buttonText}"), ${zone} .btn:has-text("${buttonText}")`).join(', ');
  const button = page.locator(selector).first();

  if (expected === 'visible') await expect(button).toBeVisible();
  if (expected === 'hidden') await expect(button).toHaveCount(0);
  if (expected === 'enabled') await expect(button).toBeEnabled();
  if (expected === 'disabled') await expect(button).toBeDisabled();
}

export async function assertFieldVisible(page: Page, fieldname: string, expected: boolean): Promise<void> {
  expect(await isFieldVisible(page, fieldname), `${fieldname} visibility`).toBe(expected);
}

export async function assertFieldReadOnly(page: Page, fieldname: string, expected: boolean): Promise<void> {
  expect(await isFieldReadOnly(page, fieldname), `${fieldname} read-only state`).toBe(expected);
}

export function assertNoConsoleErrors(errors: ConsoleEntry[], allowlist: RegExp[] = []): void {
  const unexpected = errors.filter((entry) => entry.type === 'error' && !allowlist.some((pattern) => pattern.test(entry.text)));
  expect(unexpected, unexpected.map((entry) => entry.text).join('\n')).toEqual([]);
}
