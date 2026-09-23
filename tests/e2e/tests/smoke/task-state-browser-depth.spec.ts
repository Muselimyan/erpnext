import { expect, test } from '@playwright/test';
import { assertButtonState, assertNoConsoleErrors, assertNoDuplicateButtons } from '../../src/assertions.js';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { isFieldReadOnly, isFieldVisible } from '../../src/frappe-ui.js';
import { createRoleApiBundle, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { ConsoleEntry, NetworkEntry, RoleName } from '../../src/types.js';

type TaskStateCase = {
  taskKind: string;
  role: RoleName;
  editableField: string;
};

const taskStateCases: TaskStateCase[] = [
  { taskKind: 'Order entry', role: 'orderCreating', editableField: 'customer' },
  { taskKind: 'Delivery', role: 'delivery', editableField: 'delivery_status' },
  { taskKind: 'Pickup Returns', role: 'delivery', editableField: 'delivery_status' },
  { taskKind: 'Returns processing / verification', role: 'returns', editableField: 'custom_next_task_assign_to' },
  { taskKind: 'Invoice preparation / create invoice', role: 'accounting', editableField: 'dispatch_case' },
  { taskKind: 'Payment Received', role: 'accounting', editableField: 'new_payment_amount' },
  { taskKind: 'Debt Collection', role: 'finance', editableField: 'new_payment_amount' },
  { taskKind: 'Debt Closure Approval', role: 'directors', editableField: 'approval_outcome' },
  { taskKind: 'Discount Approval', role: 'directors', editableField: 'approval_outcome' },
  { taskKind: 'Purchase Approval', role: 'directors', editableField: 'approval_outcome' },
  { taskKind: 'Other: Entry', role: 'orderAccepting', editableField: 'custom_next_task_assign_to' },
  { taskKind: 'Account Details: Processing', role: 'accounting', editableField: 'customer' }
];

const directlyCompletableTaskStateCases = taskStateCases.filter((taskCase) => !['Order entry', 'Delivery', 'Purchase Approval'].includes(taskCase.taskKind));

async function expectHealthyPage(networkEntries: NetworkEntry[], consoleEntries: ConsoleEntry[]): Promise<void> {
  expect(networkEntries.filter((entry) => entry.status && entry.status >= 500), 'server-error network responses').toEqual([]);
  assertNoConsoleErrors(consoleEntries);
}

test.describe('Task state browser depth @smoke', () => {
  for (const taskCase of taskStateCases) {
    test(`${taskCase.taskKind} unaccepted state hides completion and keeps workflow field read-only`, async ({ browser }) => {
      const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
      const { context, api } = await createRoleApiBundle(taskCase.role);
      try {
        const task = await createTask(api, taskCase.taskKind);
        const page = await openTaskAsRole(browser, taskCase.role, String(task.name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await assertNoDuplicateButtons(page, viewportName);
        await assertButtonState(page, 'Accept / Start Task', 'visible', viewportName);
        await assertButtonState(page, 'Complete', 'hidden', viewportName);
        expect(await isFieldVisible(page, taskCase.editableField), `${taskCase.editableField} visible before accept`).toBe(true);
        expect(await isFieldReadOnly(page, taskCase.editableField), `${taskCase.editableField} read-only before accept`).toBe(true);
        await expectHealthyPage(networkEntries, consoleEntries);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  for (const taskCase of directlyCompletableTaskStateCases) {
    test(`${taskCase.taskKind} completed state hides edit actions`, async ({ browser }) => {
      const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
      const { context, api } = await createRoleApiBundle(taskCase.role);
      try {
        const task = await createTask(api, taskCase.taskKind, taskCase.taskKind.includes('Approval') ? { approval_outcome: 'Approved' } : {});
        await api.acceptTask(String(task.name));
        await api.updateDoc('Task', String(task.name), { status: 'Completed' });
        const page = await openTaskAsRole(browser, taskCase.role, String(task.name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await assertNoDuplicateButtons(page, viewportName);
        await assertButtonState(page, 'Accept / Start Task', 'hidden', viewportName);
        await assertButtonState(page, 'Complete', 'hidden', viewportName);
        expect(await isFieldVisible(page, taskCase.editableField), `${taskCase.editableField} visible after completion`).toBe(true);
        expect(await isFieldReadOnly(page, taskCase.editableField), `${taskCase.editableField} read-only after completion`).toBe(true);
        await expectHealthyPage(networkEntries, consoleEntries);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }
});
