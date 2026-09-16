import { expect, test, type Page } from '@playwright/test';
import { assertButtonFullyVisible, assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { createApiBundle, createOrderEntryTask, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { RoleName } from '../../src/types.js';

type UiTaskCase = {
  taskKind: string;
  role: RoleName;
};

const uiTaskCases: UiTaskCase[] = [
  { taskKind: 'Order entry', role: 'orderCreating' },
  { taskKind: 'Other: Entry', role: 'orderAccepting' },
  { taskKind: 'Other: Processing', role: 'orderCreating' },
  { taskKind: 'Account Details: Entry', role: 'orderAccepting' },
  { taskKind: 'Account Details: Processing', role: 'accounting' },
  { taskKind: 'Payment Received', role: 'accounting' },
  { taskKind: 'Debt Alert', role: 'directors' },
  { taskKind: 'Debt Closure Approval', role: 'directors' }
];

const buttonLabels = ['Accept / Start Task', 'Complete', 'Create Dispatch Case', 'Open DC', 'View DC', 'Back', 'Refresh'];

async function visibleButtonLabels(page: Page): Promise<string[]> {
  const labels: string[] = [];
  for (const label of buttonLabels) {
    const count = await page.locator(`button:has-text("${label}"), .btn:has-text("${label}")`).count();
    if (count > 0) labels.push(label);
  }
  return labels;
}

test.describe('Task form UI matrix @smoke', () => {
  for (const taskCase of uiTaskCases) {
    test(`${taskCase.taskKind} form loads cleanly and keeps primary controls visible`, async ({ browser }) => {
      const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
      const { context, api } = await createApiBundle();
      try {
        const task = await createTask(api, taskCase.taskKind);
        const page = await openTaskAsRole(browser, taskCase.role, String(task.name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await expect(page.locator('.page-title, .title-text, h3, h1').first()).toBeVisible();
        await assertNoDuplicateButtons(page, viewportName);

        for (const label of await visibleButtonLabels(page)) {
          await assertButtonFullyVisible(page, label);
        }

        expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
        assertNoConsoleErrors(consoleEntries);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  test('accepted Order Entry with Dispatch Case keeps dispatch controls visible and usable', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      await api.createDispatchCase(String(task.name));
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await expect(page.locator('.page-title, .title-text, h3, h1').first()).toBeVisible();
      await assertNoDuplicateButtons(page, viewportName);
      const dispatchControlCount = await page.locator('button:has-text("Open DC"), button:has-text("View DC"), .btn:has-text("Open DC"), .btn:has-text("View DC")').count();
      expect(dispatchControlCount, 'accepted Order Entry dispatch control').toBeGreaterThanOrEqual(1);

      for (const label of await visibleButtonLabels(page)) {
        await assertButtonFullyVisible(page, label);
      }

      expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
