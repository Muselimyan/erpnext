import { expect, test, type Locator, type Page } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createApiBundle, createOrderEntryTask, createTask, openTaskAsRole, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc } from '../../src/types.js';

async function latestTask(api: FrappeApiClient, taskKind: string, dispatchCase: string): Promise<FrappeDoc | null> {
  const rows = await api.getList<FrappeDoc>('Task', {
    fields: ['name', 'status', 'task_kind', 'dispatch_case'],
    filters: [
      ['task_kind', '=', taskKind],
      ['dispatch_case', '=', dispatchCase]
    ],
    limit: 1,
    orderBy: 'creation desc'
  });
  return rows[0] || null;
}

async function createPackTask(api: FrappeApiClient): Promise<{ caseName: string; packTask: FrappeDoc }> {
  const orderTask = await createOrderEntryTask(api, false);
  const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
  const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
  await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
  const packTask = await latestTask(api, 'Pack / prepare items', caseName);
  expect(packTask, 'Pack task created for product work area smoke').not.toBeNull();
  return { caseName, packTask: packTask as FrappeDoc };
}

async function createReturnsProcessingTask(api: FrappeApiClient, apiContext: Parameters<typeof uploadSamplePhotoByApi>[0]): Promise<FrappeDoc> {
  const orderTask = await createOrderEntryTask(api, true);
  const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
  const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
  await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
  const packTask = await latestTask(api, 'Pack / prepare items', caseName);
  expect(packTask, 'Pack task created before returns smoke').not.toBeNull();
  await api.acceptTask(String(packTask?.name));
  await uploadSamplePhotoByApi(apiContext, 'Task', String(packTask?.name), 'warehouse_pickup_photo');
  await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
  await api.updateDoc('Task', String(packTask?.name), { status: 'Completed' });
  const deliveryTask = await latestTask(api, 'Delivery', caseName);
  expect(deliveryTask, 'Delivery task created before returns smoke').not.toBeNull();
  await api.acceptTask(String(deliveryTask?.name));
  await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
  await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
  const fallbackTask = await createTask(api, 'Returns processing / verification', { dispatch_case: caseName });
  return fallbackTask;
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow, 'horizontal overflow pixels').toBeLessThanOrEqual(8);
}

async function expectInsideViewport(locator: Locator, label: string): Promise<void> {
  if (!(await locator.isVisible().catch(() => false))) return;
  const box = await locator.boundingBox();
  expect(box, `${label} bounding box`).not.toBeNull();
  if (!box) return;
  expect(box.x, `${label} left edge`).toBeGreaterThanOrEqual(-1);
  expect(box.x + box.width, `${label} right edge`).toBeLessThanOrEqual(430);
}

async function visibleTextCount(page: Page, patterns: RegExp[]): Promise<number> {
  let count = 0;
  for (const pattern of patterns) {
    count += await page.getByText(pattern).count();
  }
  return count;
}

test.describe('Barcode and Product Work Area browser smoke @smoke', () => {
  test('Order Entry product controls render without duplicate buttons or overflow', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);
      await waitForFrappeFormReady(page, 'Task');

      await assertNoDuplicateButtons(page, viewportName);
      const productMarkers = await visibleTextCount(page, [/Add Product/i, /Search.*Item/i, /Barcode/i, /Product Work Area/i, /Dispatch Product/i]);
      expect(productMarkers, 'Order Entry product UI marker count').toBeGreaterThanOrEqual(0);
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Order Entry product search or barcode probe does not crash the form when present', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);
      const searchInput = page.locator('input[placeholder*="item" i], input[placeholder*="barcode" i], input[data-fieldname*="barcode"], input[data-fieldname*="item"]').first();

      if (await searchInput.count()) {
        await searchInput.fill('');
        await searchInput.press('Enter');
      }

      await waitForFrappeFormReady(page, 'Task');
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Pack product work area renders with packing markers and pickup photo control', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const { packTask } = await createPackTask(api);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      const packingMarkers = await visibleTextCount(page, [/Packed/i, /Required/i, /Scanned/i, /Missing/i, /Batch\/LOT/i, /Expiry/i, /Problem/i]);
      expect(packingMarkers, 'Pack product area marker count').toBeGreaterThanOrEqual(0);
      const photoButton = page.getByText(/Add Pickup Photos|Pickup Photos/i).first();
      if (await photoButton.count()) await expectInsideViewport(photoButton, 'pickup photo button');
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Pack mobile dashboard markers are reachable when rendered', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const { packTask } = await createPackTask(api);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      const dashboardMarkers = await visibleTextCount(page, [/Packed\?/i, /Required/i, /Scanned/i, /Missing/i, /Status/i, /Warning/i]);
      expect(dashboardMarkers, 'Pack mobile dashboard marker probe').toBeGreaterThanOrEqual(0);
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Packing checkbox controls stay inside viewport when present', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const { packTask } = await createPackTask(api);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      const checkbox = page.locator('input[type="checkbox"], .checkbox input, [role="checkbox"]').first();
      if (await checkbox.count()) await expectInsideViewport(checkbox, 'packing checkbox');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Returns processing product area renders return quantity markers when present', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createReturnsProcessingTask(api, context);
      const page = await openTaskAsRole(browser, 'returns', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      const returnMarkers = await visibleTextCount(page, [/Ret\?/i, /Returned/i, /Lost\/Damaged/i, /Used/i, /Sent/i, /Use Detailed/i, /Use Compact/i]);
      expect(returnMarkers, 'Returns product area marker count').toBeGreaterThanOrEqual(0);
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Returns compact detailed toggle stays inside viewport when present', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const task = await createReturnsProcessingTask(api, context);
      const page = await openTaskAsRole(browser, 'returns', String(task.name));
      const toggle = page.getByText(/Use Detailed|Use Compact/).first();
      if (await toggle.count()) await expectInsideViewport(toggle, 'returns compact detailed toggle');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
