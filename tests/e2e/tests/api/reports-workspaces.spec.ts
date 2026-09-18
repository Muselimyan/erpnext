import { expect, test } from '@playwright/test';
import { createRoleApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type ExpectedReport = {
  name: string;
  refDoctype: string;
  roleHints: string[];
};

const expectedReports: ExpectedReport[] = [
  { name: 'RPT - Clients Exceeding Debt Threshold', refDoctype: 'Customer', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Collection Set Readiness', refDoctype: 'Item', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Dispatch Case Aging', refDoctype: 'Dispatch Case', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Item - Nomenclature and Prices', refDoctype: 'Item', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Item - Sort and Classify', refDoctype: 'Item', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Items by Delivery Person', refDoctype: 'Task', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Low Stock by Supplier', refDoctype: 'Item', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Prepaid Orders Awaiting Delivery', refDoctype: 'Dispatch Case', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Price Override List', refDoctype: 'Item Price', roleHints: ['Ops - Purchasing'] },
  { name: 'RPT - Returns - Refund Queue', refDoctype: 'Sales Invoice', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Unallocated Customer Advances', refDoctype: 'Payment Entry', roleHints: ['Ops - Accounting'] }
];

const reportDuplicatePairs = [
  ['RPT - Clients Exceeding Debt Threshold'],
  ['RPT - Unallocated Customer Advances'],
  ['RPT - Dispatch Case Aging'],
  ['RPT - Prepaid Orders Awaiting Delivery']
];

const workspaceMetadataCases = [
  { workspace: 'Dispatch - Task Queues' },
  { workspace: 'Management - KPI Dashboard' }
];

function childValues(doc: FrappeDoc, fieldname: string): Record<string, unknown>[] {
  const value = doc[fieldname];
  return Array.isArray(value) ? value.filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object') : [];
}

test.describe('Reports and workspaces metadata @api @audit', () => {
  for (const expectedReport of expectedReports) {
    test(`${expectedReport.name} metadata matches expected reporting pack shape`, async () => {
      const { context, api } = await createRoleApiBundle('directors');
      try {
        const report = await api.getDoc<FrappeDoc>('Report', expectedReport.name);
        const roles = childValues(report, 'roles').map((row) => String(row.role || '')).filter(Boolean);

        expect(report.name).toBe(expectedReport.name);
        expect(report.ref_doctype, `${expectedReport.name} ref_doctype`).toBe(expectedReport.refDoctype);
        expect(report.report_type, `${expectedReport.name} report_type`).toBeTruthy();
        expect(roles.length, `${expectedReport.name} has role rows`).toBeGreaterThan(0);

        for (const roleHint of expectedReport.roleHints) {
          expect(roles, `${expectedReport.name} role includes ${roleHint}`).toContain(roleHint);
        }
      } finally {
        await context.dispose();
      }
    });
  }

  test('known duplicate report pairs remain explicit for colleague review', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      for (const pair of reportDuplicatePairs) {
        for (const reportName of pair) {
          const report = await api.getDoc<FrappeDoc>('Report', reportName);
          expect(report.name, `${reportName} duplicate/deferred report exists`).toBe(reportName);
        }
      }
    } finally {
      await context.dispose();
    }
  });

  for (const expectedWorkspace of workspaceMetadataCases) {
    test(`${expectedWorkspace.workspace} metadata is readable as a deployed workspace`, async () => {
      const { context, api } = await createRoleApiBundle('directors');
      try {
        const workspace = await api.getDoc<FrappeDoc>('Workspace', expectedWorkspace.workspace);
        expect(workspace.name).toBe(expectedWorkspace.workspace);
        expect(String(workspace.title || workspace.label || workspace.name || ''), `${expectedWorkspace.workspace} title metadata`).toContain(expectedWorkspace.workspace);
      } finally {
        await context.dispose();
      }
    });
  }

  test('Management KPI dashboard current skeleton state is visible in metadata', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const workspace = await api.getDoc<FrappeDoc>('Workspace', 'Management - KPI Dashboard');
      expect(childValues(workspace, 'charts').length, 'KPI dashboard chart count').toBe(0);
      expect(childValues(workspace, 'number_cards').length, 'KPI dashboard number card count').toBe(0);
      expect(childValues(workspace, 'links').length, 'KPI dashboard shortcut count').toBe(0);
    } finally {
      await context.dispose();
    }
  });
});
