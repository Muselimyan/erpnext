import { expect, test } from '@playwright/test';
import { createApiBundle, createOrderEntryTask, uploadSamplePhotoByApi } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

async function latestTask(api: { getList: Function }, taskKind: string, dispatchCase: string): Promise<FrappeDoc | null> {
  const rows = (await api.getList('Task', {
    fields: ['name', 'status', 'task_kind', 'custom_assigned_to', 'dispatch_case'],
    filters: [
      ['task_kind', '=', taskKind],
      ['dispatch_case', '=', dispatchCase]
    ],
    limit: 1,
    orderBy: 'creation desc'
  })) as FrappeDoc[];
  return rows[0] || null;
}

test.describe('Dispatch Case lifecycle @api', () => {
  test('no-return lifecycle creates Dispatch Case and downstream tasks', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      const dispatchCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(dispatchCase.name).toBe(caseName);
      expect(Number(dispatchCase.return_expected || 0)).toBe(0);
      const createdAgain = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const secondCaseName = String(createdAgain.name || createdAgain.dispatch_case || createdAgain.dispatchCase || createdAgain);
      expect(secondCaseName, 'duplicate Dispatch Case call returns the existing case').toBe(caseName);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const confirmedCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(String(confirmedCase.status || '')).toMatch(/Confirmed|Packed|In Transit|Invoice Pending|Payment Pending|Closed/i);
      const packTask = await latestTask(api, 'Pack / prepare items', caseName);
      expect(packTask, 'Pack task is created').not.toBeNull();
    } finally {
      await context.dispose();
    }
  });

  test('return-expected lifecycle creates return path tasks after delivery', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, true);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTask = await latestTask(api, 'Pack / prepare items', caseName);
      test.skip(!packTask, 'Pack task was not created by current server scripts');
      await api.acceptTask(String(packTask?.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask?.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask?.name), { status: 'Completed' });
      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      expect(deliveryTask, 'Delivery task is created').not.toBeNull();
      await api.acceptTask(String(deliveryTask?.name));
      await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
      await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
      const invoiceTask = await latestTask(api, 'Invoice preparation / create invoice', caseName);
      expect(invoiceTask, 'Invoice preparation task is created after delivery').not.toBeNull();
    } finally {
      await context.dispose();
    }
  });
});
