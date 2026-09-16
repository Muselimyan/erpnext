import { expect, test } from '@playwright/test';
import { createApiBundle, createOrderEntryTask, expectRejects, uploadSamplePhotoByApi } from '../../src/test-data.js';
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

async function createCase(api: { createDispatchCase: Function }, orderTask: FrappeDoc): Promise<string> {
  const created = (await api.createDispatchCase(String(orderTask.name))) as FrappeDoc;
  return String(created.name || created.dispatch_case || created.dispatchCase || created);
}

async function completeOrderAndGetPack(api: { updateDoc: Function; getList: Function }, caseName: string, orderTask: FrappeDoc): Promise<FrappeDoc> {
  await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
  const packTask = await latestTask(api, 'Pack / prepare items', caseName);
  expect(packTask, 'pack task exists').not.toBeNull();
  return packTask as FrappeDoc;
}

test.describe('Dispatch workflow gate depth @api @audit', () => {
  test('Pack task cannot complete before acceptance even with case link', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      await expectRejects(() => api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /accept|accepted|locked|permission/i);
    } finally {
      await context.dispose();
    }
  });

  test('Pack task cannot complete with photo but without packed items', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await expectRejects(() => api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /packed|items|required/i);
    } finally {
      await context.dispose();
    }
  });

  test('Pack task cannot complete with packed item but without pickup photo', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      await api.acceptTask(String(packTask.name));
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await expectRejects(() => api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /photo|pickup|required/i);
    } finally {
      await context.dispose();
    }
  });

  test('Delivery task cannot complete before delivery status is Delivered', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      expect(deliveryTask, 'delivery task exists').not.toBeNull();
      await api.acceptTask(String(deliveryTask?.name));
      await expectRejects(() => api.updateDoc('Task', String(deliveryTask?.name), { status: 'Completed' }), /delivery|delivered|status|required/i);
    } finally {
      await context.dispose();
    }
  });

  test('Invoice task cannot complete without submitted invoice link', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      await api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(api, 'Delivery', caseName);
      await api.acceptTask(String(deliveryTask?.name));
      await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
      await api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
      const invoiceTask = await latestTask(api, 'Invoice preparation / create invoice', caseName);
      expect(invoiceTask, 'invoice task exists').not.toBeNull();
      await api.acceptTask(String(invoiceTask?.name));
      await expectRejects(() => api.updateDoc('Task', String(invoiceTask?.name), { status: 'Completed' }), /invoice|submitted|sales invoice|required/i);
    } finally {
      await context.dispose();
    }
  });

  test('invoice task is not created before Pack and Delivery gates complete', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const caseName = await createCase(api, orderTask);
      const packTask = await completeOrderAndGetPack(api, caseName, orderTask);
      const invoiceTask = await latestTask(api, 'Invoice preparation / create invoice', caseName);
      expect(packTask, 'pack task exists before invoice path').not.toBeNull();
      expect(invoiceTask, 'invoice task waits for delivery gate completion').toBeNull();
    } finally {
      await context.dispose();
    }
  });
});
