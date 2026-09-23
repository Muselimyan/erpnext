import { expect, test, type Locator, type Page } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createRoleApiBundle, createOrderEntryTask, createTask, openTaskAsRole, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { ApiBundle } from '../../src/test-data.js';
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

async function createPackTask(order: ApiBundle): Promise<{ caseName: string; packTask: FrappeDoc }> {
  const orderTask = await createOrderEntryTask(order.api, false);
  const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
  const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
  await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
  const packTask = await latestTask(order.api, 'Pack / prepare items', caseName);
  expect(packTask, 'Pack task created for product work area smoke').not.toBeNull();
  return { caseName, packTask: packTask as FrappeDoc };
}

async function createReturnsProcessingTask(order: ApiBundle, inventory: ApiBundle, delivery: ApiBundle, returns: ApiBundle): Promise<FrappeDoc> {
  const orderTask = await createOrderEntryTask(order.api, true);
  const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
  const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
  await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
  const packTask = await latestTask(order.api, 'Pack / prepare items', caseName);
  expect(packTask, 'Pack task created before returns smoke').not.toBeNull();
  await inventory.api.acceptTask(String(packTask?.name));
  await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask?.name), 'warehouse_pickup_photo');
  await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
  await inventory.api.updateDoc('Task', String(packTask?.name), { status: 'Completed' });
  const deliveryTask = await latestTask(order.api, 'Delivery', caseName);
  expect(deliveryTask, 'Delivery task created before returns smoke').not.toBeNull();
  await delivery.api.acceptTask(String(deliveryTask?.name));
  await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
  await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
  return createTask(returns.api, 'Returns processing / verification', { dispatch_case: caseName });
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow, 'horizontal overflow pixels').toBeLessThanOrEqual(8);
}

async function expectInsideViewport(locator: Locator, label: string): Promise<void> {
  await expect(locator, `${label} visible`).toBeVisible();
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
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const task = await createOrderEntryTask(api, false);
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);
      await waitForFrappeFormReady(page, 'Task');

      await assertNoDuplicateButtons(page, viewportName);
      const productMarkers = await visibleTextCount(page, [/Add Product/i, /Search.*Item/i, /Barcode/i, /Product Work Area/i, /Dispatch Product/i]);
      expect(productMarkers, 'Order Entry product UI marker count').toBeGreaterThan(0);
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Order Entry product search or barcode probe is usable without crashing the form', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const task = await createOrderEntryTask(api, false);
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);
      const searchInput = page.locator('input[placeholder*="item" i], input[placeholder*="barcode" i], input[data-fieldname*="barcode"], input[data-fieldname*="item"]').first();

      await expect(searchInput).toBeVisible();
      await searchInput.fill('');
      await searchInput.press('Enter');

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
    const order = await createRoleApiBundle('orderCreating');
    try {
      const { packTask } = await createPackTask(order);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      const packingMarkers = await visibleTextCount(page, [/Packed/i, /Required/i, /Scanned/i, /Missing/i, /Batch\/LOT/i, /Expiry/i, /Problem/i]);
      expect(packingMarkers, 'Pack product area marker count').toBeGreaterThan(0);
      await expectInsideViewport(page.getByText(/Add Pickup Photos|Pickup Photos/i).first(), 'pickup photo button');
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await order.context.dispose();
    }
  });

  test('Pack mobile dashboard markers are reachable when rendered', async ({ browser }) => {
    const order = await createRoleApiBundle('orderCreating');
    try {
      const { packTask } = await createPackTask(order);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      const dashboardMarkers = await visibleTextCount(page, [/Packed\?/i, /Required/i, /Scanned/i, /Missing/i, /Status/i, /Warning/i]);
      expect(dashboardMarkers, 'Pack mobile dashboard marker count').toBeGreaterThan(0);
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await order.context.dispose();
    }
  });

  test('Packing checkbox controls stay inside viewport', async ({ browser }) => {
    const order = await createRoleApiBundle('orderCreating');
    try {
      const { packTask } = await createPackTask(order);
      const page = await openTaskAsRole(browser, 'inventory', String(packTask.name));
      await expectInsideViewport(page.locator('input[type="checkbox"], .checkbox input, [role="checkbox"]').first(), 'packing checkbox');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await order.context.dispose();
    }
  });

  test('Returns processing product area renders return quantity markers', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    const returns = await createRoleApiBundle('returns');
    try {
      const task = await createReturnsProcessingTask(order, inventory, delivery, returns);
      const page = await openTaskAsRole(browser, 'returns', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      const returnMarkers = await visibleTextCount(page, [/Ret\?/i, /Returned/i, /Lost\/Damaged/i, /Used/i, /Sent/i, /Use Detailed/i, /Use Compact/i]);
      expect(returnMarkers, 'Returns product area marker count').toBeGreaterThan(0);
      await expectNoHorizontalOverflow(page);
      assertNoConsoleErrors(consoleEntries);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      await page.context().close();
    } finally {
      await returns.context.dispose();
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Returns compact detailed toggle stays inside viewport', async ({ browser }) => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    const returns = await createRoleApiBundle('returns');
    try {
      const task = await createReturnsProcessingTask(order, inventory, delivery, returns);
      const page = await openTaskAsRole(browser, 'returns', String(task.name));
      await expectInsideViewport(page.getByText(/Use Detailed|Use Compact/).first(), 'returns compact detailed toggle');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await returns.context.dispose();
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });
});
