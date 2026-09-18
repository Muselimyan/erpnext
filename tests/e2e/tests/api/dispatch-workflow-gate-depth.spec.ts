import { expect, test } from '@playwright/test';
import { createRoleApiBundle, createOrderEntryTask, expectRejects, uploadSamplePhotoByApi, type ApiBundle } from '../../src/test-data.js';
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

async function createCaseWithPack(order: ApiBundle): Promise<{ caseName: string; packTask: FrappeDoc }> {
  const orderTask = await createOrderEntryTask(order.api, false);
  const caseName = await createCase(order.api, orderTask);
  const packTask = await completeOrderAndGetPack(order.api, caseName, orderTask);
  return { caseName, packTask };
}

test.describe('Dispatch workflow gate depth @api @audit', () => {
  test('Pack task cannot complete before acceptance even with case link', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    try {
      const { packTask } = await createCaseWithPack(order);
      await expectRejects(() => inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /accept|accepted|locked|permission/i);
    } finally {
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Pack task cannot complete with photo but without packed items', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    try {
      const { packTask } = await createCaseWithPack(order);
      await inventory.api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await expectRejects(() => inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /packed|items|required/i);
    } finally {
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Pack task cannot complete with packed item but without pickup photo', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    try {
      const { caseName, packTask } = await createCaseWithPack(order);
      await inventory.api.acceptTask(String(packTask.name));
      await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await expectRejects(() => inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' }), /photo|pickup|required/i);
    } finally {
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Delivery task cannot complete before delivery status is Delivered', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    try {
      const { caseName, packTask } = await createCaseWithPack(order);
      await inventory.api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(order.api, 'Delivery', caseName);
      expect(deliveryTask, 'delivery task exists').not.toBeNull();
      await delivery.api.acceptTask(String(deliveryTask?.name));
      await expectRejects(() => delivery.api.updateDoc('Task', String(deliveryTask?.name), { status: 'Completed' }), /delivery|delivered|status|required/i);
    } finally {
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Invoice task cannot complete without submitted invoice link', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    const delivery = await createRoleApiBundle('delivery');
    const accounting = await createRoleApiBundle('accounting');
    try {
      const { caseName, packTask } = await createCaseWithPack(order);
      await inventory.api.acceptTask(String(packTask.name));
      await uploadSamplePhotoByApi(inventory.context, 'Task', String(packTask.name), 'warehouse_pickup_photo');
      await inventory.api.markItemsPackedBatch(caseName, [0], 'Pack / prepare items');
      await inventory.api.updateDoc('Task', String(packTask.name), { status: 'Completed' });
      const deliveryTask = await latestTask(order.api, 'Delivery', caseName);
      await delivery.api.acceptTask(String(deliveryTask?.name));
      await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Picked Up' });
      await delivery.api.updateDoc('Task', String(deliveryTask?.name), { delivery_status: 'Delivered' });
      const invoiceTask = await latestTask(order.api, 'Invoice preparation / create invoice', caseName);
      expect(invoiceTask, 'invoice task exists').not.toBeNull();
      await accounting.api.acceptTask(String(invoiceTask?.name));
      await expectRejects(() => accounting.api.updateDoc('Task', String(invoiceTask?.name), { status: 'Completed' }), /invoice|submitted|sales invoice|required/i);
    } finally {
      await accounting.context.dispose();
      await delivery.context.dispose();
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('invoice task is not created before Pack and Delivery gates complete', async () => {
    const order = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(order.api, false);
      const caseName = await createCase(order.api, orderTask);
      const packTask = await completeOrderAndGetPack(order.api, caseName, orderTask);
      const invoiceTask = await latestTask(order.api, 'Invoice preparation / create invoice', caseName);
      expect(packTask, 'pack task exists before invoice path').not.toBeNull();
      expect(invoiceTask, 'invoice task waits for delivery gate completion').toBeNull();
    } finally {
      await order.context.dispose();
    }
  });
});
