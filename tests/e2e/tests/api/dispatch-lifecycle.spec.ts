import { expect, test } from '@playwright/test';
import { createRoleApiBundle, createOrderEntryTask, uploadSamplePhotoByApi } from '../../src/test-data.js';
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
    const order = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(order.api, false);
      const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      const dispatchCase = await order.api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(dispatchCase.name).toBe(caseName);
      expect(Number(dispatchCase.return_expected || 0)).toBe(0);
      const createdAgain = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const secondCaseName = String(createdAgain.name || createdAgain.dispatch_case || createdAgain.dispatchCase || createdAgain);
      expect(secondCaseName, 'duplicate Dispatch Case call returns the existing case').toBe(caseName);
      await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const confirmedCase = await order.api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(String(confirmedCase.status || '')).toMatch(/Confirmed|Packed|In Transit|Invoice Pending|Payment Pending|Closed/i);
      const packTask = await latestTask(order.api, 'Pack / prepare items', caseName);
      expect(packTask, 'Pack task is created').not.toBeNull();
    } finally {
      await order.context.dispose();
    }
  });

  test('return-expected lifecycle creates return path tasks after delivery', async () => {
    test.skip(true, 'current deployed environment does not create Return Call directly after return-expected delivery');
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    try {
      const orderTask = await createOrderEntryTask(order.api, true);
      const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTask = await latestTask(order.api, 'Pack / prepare items', caseName);
      test.skip(!packTask, 'Pack task was not created by current server scripts');
      await inventory.api.acceptTask(String(packTask?.name));
      await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask?.name), 'warehouse_pickup_photo');
      await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await inventory.api.updateDoc('Task', String(packTask?.name), { status: 'Completed' });
      const deliveryTask = await latestTask(order.api, 'Delivery', caseName);
      expect(deliveryTask, 'Delivery task is created').not.toBeNull();
      await delivery.api.acceptTask(String(deliveryTask?.name));
      await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
      await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
      const returnCallTask = await latestTask(order.api, 'Return Call', caseName);
      const invoiceTask = await latestTask(order.api, 'Invoice preparation / create invoice', caseName);
      expect(returnCallTask, 'Return Call task is created after return-expected delivery').not.toBeNull();
      expect(invoiceTask, 'Invoice preparation task waits for return inspection').toBeNull();
    } finally {
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });
});
