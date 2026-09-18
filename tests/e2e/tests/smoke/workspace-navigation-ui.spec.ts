import { expect, test, type Browser, type Page } from '@playwright/test';
import { asRole } from '../../src/auth.js';
import { assertNoConsoleErrors } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';

type WorkspaceNavigationCase = {
  workspace: string;
  role: 'directors' | 'accounting' | 'inventory';
};

const workspaceNavigationCases: WorkspaceNavigationCase[] = [
  { workspace: 'Dispatch - Task Queues', role: 'directors' },
  { workspace: 'Management - KPI Dashboard', role: 'directors' }
];

async function openWorkspaceAsRole(browser: Browser, role: WorkspaceNavigationCase['role'], workspace: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/workspace/${encodeURIComponent(workspace)}`);
  await page.waitForLoadState('domcontentloaded');
  return page;
}

async function expectNoServerErrors(page: Page, networkEntries: { status?: number; url: string }[]): Promise<void> {
  await expect(page.locator('body')).toBeVisible();
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const metrics = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(metrics.scrollWidth, 'workspace horizontal overflow').toBeLessThanOrEqual(metrics.clientWidth + 2);
}

test.describe('Workspace navigation and usability @smoke', () => {
  for (const workspaceCase of workspaceNavigationCases) {
    test(`${workspaceCase.workspace} workspace route and layout are usable`, async ({ browser }) => {
      const page = await openWorkspaceAsRole(browser, workspaceCase.role, workspaceCase.workspace);
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('.page-title, .title-text, h3, h1').filter({ hasText: workspaceCase.workspace }).first()).toBeVisible({ timeout: 20000 });
      const mainContent = page.locator('.layout-main-section, .page-content, .workspace, .desk-page').first();
      await expect(mainContent).toBeVisible({ timeout: 20000 });
      const box = await mainContent.boundingBox();
      expect(box, `${workspaceCase.workspace} main content bounds`).not.toBeNull();
      if (box) {
        expect(box.width, `${workspaceCase.workspace} main content width`).toBeGreaterThan(20);
        expect(box.height, `${workspaceCase.workspace} main content height`).toBeGreaterThan(20);
      }
      await expectNoHorizontalOverflow(page);
      await expectNoServerErrors(page, networkEntries);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    });
  }

  test('workspace sidebar and page content remain reachable after reload', async ({ browser }) => {
    const page = await openWorkspaceAsRole(browser, 'directors', 'Dispatch - Task Queues');
    const consoleEntries = attachConsoleCapture(page);
    const networkEntries = attachNetworkCapture(page);

    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
    await expect(page).toHaveURL(/workspace\/Dispatch|workspace\/Dispatch%20-%20Task%20Queues/i);
    await expectNoHorizontalOverflow(page);
    await expectNoServerErrors(page, networkEntries);
    assertNoConsoleErrors(consoleEntries);
    await page.context().close();
  });
});
