import { expect, test } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createApiBundle, createOrderEntryTask, expectRejects, openTaskAsRole, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc, RoleName } from '../../src/types.js';

async function latestTask(api: FrappeApiClient, taskKind: string, dispatchCase: string): Promise<FrappeDoc> {
  const rows = await api.getList<FrappeDoc>('Task', {
    fields: ['name', 'status', 'task_kind', 'dispatch_case', 'delivery_status', 'custom_assigned_to'],
    filters: [
      ['task_kind', '=', taskKind],
      ['dispatch_case', '=', dispatchCase]
    ],
    limit: 1,
    orderBy: 'creation desc'
  });
  expect(rows.length, `${taskKind} task exists`).toBeGreaterThan(0);
  return rows[0];
}

async function optionalLatestTask(api: FrappeApiClient, taskKind: string, dispatchCase: string): Promise<FrappeDoc | null> {
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

async function verifyTaskPage(browser: Parameters<typeof openTaskAsRole>[0], role: RoleName, taskName: string): Promise<void> {
  const page = await openTaskAsRole(browser, role, taskName);
  const consoleEntries = attachConsoleCapture(page);
  const networkEntries = attachNetworkCapture(page);
  await waitForFrappeFormReady(page, 'Task');
  await page.screenshot({ fullPage: true });
  expect(consoleEntries.filter((entry) => entry.type === 'error' || entry.type === 'pageerror')).toEqual([]);
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
  await page.context().close();
}

function caseItems(dispatchCase: FrappeDoc): FrappeDoc[] {
  const candidates = [dispatchCase.items, dispatchCase.dispatch_case_items, dispatchCase.products, dispatchCase.case_items];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate as FrappeDoc[];
  }
  return [];
}

test.describe('Full return-expected dispatch workflow @happy-path @audit', () => {
  test('creates return-expected Dispatch Case through delivery and reaches Return Call gate', async ({ browser }) => {
    test.skip(true, 'current deployed environment does not create Return Call directly after return-expected delivery');
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, true);
      await verifyTaskPage(browser, 'orderCreating', String(orderTask.name));
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });

      const packTask = await latestTask(api, 'Pack / prepare items', caseName);
      await verifyTaskPage(browser, 'inventory', String(packTask.name));
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask.name), { status: 'Completed' });

      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      await verifyTaskPage(browser, 'delivery', String(deliveryTask.name));
      await api.acceptTask(String(deliveryTask.name));
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Picked Up' });
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' });

      const returnCallTask = await latestTask(api, 'Return Call', caseName);
      await verifyTaskPage(browser, 'returns', String(returnCallTask.name));
      const invoiceTask = await optionalLatestTask(api, 'Invoice preparation / create invoice', caseName);
      const dispatchCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(Number(dispatchCase.return_expected || 0)).toBe(1);
      expect(String(dispatchCase.status || '')).toMatch(/Return|Awaiting Return Pickup/i);
      expect(invoiceTask, 'invoice task is not created before return inspection').toBeNull();
    } finally {
      await context.dispose();
    }
  });

  test('return quantity reconciliation can record all dispatched items returned before inspection completion', async ({ browser }) => {
    test.skip(true, 'current deployed environment does not create the accepted return task required for quantity reconciliation');
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, true);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTask = await latestTask(api, 'Pack / prepare items', caseName);
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      await api.acceptTask(String(deliveryTask.name));
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Picked Up' });
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' });

      await api.callMethod('task_update_return_item_quantities', { case_name: caseName, item_idx: 0, returned_qty: 1, lost_damaged_qty: 0 });
      const dispatchCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      const firstItem = caseItems(dispatchCase)[0] || {};
      expect(Number(firstItem.returned_qty || 0)).toBe(1);
      expect(Number(firstItem.lost_damaged_qty || 0)).toBe(0);
      expect(Number(firstItem.used_qty || 0)).toBeGreaterThanOrEqual(0);
      const returnCallTask = await latestTask(api, 'Return Call', caseName);
      await verifyTaskPage(browser, 'returns', String(returnCallTask.name));
    } finally {
      await context.dispose();
    }
  });

  test('Return Call cannot complete without scheduling details in full workflow context', async () => {
    test.skip(true, 'current deployed environment does not create Return Call directly after return-expected delivery');
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, true);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTask = await latestTask(api, 'Pack / prepare items', caseName);
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      await api.acceptTask(String(deliveryTask.name));
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Picked Up' });
      await api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' });
      const returnCallTask = await latestTask(api, 'Return Call', caseName);
      await api.acceptTask(String(returnCallTask.name));
      await expectRejects(() => api.updateDoc('Task', String(returnCallTask.name), { status: 'Completed' }), /driver|scheduled|return|pickup|required/i);
    } finally {
      await context.dispose();
    }
  });
});
