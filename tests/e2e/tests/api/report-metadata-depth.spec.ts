import { expect, test } from '@playwright/test';
import { createApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type ReportDepthCase = {
  name: string;
  refDoctype: string;
  modulePattern: RegExp;
  roleHints: string[];
};

const reportDepthCases: ReportDepthCase[] = [
  { name: 'RPT - Clients Exceeding Debt Threshold', refDoctype: 'Customer', modulePattern: /selling|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Collection Set Readiness', refDoctype: 'Item', modulePattern: /stock|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Dispatch Case Aging', refDoctype: 'Dispatch Case', modulePattern: /custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Item - Nomenclature and Prices', refDoctype: 'Item', modulePattern: /stock|buying|selling|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Item - Sort and Classify', refDoctype: 'Item', modulePattern: /stock|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Items by Delivery Person', refDoctype: 'Task', modulePattern: /projects|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Low Stock by Supplier', refDoctype: 'Item', modulePattern: /stock|buying|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Prepaid Orders Awaiting Delivery', refDoctype: 'Dispatch Case', modulePattern: /custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Price Override List', refDoctype: 'Item Price', modulePattern: /stock|custom|erpnext/i, roleHints: ['Ops - Purchasing'] },
  { name: 'RPT - Returns - Refund Queue', refDoctype: 'Sales Invoice', modulePattern: /accounts|custom|erpnext/i, roleHints: ['Ops - Directors'] },
  { name: 'RPT - Unallocated Customer Advances', refDoctype: 'Payment Entry', modulePattern: /accounts|custom|erpnext/i, roleHints: ['Ops - Accounting'] }
];

function childValues(doc: FrappeDoc, fieldname: string): Record<string, unknown>[] {
  const value = doc[fieldname];
  return Array.isArray(value) ? value.filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object') : [];
}

test.describe('Report metadata depth @api @audit', () => {
  for (const reportCase of reportDepthCases) {
    test(`${reportCase.name} has runnable operational report metadata`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const report = await api.getDoc<FrappeDoc>('Report', reportCase.name);
        const roles = childValues(report, 'roles').map((row) => String(row.role || '')).filter(Boolean);
        expect(report.name).toBe(reportCase.name);
        expect(String(report.ref_doctype || ''), `${reportCase.name} ref_doctype`).toBe(reportCase.refDoctype);
        expect(String(report.module || ''), `${reportCase.name} module`).toMatch(reportCase.modulePattern);
        expect(String(report.report_type || ''), `${reportCase.name} report type`).toMatch(/Script Report|Query Report|Report Builder/i);
        expect(roles.length, `${reportCase.name} roles`).toBeGreaterThan(0);
        for (const role of reportCase.roleHints) expect(roles, `${reportCase.name} includes ${role}`).toContain(role);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const reportCase of reportDepthCases.slice(0, 8)) {
    test(`${reportCase.name} stores query definition metadata`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const report = await api.getDoc<FrappeDoc>('Report', reportCase.name);
        const queryText = String(report.query || report.json || report.javascript || report.name || '');
        expect(queryText.length, `${reportCase.name} query definition`).toBeGreaterThan(0);
        expect(queryText, `${reportCase.name} query labels`).toMatch(/name|item|customer|invoice|qty|amount|status|date|warehouse|supplier|dispatch|delivery/i);
      } finally {
        await context.dispose();
      }
    });
  }
});
