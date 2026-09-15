import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';

type ListNavigationCase = {
  doctype: string;
  role: 'directors' | 'accounting' | 'inventory' | 'orderCreating' | 'returns' | 'finance';
  expectedText: RegExp;
};

const listNavigationCases: ListNavigationCase[] = [
  { doctype: 'Task', role: 'directors', expectedText: /Task|Subject|Status|Assigned/i },
  { doctype: 'Dispatch Case', role: 'directors', expectedText: /Dispatch Case|Customer|Status/i },
  { doctype: 'Customer', role: 'orderCreating', expectedText: /Customer|Name|Group|Territory/i },
  { doctype: 'Item', role: 'inventory', expectedText: /Item|Code|Group|Stock/i },
  { doctype: 'Warehouse', role: 'inventory', expectedText: /Warehouse|Company|Group/i },
  { doctype: 'Stock Entry', role: 'inventory', expectedText: /Stock Entry|Purpose|Status/i },
  { doctype: 'Sales Invoice', role: 'accounting', expectedText: /Sales Invoice|Customer|Status|Grand Total/i },
  { doctype: 'Payment Entry', role: 'accounting', expectedText: /Payment Entry|Party|Status|Amount/i },
  { doctype: 'Purchase Order', role: 'directors', expectedText: /Purchase Order|Supplier|Status/i },
  { doctype: 'Purchase Receipt', role: 'inventory', expectedText: /Purchase Receipt|Supplier|Status/i },
  { doctype: 'Supplier', role: 'directors', expectedText: /Supplier|Name|Group/i },
  { doctype: 'Task Access Policy', role: 'directors', expectedText: /Task Access Policy|Task Kind|Default/i }
];

async function openListAsRole(browser: Browser, role: ListNavigationCase['role'], doctype: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/${doctype.toLowerCase().replace(/ /g, '-')}`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectListShell(page: Page, doctype: string, expectedText: RegExp): Promise<void> {
  await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
  await expect(page).toHaveURL(new RegExp(doctype.toLowerCase().replace(/ /g, '-')));
  expect(String(expectedText), `${doctype} expected navigation marker`).not.toEqual('');
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const metrics = await page.evaluate(() => ({ clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth }));
  expect(metrics.scrollWidth, 'list horizontal overflow').toBeLessThanOrEqual(metrics.clientWidth + 2);
}

test.describe('Desk list navigation smoke @smoke', () => {
  for (const listCase of listNavigationCases) {
    test(`${listCase.doctype} list opens with usable shell`, async ({ browser }) => {
      const page = await openListAsRole(browser, listCase.role, listCase.doctype);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expectListShell(page, listCase.doctype, listCase.expectedText);
      await expectNoHorizontalOverflow(page);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    });
  }
});
