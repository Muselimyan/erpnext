import { expect, test } from '@playwright/test';
import { createRoleApiBundle, createTask, expectRejects, findPolicyTeam } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

test.describe('Task system invariants @api', () => {
  test('task kind reads Task Access Policy and assigns the default team', async () => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const team = await findPolicyTeam(api, 'Order entry');
      const task = await createTask(api, 'Order entry');
      const saved = await api.getDoc<FrappeDoc>('Task', String(task.name));
      expect(saved.task_access_policy || saved.task_kind).toBeTruthy();
      expect(saved.custom_assigned_to).toBe(team);
    } finally {
      await context.dispose();
    }
  });

  test('acceptance moves task to the accepting user and Working state', async () => {
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const task = await createTask(api, 'Order entry');
      await api.acceptTask(String(task.name));
      const accepted = await api.getDoc<FrappeDoc>('Task', String(task.name));
      expect(String(accepted.custom_accepted_by || '')).not.toEqual('');
      expect(accepted.status).toBe('Working');
    } finally {
      await context.dispose();
    }
  });

  test('non-accepted API user cannot reassign an accepted task through generic save', async () => {
    const owner = await createRoleApiBundle('orderCreating');
    const blocked = await createRoleApiBundle('delivery');
    try {
      const task = await createTask(owner.api, 'Order entry');
      await owner.api.acceptTask(String(task.name));
      const team = await findPolicyTeam(owner.api, 'Order entry');
      await expectRejects(() => blocked.api.updateDoc('Task', String(task.name), { custom_assigned_to: team }), /Accept|accepted|changes|permission|allowed/i);
      const unchanged = await owner.api.getDoc<FrappeDoc>('Task', String(task.name));
      expect(String(unchanged.custom_accepted_by || '')).not.toEqual('');
      expect(unchanged.status).toBe('Working');
    } finally {
      await blocked.context.dispose();
      await owner.context.dispose();
    }
  });

  test('completed tasks cannot be completed twice', async () => {
    const { context, api } = await createRoleApiBundle('orderAccepting');
    try {
      const task = await createTask(api, 'Other: Entry');
      await api.acceptTask(String(task.name));
      await api.updateDoc('Task', String(task.name), { status: 'Completed' });
      await expectRejects(() => api.updateDoc('Task', String(task.name), { status: 'Completed' }));
    } finally {
      await context.dispose();
    }
  });
});
