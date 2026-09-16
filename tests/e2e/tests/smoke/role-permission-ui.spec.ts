import { expect, test, type Page } from '@playwright/test';
import { assertButtonState, assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { isFieldReadOnly, isFieldVisible } from '../../src/frappe-ui.js';
import { createApiBundle, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { RoleName } from '../../src/types.js';

type RolePermissionCase = {
  taskKind: string;
  role: RoleName;
  visibleFields: string[];
  forbiddenFields: string[];
};

const rolePermissionCases: RolePermissionCase[] = [
  { taskKind: 'Payment Received', role: 'accounting', visibleFields: ['task_kind'], forbiddenFields: ['delivery_status'] },
  { taskKind: 'Debt Collection', role: 'finance', visibleFields: ['task_kind'], forbiddenFields: ['delivery_status'] },
  { taskKind: 'Debt Closure Approval', role: 'directors', visibleFields: ['task_kind'], forbiddenFields: ['delivery_status'] },
  { taskKind: 'Discount Approval', role: 'directors', visibleFields: ['task_kind', 'approval_outcome'], forbiddenFields: ['delivery_status', 'payment_method'] },
  { taskKind: 'Delivery', role: 'delivery', visibleFields: ['task_kind'], forbiddenFields: ['new_payment_amount', 'payment_method', 'approval_outcome'] },
  { taskKind: 'Returns processing / verification', role: 'returns', visibleFields: ['task_kind'], forbiddenFields: ['new_payment_amount', 'payment_method', 'approval_outcome'] },
  { taskKind: 'Purchase Approval', role: 'directors', visibleFields: ['task_kind', 'approval_outcome'], forbiddenFields: ['delivery_status', 'payment_method'] },
  { taskKind: 'Order entry', role: 'orderCreating', visibleFields: ['task_kind'], forbiddenFields: ['delivery_status', 'payment_method'] }
];

async function expectNoServerErrors(page: Page, networkEntries: { status?: number; url: string }[]): Promise<void> {
  await expect(page.locator('body')).toBeVisible();
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
}

async function existingVisibleFields(page: Page, fields: string[]): Promise<string[]> {
  const visible: string[] = [];
  for (const field of fields) {
    if (await isFieldVisible(page, field)) visible.push(field);
  }
  return visible;
}

test.describe('Role-based task permission UI @smoke', () => {
  for (const permissionCase of rolePermissionCases) {
    test(`${permissionCase.taskKind} shows role-appropriate fields and no edit controls before accept`, async ({ browser }) => {
      const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
      const { context, api } = await createApiBundle();
      try {
        const task = await createTask(api, permissionCase.taskKind);
        const page = await openTaskAsRole(browser, permissionCase.role, String(task.name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await assertNoDuplicateButtons(page, viewportName);
        await assertButtonState(page, 'Complete', 'hidden', viewportName);

        await expect(page.locator('body')).toBeVisible({ timeout: 20000 });

        for (const field of permissionCase.forbiddenFields) {
          expect(await isFieldVisible(page, field), `${permissionCase.taskKind}.${field} hidden for ${permissionCase.role}`).toBe(false);
        }

        for (const field of permissionCase.visibleFields) {
          if (await isFieldVisible(page, field)) expect(await isFieldReadOnly(page, field), `${permissionCase.taskKind}.${field} read-only before accept`).toBe(true);
        }

        await expectNoServerErrors(page, networkEntries);
        assertNoConsoleErrors(consoleEntries);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  test('other role cannot see completion controls for an accepted Payment Received task', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Payment Received', { new_payment_amount: 100, payment_method: 'Cash' });
      await api.acceptTask(String(task.name));
      const page = await openTaskAsRole(browser, 'finance', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Complete', 'hidden', viewportName);
      if (await isFieldVisible(page, 'new_payment_amount')) expect(await isFieldReadOnly(page, 'new_payment_amount'), 'payment amount read-only for other role').toBe(true);
      if (await isFieldVisible(page, 'payment_method')) expect(await isFieldReadOnly(page, 'payment_method'), 'payment method read-only for other role').toBe(true);

      await expectNoServerErrors(page, networkEntries);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('other role cannot see approval controls for an accepted director approval task', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Debt Closure Approval', { approval_outcome: 'Approved' });
      await api.acceptTask(String(task.name));
      const page = await openTaskAsRole(browser, 'accounting', String(task.name));
      const consoleEntries = attachConsoleCapture(page);
      const networkEntries = attachNetworkCapture(page);

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Complete', 'hidden', viewportName);
      if (await isFieldVisible(page, 'approval_outcome')) expect(await isFieldReadOnly(page, 'approval_outcome'), 'approval outcome read-only for other role').toBe(true);

      await expectNoServerErrors(page, networkEntries);
      assertNoConsoleErrors(consoleEntries);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
