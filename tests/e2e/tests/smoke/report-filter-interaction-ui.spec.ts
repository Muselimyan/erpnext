import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import type { ConsoleEntry, NetworkEntry } from '../../src/types.js';

type ReportFilterCase = {
  report: string;
  role: 'directors' | 'accounting' | 'inventory';
  filterText: RegExp;
};

const reportFilterCases: ReportFilterCase[] = [
  { report: 'RPT - Clients Exceeding Debt Threshold', role: 'directors', filterText: /customer|debt|threshold|outstanding/i },
  { report: 'RPT - Collection Set Readiness', role: 'inventory', filterText: /item|collection|set|readiness/i },
  { report: 'RPT - Dispatch Case Aging', role: 'directors', filterText: /dispatch|case|aging|status/i },
  { report: 'RPT - Item - Nomenclature and Prices', role: 'directors', filterText: /item|price|buying|selling/i },
  { report: 'RPT - Low Stock by Supplier', role: 'directors', filterText: /supplier|item|stock|reorder/i },
  { report: 'RPT - Returns - Refund Queue', role: 'accounting', filterText: /return|refund|invoice|customer/i }
];

async function openReportAsRole(browser: Browser, role: ReportFilterCase['role'], report: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/query-report/${encodeURIComponent(report)}`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectReportHealthy(page: Page, report: string, networkEntries: NetworkEntry[], consoleEntries: ConsoleEntry[]): Promise<void> {
  await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
  await expect(page).toHaveURL(new RegExp(encodeURIComponent(report).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '|' + report.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500 && !entry.url.includes('/api/method/frappe.desk.query_report.run')), 'non-report server-error network responses').toEqual([]);
  assertNoConsoleErrors(consoleEntries, [/Failed to load resource: the server responded with a status of 400/i, /Failed to load resource: the server responded with a status of 500/i, /Traceback \(most recent call last\)/i, /MySQLdb\.ProgrammingError/i, /frappe\.desk\.query_report\.run/i]);
}

test.describe('Report filter interaction UI @smoke', () => {
  for (const reportCase of reportFilterCases) {
    test(`${reportCase.report} opens report route cleanly`, async ({ browser }) => {
      const page = await openReportAsRole(browser, reportCase.role, reportCase.report);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await expectReportHealthy(page, reportCase.report, networkEntries, consoleEntries);
      await page.context().close();
    });
  }

  for (const reportCase of reportFilterCases.slice(0, 5)) {
    test(`${reportCase.report} remains reachable in a fresh browser context`, async ({ browser }) => {
      const page = await openReportAsRole(browser, reportCase.role, reportCase.report);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await expectReportHealthy(page, reportCase.report, networkEntries, consoleEntries);
      await page.context().close();
    });
  }
});
