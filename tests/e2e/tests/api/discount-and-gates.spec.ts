import { expect, test } from '@playwright/test';
import { createRoleApiBundle, createOrderEntryTask, createTask, expectRejects } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

test.describe('Discount approval and completion gates @api', () => {
  test('discounted Dispatch Case creates approval gate before packing', async () => {
    const order = await createRoleApiBundle('orderCreating');
    try {
      const orderTask = await createOrderEntryTask(order.api, false);
      const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await order.api.updateDoc('Dispatch Case', caseName, { discount_percent: 10, discount_amount: 10 });
      await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const dispatchCase = await order.api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(String(dispatchCase.status || '')).toMatch(/Awaiting Approval|Approval/i);
      const approvalTasks = await order.api.getList<FrappeDoc>('Task', {
        fields: ['name', 'task_kind', 'status', 'dispatch_case'],
        filters: [
          ['task_kind', '=', 'Discount Approval'],
          ['dispatch_case', '=', caseName]
        ],
        limit: 1,
        orderBy: 'creation desc'
      });
      expect(approvalTasks.length, 'Discount Approval task is created before packing').toBeGreaterThan(0);
    } finally {
      await order.context.dispose();
    }
  });

  test('Pack completion without required photo is rejected when gate is active', async () => {
    const order = await createRoleApiBundle('orderCreating');
    const inventory = await createRoleApiBundle('inventory');
    try {
      const orderTask = await createOrderEntryTask(order.api, false);
      const created = await order.api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await order.api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTasks = await order.api.getList<FrappeDoc>('Task', {
        fields: ['name', 'task_kind', 'status', 'dispatch_case'],
        filters: [
          ['task_kind', '=', 'Pack / prepare items'],
          ['dispatch_case', '=', caseName]
        ],
        limit: 1,
        orderBy: 'creation desc'
      });
      test.skip(packTasks.length === 0, 'Pack task was not created by current server scripts');
      await inventory.api.acceptTask(String(packTasks[0].name));
      await expectRejects(() => inventory.api.updateDoc('Task', String(packTasks[0].name), { status: 'Completed' }), /photo|image|warehouse|gate|required/i);
    } finally {
      await inventory.context.dispose();
      await order.context.dispose();
    }
  });

  test('Delivery status cannot skip directly to Delivered', async () => {
    const delivery = await createRoleApiBundle('delivery');
    try {
      const deliveryTask = await createTask(delivery.api, 'Delivery');
      await delivery.api.acceptTask(String(deliveryTask.name));
      await expectRejects(() => delivery.api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' }), /Picked Up|skip|Delivered|delivery/i);
    } finally {
      await delivery.context.dispose();
    }
  });
});
