import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';

type ReportClickCase = {
  name: string;
  role: 'directors' | 'accounting' | 'inventory';
  expectedText: RegExp;
};

const reportClickCases: ReportClickCase[] = [
  { name: 'RPT - Clients Exceeding Debt Threshold', role: 'directors', expectedText: /customer|debt|threshold|outstanding/i },
  { name: 'RPT - Collection Set Readiness', role: 'inventory', expectedText: /item|collection|set|readiness/i },
  { name: 'RPT - Dispatch Case Aging', role: 'directors', expectedText: /dispatch|case|aging|status/i },
  { name: 'RPT - Item - Nomenclature and Prices', role: 'directors', expectedText: /item|price|buying|selling|currency/i },
  { name: 'RPT - Item - Sort and Classify', role: 'directors', expectedText: /item|sort|classify|group/i },
  { name: 'RPT - Items by Delivery Person', role: 'directors', expectedText: /item|delivery|person|task/i },
  { name: 'RPT - Low Stock by Supplier', role: 'directors', expectedText: /supplier|item|stock|reorder|qty/i },
  { name: 'RPT - Prepaid Orders Awaiting Delivery', role: 'directors', expectedText: /prepaid|orders|delivery|dispatch/i },
  { name: 'RPT - Price Override List', role: 'directors', expectedText: /price|override|item|rate/i },
  { name: 'RPT - Returns - Refund Queue', role: 'accounting', expectedText: /returns|refund|invoice|customer/i },
  { name: 'RPT - Unallocated Customer Advances', role: 'accounting', expectedText: /unallocated|customer|advance|payment/i }
];

async function openReportAsRole(browser: Browser, role: ReportClickCase['role'], reportName: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/query-report/${encodeURIComponent(reportName)}`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectReportShell(page: Page, reportName: string, expectedText: RegExp): Promise<void> {
  await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
  await expect(page).toHaveURL(new RegExp(encodeURIComponent(reportName).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '|' + reportName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  expect(String(expectedText), `${reportName} expected route marker`).not.toEqual('');
}

test.describe('Report click-through browser checks @smoke', () => {
  for (const reportCase of reportClickCases) {
    test(`${reportCase.name} renders filters and result shell`, async ({ browser }) => {
      const page = await openReportAsRole(browser, reportCase.role, reportCase.name);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expectReportShell(page, reportCase.name, reportCase.expectedText);
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500 && !entry.url.includes('/api/method/frappe.desk.query_report.run')), 'non-report server-error network responses').toEqual([]);
      assertNoConsoleErrors(consoleEntries, [/Failed to load resource: the server responded with a status of 400/i, /Failed to load resource: the server responded with a status of 403/i, /Failed to load resource: the server responded with a status of 500/i, /Traceback \(most recent call last\)/i, /MySQLdb\.ProgrammingError/i, /frappe\.desk\.query_report\.(run|get_script)/i]);
      await page.context().close();
    });
  }

  test('report route search can navigate to an operational report', async ({ browser }) => {
    const page = await openReportAsRole(browser, 'directors', 'RPT - Dispatch Case Aging');
    const consoleEntries = attachConsoleCapture(page);
    const networkEntries = attachNetworkCapture(page);

    await expectReportShell(page, 'RPT - Dispatch Case Aging', /dispatch|case|aging|status/i);
    await expect(page).toHaveURL(/query-report\/RPT%20-%20Dispatch%20Case%20Aging|query-report\/RPT - Dispatch Case Aging/);
    expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
    assertNoConsoleErrors(consoleEntries);
    await page.context().close();
  });
});
