import { expect, test, type Locator } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { asRole } from '../../src/auth.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createRoleApiBundle, createOrderEntryTask } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc } from '../../src/types.js';

async function expectInsideViewport(locator: Locator, label: string): Promise<void> {
  if (!(await locator.isVisible().catch(() => false))) return;
  const box = await locator.boundingBox();
  expect(box, `${label} bounding box`).not.toBeNull();
  if (!box) return;
  expect(box.x, `${label} left edge`).toBeGreaterThanOrEqual(-1);
  expect(box.x + box.width, `${label} right edge`).toBeLessThanOrEqual(430);
}

async function openDispatchCaseFromOrderTask(api: FrappeApiClient, taskName: string): Promise<string> {
  const created = await api.createDispatchCase<FrappeDoc>(taskName);
  return String(created.name || created.dispatch_case || created.dispatchCase || created);
}

test.describe('Dispatch Case item selection browser smoke @smoke', () => {
  test('Dispatch Case form opens with item table and template selector markers', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await openDispatchCaseFromOrderTask(api, String(orderTask.name));
      const browserContext = await asRole(browser, 'orderCreating');
      const page = await browserContext.newPage();
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);
      await page.goto(`/app/dispatch-case/${encodeURIComponent(caseName)}`);
      await waitForFrappeFormReady(page, 'Dispatch Case');

      await expect(page.locator('.title-text, .page-title, h3').first()).toBeVisible();
      const itemMarkers = await page.getByText(/Case Items|Items|Item Code|Dispatched Qty/i).count();
      expect(itemMarkers, 'Dispatch Case item table marker count').toBeGreaterThan(0);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await browserContext.close();
    } finally {
      await context.dispose();
    }
  });

  test('Dispatch Case Add Items by Category button is visible and inside viewport', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await openDispatchCaseFromOrderTask(api, String(orderTask.name));
      const browserContext = await asRole(browser, 'orderCreating');
      const page = await browserContext.newPage();
      await page.goto(`/app/dispatch-case/${encodeURIComponent(caseName)}`);
      await waitForFrappeFormReady(page, 'Dispatch Case');
      const button = page.getByText(/Add Items by Category/i).first();
      await expect(button).toBeVisible();
      await expectInsideViewport(button, 'Add Items by Category button');
      await browserContext.close();
    } finally {
      await context.dispose();
    }
  });

  test('Dispatch Case Search Add Item button is visible and inside viewport', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await openDispatchCaseFromOrderTask(api, String(orderTask.name));
      const browserContext = await asRole(browser, 'orderCreating');
      const page = await browserContext.newPage();
      await page.goto(`/app/dispatch-case/${encodeURIComponent(caseName)}`);
      await waitForFrappeFormReady(page, 'Dispatch Case');
      const button = page.getByText(/Search.*Add Item|Add Item/i).first();
      await expect(button).toBeVisible();
      await expectInsideViewport(button, 'Search Add Item button');
      await browserContext.close();
    } finally {
      await context.dispose();
    }
  });

  test('Dispatch Case template selector field stays reachable when rendered', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await openDispatchCaseFromOrderTask(api, String(orderTask.name));
      const browserContext = await asRole(browser, 'orderCreating');
      const page = await browserContext.newPage();
      await page.goto(`/app/dispatch-case/${encodeURIComponent(caseName)}`);
      await waitForFrappeFormReady(page, 'Dispatch Case');
      const selector = page.locator('[data-fieldname="custom_select_surgical_kit_template"]').first();
      await expect(selector).toBeVisible();
      await expectInsideViewport(selector, 'Surgical Kit Template selector');
      await browserContext.close();
    } finally {
      await context.dispose();
    }
  });
});
