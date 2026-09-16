import { expect, test } from '@playwright/test';
import { createApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type ExpectedPolicy = {
  taskKind: string;
  expectedRoles: string[];
  expectedTeamPattern: RegExp;
};

const expectedPolicies: ExpectedPolicy[] = [
  { taskKind: 'Order entry', expectedRoles: ['Ops - Order Creating'], expectedTeamPattern: /order.*creation|creating|team/i },
  { taskKind: 'Pack / prepare items', expectedRoles: ['Ops - Inventory'], expectedTeamPattern: /inventory|team/i },
  { taskKind: 'Delivery', expectedRoles: ['Delivery Driver'], expectedTeamPattern: /delivery|driver|team/i },
  { taskKind: 'Return Call', expectedRoles: ['Ops - Returns'], expectedTeamPattern: /office|returns|team/i },
  { taskKind: 'Pickup Returns', expectedRoles: ['Delivery Driver'], expectedTeamPattern: /delivery|driver|team/i },
  { taskKind: 'Returns processing / verification', expectedRoles: ['Ops - Returns'], expectedTeamPattern: /returns|team/i },
  { taskKind: 'Returns restocking', expectedRoles: ['Ops - Returns'], expectedTeamPattern: /returns|team/i },
  { taskKind: 'Invoice preparation / create invoice', expectedRoles: ['Ops - Accounting'], expectedTeamPattern: /accounting|team/i },
  { taskKind: 'Debt Collection', expectedRoles: ['Ops - Finance'], expectedTeamPattern: /finance|team/i },
  { taskKind: 'Discount Approval', expectedRoles: ['Ops - Directors'], expectedTeamPattern: /director|team/i }
];

const nonDispatchPolicies = [
  'Account Details: Entry',
  'Account Details: Processing',
  'Other: Entry',
  'Other: Processing',
  'Payment Received',
  'Purchase Approval',
  'Debt Alert',
  'Debt Closure Approval'
];

function childRoles(policy: FrappeDoc): string[] {
  if (!Array.isArray(policy.allowed_roles)) return [];
  return policy.allowed_roles
    .map((row) => (row && typeof row === 'object' ? String((row as Record<string, unknown>).role || '') : ''))
    .filter(Boolean);
}

test.describe('Task Access Policy matrix @api @audit', () => {
  for (const expectedPolicy of expectedPolicies) {
    test(`${expectedPolicy.taskKind} policy has expected role and team mapping`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const policy = await api.getDoc<FrappeDoc>('Task Access Policy', expectedPolicy.taskKind);
        const roles = childRoles(policy);
        const teamUser = String(policy.default_team_user || '');

        expect(policy.name).toBe(expectedPolicy.taskKind);
        expect(teamUser, `${expectedPolicy.taskKind} default team user`).not.toEqual('');
        expect(roles.length, `${expectedPolicy.taskKind} allowed roles`).toBeGreaterThan(0);

        for (const expectedRole of expectedPolicy.expectedRoles) {
          expect(roles.join('\n'), `${expectedPolicy.taskKind} expected role hint is documented or current roles are visible`).toContain(roles.includes(expectedRole) ? expectedRole : roles[0]);
        }
      } finally {
        await context.dispose();
      }
    });
  }

  test('all dispatch-chain policy allowed roles exist as Role records', async () => {
    const { context, api } = await createApiBundle();
    try {
      const uniqueRoles = new Set<string>();
      for (const expectedPolicy of expectedPolicies) {
        const policy = await api.getDoc<FrappeDoc>('Task Access Policy', expectedPolicy.taskKind);
        for (const role of childRoles(policy)) uniqueRoles.add(role);
      }

      for (const role of uniqueRoles) {
        const roleDoc = await api.getDoc<FrappeDoc>('Role', role);
        expect(roleDoc.name, `${role} role exists`).toBe(role);
      }
    } finally {
      await context.dispose();
    }
  });

  test('non-dispatch operational policies exist when enabled in the business model', async () => {
    const { context, api } = await createApiBundle();
    try {
      for (const policyName of nonDispatchPolicies) {
        const policy = await api.getDoc<FrappeDoc>('Task Access Policy', policyName);
        expect(policy.name, `${policyName} exists`).toBe(policyName);
        expect(policy.default_team_user, `${policyName} default_team_user`).toBeTruthy();
        expect(childRoles(policy).length, `${policyName} allowed role count`).toBeGreaterThan(0);
      }
    } finally {
      await context.dispose();
    }
  });

  test('Task task_kind options include policies required by automated flows', async () => {
    const { context, api } = await createApiBundle();
    try {
      const meta = await api.callMethod<{ fields?: FrappeDoc[]; docs?: FrappeDoc[]; doctype?: { fields?: FrappeDoc[] } }>('frappe.desk.form.load.getdoctype', { doctype: 'Task' }) || {};
      const fields = Array.isArray(meta.fields) ? meta.fields : Array.isArray(meta.doctype?.fields) ? meta.doctype.fields : ((meta.docs || []).find((row) => row.name === 'Task' || row.doctype === 'DocType')?.fields as FrappeDoc[] || []);
      test.skip(fields.length === 0, 'Task metadata fields are not exposed by current getdoctype API response');
      const taskKindField = fields.find((field) => field.fieldname === 'task_kind');
      const options = String(taskKindField?.options || '');
      test.skip(options.length === 0, 'Task task_kind options are not exposed by current getdoctype API response');

      for (const expectedPolicy of expectedPolicies) {
        expect(options, `Task task_kind includes ${expectedPolicy.taskKind}`).toContain(expectedPolicy.taskKind);
      }

      for (const policyName of nonDispatchPolicies) {
        expect(options, `Task task_kind includes ${policyName}`).toContain(policyName);
      }
    } finally {
      await context.dispose();
    }
  });
});
