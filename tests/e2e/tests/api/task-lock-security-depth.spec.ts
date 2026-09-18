import { expect, test } from '@playwright/test';
import { createRoleApiBundle, createTask, expectRejects, findPolicyTeam } from '../../src/test-data.js';
import type { FrappeDoc, RoleName } from '../../src/types.js';

type LockMutationCase = {
  taskKind: string;
  role: RoleName;
  fields: FrappeDoc;
  pattern: RegExp;
};

const unacceptedMutationCases: LockMutationCase[] = [
  { taskKind: 'Order entry', role: 'orderCreating', fields: { customer: 'SHOULD-NOT-SAVE' }, pattern: /accept|accepted|locked|permission|customer/i },
  { taskKind: 'Delivery', role: 'delivery', fields: { delivery_status: 'Delivered' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Pickup Returns', role: 'delivery', fields: { delivery_status: 'Picked Up' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Returns processing / verification', role: 'returns', fields: { custom_next_task_assign_to: 'returns.team@example.com' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Invoice preparation / create invoice', role: 'accounting', fields: { invoice_number: 'TEST' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Payment Received', role: 'accounting', fields: { new_payment_amount: 100, payment_method: 'Cash' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Debt Collection', role: 'finance', fields: { new_payment_amount: 100, payment_method: 'Cash' }, pattern: /accept|accepted|locked|permission|party|mandatory/i },
  { taskKind: 'Discount Approval', role: 'directors', fields: { approval_outcome: 'Approved' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Purchase Approval', role: 'directors', fields: { approval_outcome: 'Approved' }, pattern: /accept|accepted|locked|permission/i },
  { taskKind: 'Debt Closure Approval', role: 'directors', fields: { approval_outcome: 'Approved' }, pattern: /accept|accepted|locked|permission/i }
];

const completedMutationCases: LockMutationCase[] = [
  { taskKind: 'Other: Entry', role: 'orderAccepting', fields: { subject: 'AUTO MUTATION SHOULD BE BLOCKED' }, pattern: /completed|closed|locked|cannot/i },
  { taskKind: 'Payment Received', role: 'accounting', fields: { new_payment_amount: 200 }, pattern: /completed|closed|locked|cannot/i },
  { taskKind: 'Debt Collection', role: 'finance', fields: { payment_method: 'Cash' }, pattern: /completed|closed|locked|cannot/i },
  { taskKind: 'Discount Approval', role: 'directors', fields: { approval_outcome: 'Rejected' }, pattern: /completed|closed|locked|cannot/i }
];

test.describe('Task lock and security depth @api', () => {
  for (const mutationCase of unacceptedMutationCases) {
    test(`${mutationCase.taskKind} rejects workflow field mutation before acceptance`, async () => {
      const { context, api } = await createRoleApiBundle(mutationCase.role);
      try {
        const task = await createTask(api, mutationCase.taskKind);
        await expectRejects(() => api.updateDoc('Task', String(task.name), mutationCase.fields), mutationCase.pattern);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const mutationCase of completedMutationCases) {
    test(`${mutationCase.taskKind} rejects workflow mutation after completion`, async () => {
      const { context, api } = await createRoleApiBundle(mutationCase.role);
      try {
        const task = await createTask(api, mutationCase.taskKind, mutationCase.taskKind.includes('Approval') ? { approval_outcome: 'Approved' } : {});
        await api.acceptTask(String(task.name));
        await api.updateDoc('Task', String(task.name), { status: 'Completed' });
        await expectRejects(() => api.updateDoc('Task', String(task.name), mutationCase.fields), mutationCase.pattern);
      } finally {
        await context.dispose();
      }
    });
  }

  test('accepted task rejects reassignment from a non-accepted API session', async () => {
    const owner = await createRoleApiBundle('orderAccepting');
    const blocked = await createRoleApiBundle('orderCreating');
    try {
      const task = await createTask(owner.api, 'Other: Entry');
      await owner.api.acceptTask(String(task.name));
      const team = await findPolicyTeam(owner.api, 'Other: Entry');
      await expectRejects(() => blocked.api.updateDoc('Task', String(task.name), { custom_assigned_to: team }), /accept|accepted|locked|permission/i);
    } finally {
      await blocked.context.dispose();
      await owner.context.dispose();
    }
  });

  test('accepted task cannot be simultaneously reassigned and completed', async () => {
    const { context, api } = await createRoleApiBundle('orderAccepting');
    try {
      const task = await createTask(api, 'Other: Entry');
      await api.acceptTask(String(task.name));
      const team = await findPolicyTeam(api, 'Other: Entry');
      await expectRejects(() => api.updateDoc('Task', String(task.name), { custom_assigned_to: team, status: 'Completed' }), /reassign|complete|simultaneous|accept|accepted|locked/i);
    } finally {
      await context.dispose();
    }
  });

  test('cancelled task cannot be accepted again', async () => {
    const { context, api } = await createRoleApiBundle('orderAccepting');
    try {
      const task = await createTask(api, 'Other: Entry');
      await api.acceptTask(String(task.name));
      await api.updateDoc('Task', String(task.name), { status: 'Cancelled' });
      await expectRejects(() => api.acceptTask(String(task.name)), /cancelled|closed|status|cannot|open|working/i);
    } finally {
      await context.dispose();
    }
  });
});
