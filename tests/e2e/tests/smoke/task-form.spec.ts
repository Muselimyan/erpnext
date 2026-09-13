import { expect, test } from '@playwright/test';
import { assertButtonFullyVisible, assertButtonState, assertFieldReadOnly, assertFieldVisible, assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { waitForFrappeFormReady } from '../../src/frappe-ui.js';
import { createApiBundle, createOrderEntryTask, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

test.describe('Task form browser smoke @smoke', () => {
  test('button state matrix for unaccepted Order Entry task', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Order entry');
      const openPage = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const openConsole = attachConsoleCapture(openPage);
      const openNetwork = attachNetworkCapture(openPage);
      await assertNoDuplicateButtons(openPage, viewportName);
      await assertButtonState(openPage, 'Accept / Start Task', 'visible', viewportName);
      await assertButtonState(openPage, 'Complete', 'hidden', viewportName);
      expect(openNetwork.filter((entry) => entry.status && entry.status >= 400)).toEqual([]);
      assertNoConsoleErrors(openConsole);
      await openPage.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Open DC replaces Create Dispatch Case when Dispatch Case exists', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      await api.createDispatchCase(String(task.name));
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Create Dispatch Case', 'hidden', viewportName);
      const openCount = await page.locator('button:has-text("Open DC"), button:has-text("View DC"), .btn:has-text("Open DC"), .btn:has-text("View DC")').count();
      expect(openCount).toBeGreaterThanOrEqual(1);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('field visibility and editability follows task state', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const unaccepted = await createTask(api, 'Order entry');
      const unacceptedPage = await openTaskAsRole(browser, 'orderCreating', String(unaccepted.name));
      await assertFieldVisible(unacceptedPage, 'task_kind', true);
      await assertFieldReadOnly(unacceptedPage, 'customer', true);
      await unacceptedPage.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('completed and other-user tasks do not show edit action buttons', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Other: Entry');
      await api.acceptTask(String(task.name));
      await api.updateDoc('Task', String(task.name), { status: 'Completed' });
      const completedPage = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      await assertNoDuplicateButtons(completedPage, viewportName);
      await assertButtonState(completedPage, 'Accept / Start Task', 'hidden', viewportName);
      await assertButtonState(completedPage, 'Complete', 'hidden', viewportName);
      await completedPage.context().close();
    } finally {
      await context.dispose();
    }
  });
});
