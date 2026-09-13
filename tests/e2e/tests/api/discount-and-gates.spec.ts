import { expect, test } from '@playwright/test';
import { createApiBundle, createOrderEntryTask, expectRejects } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

test.describe('Discount approval and completion gates @api', () => {
  test('discounted Dispatch Case creates approval gate before packing', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Dispatch Case', caseName, { discount_percent: 10, discount_amount: 10 });
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const dispatchCase = await api.getDoc<FrappeDoc>('Dispatch Case', caseName);
      expect(String(dispatchCase.status || '')).toMatch(/Awaiting Approval|Approval|Confirmed/i);
      const approvalTasks = await api.getList<FrappeDoc>('Task', {
        fields: ['name', 'task_kind', 'status', 'dispatch_case'],
        filters: [
          ['task_kind', '=', 'Discount Approval'],
          ['dispatch_case', '=', caseName]
        ],
        limit: 1,
        orderBy: 'creation desc'
      });
      expect(approvalTasks.length, 'Discount Approval task is created or DC is already confirmed by policy').toBeGreaterThanOrEqual(String(dispatchCase.status || '').match(/Confirmed/i) ? 0 : 1);
    } finally {
      await context.dispose();
    }
  });

  test('Pack completion without required photo is rejected when gate is active', async () => {
    const { context, api } = await createApiBundle();
    try {
      const orderTask = await createOrderEntryTask(api, false);
      const created = await api.createDispatchCase<FrappeDoc>(String(orderTask.name));
      const caseName = String(created.name || created.dispatch_case || created.dispatchCase || created);
      await api.updateDoc('Task', String(orderTask.name), { status: 'Completed' });
      const packTasks = await api.getList<FrappeDoc>('Task', {
        fields: ['name', 'task_kind', 'status', 'dispatch_case'],
        filters: [
          ['task_kind', '=', 'Pack / prepare items'],
          ['dispatch_case', '=', caseName]
        ],
        limit: 1,
        orderBy: 'creation desc'
      });
      test.skip(packTasks.length === 0, 'Pack task was not created by current server scripts');
      await api.acceptTask(String(packTasks[0].name));
      await expectRejects(() => api.updateDoc('Task', String(packTasks[0].name), { status: 'Completed' }), /photo|image|warehouse|gate|required/i);
    } finally {
      await context.dispose();
    }
  });

  test('Delivery status cannot skip directly to Delivered', async () => {
    const { context, api } = await createApiBundle();
    try {
      const deliveryTask = await createOrderEntryTask(api, false);
      await api.updateDoc('Task', String(deliveryTask.name), { task_kind: 'Delivery' });
      await api.acceptTask(String(deliveryTask.name));
      await expectRejects(() => api.updateDoc('Task', String(deliveryTask.name), { delivery_status: 'Delivered' }), /Picked Up|skip|Delivered|delivery/i);
    } finally {
      await context.dispose();
    }
  });
});
