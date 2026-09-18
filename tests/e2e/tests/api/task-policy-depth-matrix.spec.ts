import { expect, test } from '@playwright/test';
import { createRoleApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type PolicyDepthCase = {
  taskKind: string;
  roles: string[];
  teamPattern: RegExp;
};

const policyDepthCases: PolicyDepthCase[] = [
  { taskKind: 'Order entry', roles: ['Ops - Order Creating'], teamPattern: /order|team|ops/i },
  { taskKind: 'Pack / prepare items', roles: ['Ops - Inventory'], teamPattern: /inventory|warehouse|team|ops/i },
  { taskKind: 'Delivery', roles: ['Delivery Driver'], teamPattern: /delivery|driver|team/i },
  { taskKind: 'Invoice preparation / create invoice', roles: ['Ops - Accounting'], teamPattern: /account|invoice|team|ops/i },
  { taskKind: 'Payment Received', roles: ['Ops - Accounting'], teamPattern: /account|payment|team|ops/i },
  { taskKind: 'Debt Collection', roles: ['Ops - Finance'], teamPattern: /finance|debt|team|ops/i },
  { taskKind: 'Debt Closure Approval', roles: ['Ops - Directors'], teamPattern: /director|approval|team|ops/i },
  { taskKind: 'Return Call', roles: ['Ops - Returns'], teamPattern: /return|team|ops/i },
  { taskKind: 'Pickup Returns', roles: ['Delivery Driver'], teamPattern: /delivery|return|driver|team/i },
  { taskKind: 'Returns processing / verification', roles: ['Ops - Returns'], teamPattern: /return|team|ops/i },
  { taskKind: 'Returns restocking', roles: ['Ops - Returns'], teamPattern: /return|team|ops/i },
  { taskKind: 'Purchase Approval', roles: ['Ops - Directors'], teamPattern: /director|approval|team|ops/i },
  { taskKind: 'Discount Approval', roles: ['Ops - Directors'], teamPattern: /director|approval|team|ops/i },
  { taskKind: 'Other: Entry', roles: ['Ops - Order Accepting'], teamPattern: /order|team|ops/i },
  { taskKind: 'Other: Processing', roles: ['Ops - Order Creating'], teamPattern: /order|team|ops/i },
  { taskKind: 'Account Details: Entry', roles: ['Ops - Order Accepting'], teamPattern: /order|account|team|ops/i },
  { taskKind: 'Account Details: Processing', roles: ['Ops - Accounting'], teamPattern: /account|team|ops/i },
  { taskKind: 'Debt Alert', roles: ['Ops - Directors'], teamPattern: /director|debt|team|ops/i }
];

function childValues(doc: FrappeDoc, fieldname: string): Record<string, unknown>[] {
  const value = doc[fieldname];
  return Array.isArray(value) ? value.filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object') : [];
}

test.describe('Task Access Policy depth matrix @api @audit', () => {
  for (const policyCase of policyDepthCases) {
    test(`${policyCase.taskKind} policy has expected roles and enabled team user`, async () => {
      const { context, api } = await createRoleApiBundle('directors');
      try {
        const policy = await api.getDoc<FrappeDoc>('Task Access Policy', policyCase.taskKind);
        const roles = childValues(policy, 'allowed_roles').map((row) => String(row.role || '')).filter(Boolean);
        const team = String(policy.default_team_user || '');
        expect(team, `${policyCase.taskKind} default team`).not.toEqual('');
        expect(roles.length, `${policyCase.taskKind} current allowed role rows`).toBeGreaterThan(0);
        for (const role of policyCase.roles) expect(roles, `${policyCase.taskKind} includes ${role}`).toContain(role);
        expect(team, `${policyCase.taskKind} team naming`).toMatch(policyCase.teamPattern);
      } finally {
        await context.dispose();
      }
    });
  }
});
