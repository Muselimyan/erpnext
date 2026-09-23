import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { createRoleApiBundle } from '../../src/test-data.js';

type FormLoadCase = {
  doctype: string;
  role: 'directors' | 'accounting' | 'inventory' | 'orderCreating' | 'returns' | 'finance';
  fields: string[];
  filters?: unknown[];
};

const formLoadCases: FormLoadCase[] = [
  { doctype: 'Customer', role: 'orderCreating', fields: ['name', 'customer_name'], filters: [['disabled', '=', 0]] },
  { doctype: 'Item', role: 'inventory', fields: ['name', 'item_code'], filters: [['disabled', '=', 0]] },
  { doctype: 'Warehouse', role: 'inventory', fields: ['name'], filters: [['disabled', '=', 0], ['is_group', '=', 0]] },
  { doctype: 'Supplier', role: 'directors', fields: ['name', 'supplier_name'], filters: [['disabled', '=', 0]] },
  { doctype: 'Purchase Order', role: 'directors', fields: ['name', 'supplier'] },
  { doctype: 'Purchase Receipt', role: 'inventory', fields: ['name', 'supplier'] },
  { doctype: 'Sales Invoice', role: 'accounting', fields: ['name', 'customer'] },
  { doctype: 'Payment Entry', role: 'accounting', fields: ['name', 'party'] },
  { doctype: 'Dispatch Case', role: 'directors', fields: ['name', 'customer'] },
  { doctype: 'Task', role: 'directors', fields: ['name', 'subject'] }
];

async function openFormAsRole(browser: Browser, role: FormLoadCase['role'], doctype: string, name: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/${doctype.toLowerCase().replace(/ /g, '-')}/${encodeURIComponent(name)}`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectFormShell(page: Page, doctype: string): Promise<void> {
  await expect(page.locator('.page-title, .title-text, h3, h1').first()).toBeVisible({ timeout: 20000 });
  await expect(page.locator('.layout-main-section, .form-layout, .form-page, .form-dashboard').first()).toBeVisible({ timeout: 20000 });
  await expect(page.locator('body')).toContainText(doctype, { timeout: 20000 });
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const metrics = await page.evaluate(() => ({ clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth }));
  expect(metrics.scrollWidth, 'form horizontal overflow').toBeLessThanOrEqual(metrics.clientWidth + 2);
}

test.describe('Master and transaction form load smoke @smoke', () => {
  for (const formCase of formLoadCases) {
    test(`${formCase.doctype} existing record opens cleanly`, async ({ browser }) => {
      const { context, api } = await createRoleApiBundle(formCase.role);
      try {
        const docs = await api.getList(formCase.doctype, { fields: formCase.fields, filters: formCase.filters, limit: 1, orderBy: 'modified desc' });
        if (!docs.length) test.skip(true, `${formCase.doctype} fixture is not present in current test data`);
        const page = await openFormAsRole(browser, formCase.role, formCase.doctype, String(docs[0].name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await expectFormShell(page, formCase.doctype);
        await expectNoHorizontalOverflow(page);
        expect(networkEntries.filter((entry) => entry.status && entry.status >= 500 && !entry.url.includes('/socket.io/')), 'server-error network responses').toEqual([]);
        assertNoConsoleErrors(consoleEntries);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }
});
