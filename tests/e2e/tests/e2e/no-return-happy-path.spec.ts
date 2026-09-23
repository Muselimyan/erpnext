import { expect, test } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createRoleApiBundle, createOrderEntryTask, expectRejects, openTaskAsRole, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeDoc, RoleName } from '../../src/types.js';

async function latestTask(api: { getList<T extends FrappeDoc = FrappeDoc>(doctype: string, opts?: unknown): Promise<T[]> }, taskKind: string, dispatchCase: string): Promise<FrappeDoc> {
  const rows = await api.getList<FrappeDoc>('Task', {
    fields: ['name', 'status', 'task_kind', 'dispatch_case', 'custom_assigned_to'],
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

async function optionalLatestTask(api: { getList<T extends FrappeDoc = FrappeDoc>(doctype: string, opts?: unknown): Promise<T[]> }, taskKind: string, dispatchCase: string): Promise<FrappeDoc | null> {
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

function caseItems(dispatchCase: FrappeDoc): FrappeDoc[] {
  const candidates = [dispatchCase.items, dispatchCase.dispatch_case_items, dispatchCase.products, dispatchCase.case_items];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate as FrappeDoc[];
  }
  return [];
}

async function verifyTaskPage(browser: Parameters<typeof openTaskAsRole>[0], role: RoleName, taskName: string): Promise<void> {
  const page = await openTaskAsRole(browser, role, taskName);
  const consoleEntries = attachConsoleCapture(page);
  const networkEntries = attachNetworkCapture(page);
  await waitForFrappeFormReady(page, 'Task');
  await page.screenshot({ fullPage: true });
  expect(consoleEntries.filter((entry) => entry.type === 'error' || entry.type === 'pageerror')).toEqual([]);
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 400)).toEqual([]);
  await page.context().close();
}

test.describe('Full no-return dispatch happy path @happy-path', () => {
  test('creates a no-return Dispatch Case through delivery and reaches invoice gate', async ({ browser }) => {
    test.setTimeout(120_000);
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    const accounting = await createRoleApiBundle('accounting');
    try {
      const orderTask = await createOrderEntryTask(order.api, false);
      await verifyTaskPage(browser, 'orderCreating', String(orderTask.name));
      const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      expect(caseName).toMatch(/^DC-/);

      let dispatchCase = await order.api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(Number(dispatchCase.return_expected || 0), 'Dispatch Case is no-return').toBe(0);
      expect(caseItems(dispatchCase).length, 'Dispatch Case has product rows').toBeGreaterThan(0);
      expect(await optionalLatestTask(order.api, 'Return Call', caseName), 'no Return Call is created before Order Entry completion').toBeNull();

      await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTask = await latestTask(order.api, 'Pack / prepare items', caseName);
      expect(packTask.task_kind).toBe('Pack / prepare items');
      expect(packTask.dispatch_case).toBe(caseName);
      expect(String(packTask.status || ''), 'Pack task starts before completion').not.toBe('Completed');
      await verifyTaskPage(browser, 'inventory', String(packTask.name));
      await inventory.api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' });

      const deliveryTask = await latestTask(order.api, 'Delivery', caseName);
      expect(deliveryTask.task_kind).toBe('Delivery');
      expect(deliveryTask.dispatch_case).toBe(caseName);
      expect(String(deliveryTask.status || ''), 'Delivery task starts before completion').not.toBe('Completed');
      await verifyTaskPage(browser, 'delivery', String(deliveryTask.name));
      await delivery.api.acceptTask(String(deliveryTask.name));
      await delivery.api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Picked Up' });
      await delivery.api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' });

      const invoiceTask = await latestTask(order.api, 'Invoice preparation / create invoice', caseName);
      expect(invoiceTask.task_kind).toBe('Invoice preparation / create invoice');
      expect(invoiceTask.dispatch_case).toBe(caseName);
      expect(String(invoiceTask.status || ''), 'Invoice task starts before invoice-gate completion attempt').not.toBe('Completed');
      expect(await optionalLatestTask(order.api, 'Return Call', caseName), 'no Return Call is created for no-return flow').toBeNull();
      await verifyTaskPage(browser, 'accounting', String(invoiceTask.name));
      await accounting.api.acceptTask(String(invoiceTask.name));
      await expectRejects(() => accounting.api.updateDoc('Task', String(invoiceTask.name), { status: 'Completed' }), /Sales Invoice|invoice/i);
      dispatchCase = await order.api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(Number(dispatchCase.return_expected || 0), 'Dispatch Case remains no-return').toBe(0);
      expect(String(dispatchCase.status || '')).toMatch(/Invoice Pending|Payment Pending|Confirmed/i);
    } finally {
      await accounting.context.dispose();
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });
});
