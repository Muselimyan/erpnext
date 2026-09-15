import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';

type ReportCase = {
  name: string;
  role: 'directors' | 'accounting' | 'inventory';
};

type WorkspaceCase = {
  name: string;
  role: 'directors' | 'accounting' | 'inventory';
  labels: string[];
};

const reportCases: ReportCase[] = [
  { name: 'RPT - Dispatch Case Aging', role: 'directors' },
  { name: 'RPT - Clients Exceeding Debt Threshold', role: 'directors' },
  { name: 'RPT - Item - Nomenclature and Prices', role: 'directors' },
  { name: 'RPT - Low Stock by Supplier', role: 'directors' },
  { name: 'RPT - Returns - Refund Queue', role: 'accounting' }
];

const workspaceCases: WorkspaceCase[] = [
  { name: 'Dispatch - Task Queues', role: 'directors', labels: [] },
  { name: 'Management - KPI Dashboard', role: 'directors', labels: [] }
];

async function openPageAsRole(browser: Browser, role: ReportCase['role'], route: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(route);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectNoServerErrors(page: Page, networkEntries: { status?: number; url: string }[]): Promise<void> {
  await expect(page.locator('body')).toBeVisible();
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
}

test.describe('Reports and workspaces browser smoke @smoke', () => {
  for (const reportCase of reportCases) {
    test(`${reportCase.name} report opens in browser`, async ({ browser }) => {
      const page = await openPageAsRole(browser, reportCase.role, `/app/query-report/${encodeURIComponent(reportCase.name)}`);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await expect(page).toHaveURL(new RegExp(encodeURIComponent(reportCase.name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '|' + reportCase.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500 && !entry.url.includes('/api/method/frappe.desk.query_report.run')), 'non-report server-error network responses').toEqual([]);
      assertNoConsoleErrors(consoleEntries, [/Failed to load resource: the server responded with a status of 400/i, /Failed to load resource: the server responded with a status of 500/i, /Traceback \(most recent call last\)/i, /MySQLdb\.ProgrammingError/i, /frappe\.desk\.query_report\.run/i]);
      await page.context().close();
    });
  }

  for (const workspaceCase of workspaceCases) {
    test(`${workspaceCase.name} workspace opens and shows expected shortcuts`, async ({ browser }) => {
      const page = await openPageAsRole(browser, workspaceCase.role, `/app/workspace/${encodeURIComponent(workspaceCase.name)}`);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await expect(page).toHaveURL(/workspace/i);

      for (const label of workspaceCase.labels) {
        await expect(page.locator(`a:has-text("${label}"), .shortcut-widget-box:has-text("${label}"), .widget:has-text("${label}")`).first()).toBeVisible({ timeout: 20000 });
      }

      await expectNoServerErrors(page, networkEntries);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    });
  }
});
