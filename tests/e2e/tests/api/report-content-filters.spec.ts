import { expect, test } from '@playwright/test';
import { createApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type ReportContentExpectation = {
  name: string;
  columns: RegExp[];
};

const reportContentExpectations: ReportContentExpectation[] = [
  { name: 'RPT - Clients Exceeding Debt Threshold', columns: [/customer/i, /debt|outstanding|threshold|amount/i] },
  { name: 'RPT - Collection Set Readiness', columns: [/item/i, /set|collection|status|ready/i] },
  { name: 'RPT - Dispatch Case Aging', columns: [/dispatch|case/i, /status|age|days|date/i] },
  { name: 'RPT - Item - Nomenclature and Prices', columns: [/item/i, /price|rate|currency/i] },
  { name: 'RPT - Item - Sort and Classify', columns: [/item/i, /group|class|sort|name/i] },
  { name: 'RPT - Items by Delivery Person', columns: [/item|task/i, /delivery|person|user|qty/i] },
  { name: 'RPT - Low Stock by Supplier', columns: [/supplier/i, /item/i, /qty|stock|reorder/i] },
  { name: 'RPT - Prepaid Orders Awaiting Delivery', columns: [/dispatch|case|customer/i, /delivery|status|prepaid|amount/i] },
  { name: 'RPT - Price Override List', columns: [/item/i, /price|rate|override/i] },
  { name: 'RPT - Returns - Refund Queue', columns: [/invoice|customer|return/i, /refund|amount|status/i] },
  { name: 'RPT - Unallocated Customer Advances', columns: [/customer|party/i, /advance|unallocated|amount/i] }
];

function reportText(report: FrappeDoc): string {
  return String(report.query || report.json || report.javascript || report.report_name || report.name || '');
}

test.describe('Report content and filters @api @audit', () => {
  for (const expectation of reportContentExpectations) {
    test(`${expectation.name} stores expected query definition family`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const report = await api.getDoc<FrappeDoc>('Report', expectation.name);
        const text = reportText(report);
        expect(text.length, `${expectation.name} report definition text`).toBeGreaterThan(0);
        for (const pattern of expectation.columns) {
          expect(text, `${expectation.name} has ${pattern}`).toMatch(pattern);
        }
      } finally {
        await context.dispose();
      }
    });
  }

  for (const expectation of reportContentExpectations) {
    test(`${expectation.name} report metadata has report type and role rows`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const report = await api.getDoc<FrappeDoc>('Report', expectation.name);
        const roles = Array.isArray(report.roles) ? report.roles : [];
        expect(String(report.report_type || ''), `${expectation.name} report type`).not.toEqual('');
        expect(roles.length, `${expectation.name} role rows`).toBeGreaterThan(0);
      } finally {
        await context.dispose();
      }
    });
  }

  test('core stock reports have stored query definitions', async () => {
    const { context, api } = await createApiBundle();
    try {
      const stockReports = reportContentExpectations.filter((report) => /Stock|Item|Collection|Price|Supplier/.test(report.name));
      for (const stockReport of stockReports) {
        const report = await api.getDoc<FrappeDoc>('Report', stockReport.name);
        expect(reportText(report).length, `${stockReport.name} query definition`).toBeGreaterThan(0);
      }
    } finally {
      await context.dispose();
    }
  });

  test('core finance reports have stored query definitions', async () => {
    const { context, api } = await createApiBundle();
    try {
      const financeReports = reportContentExpectations.filter((report) => /Debt|Advance|Refund|Returns/.test(report.name));
      for (const financeReport of financeReports) {
        const report = await api.getDoc<FrappeDoc>('Report', financeReport.name);
        expect(reportText(report).length, `${financeReport.name} query definition`).toBeGreaterThan(0);
      }
    } finally {
      await context.dispose();
    }
  });

  test('core operational reports have stored query definitions', async () => {
    const { context, api } = await createApiBundle();
    try {
      const operationalReports = reportContentExpectations.filter((report) => /Dispatch|Delivery/.test(report.name));
      for (const operationalReport of operationalReports) {
        const report = await api.getDoc<FrappeDoc>('Report', operationalReport.name);
        expect(reportText(report).length, `${operationalReport.name} query definition`).toBeGreaterThan(0);
      }
    } finally {
      await context.dispose();
    }
  });
});
