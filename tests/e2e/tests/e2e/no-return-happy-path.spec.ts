import { expect, test } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createApiBundle, createOrderEntryTask, expectRejects, openTaskAsRole, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeDoc, RoleName } from '../../src/types.js';

async function latestTask(api: { getList<T extends FrappeDoc = FrappeDoc>(doctype: string, opts?: unknown): Promise<T[]> }, taskKind: string, dispatchCase: string): Promise<FrappeDoc> {
  const rows = await api.getList<FrappeDoc>('Task', {
    fields: ['name', 'status', 'task_kind', 'dispatch_case'],
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
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
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
      const invoiceTask = await latestTask(api, 'Invoice preparation / create invoice', caseName);
      await verifyTaskPage(browser, 'accounting', String(invoiceTask.name));
      await api.acceptTask(String(invoiceTask.name));
      await expectRejects(() => api.updateDoc('Task', String(invoiceTask.name), { status: 'Completed' }), /Sales Invoice|invoice/i);
      const dispatchCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(String(dispatchCase.status || '')).toMatch(/Invoice Pending|Payment Pending|Confirmed/i);
    } finally {
      await context.dispose();
    }
  });
});
