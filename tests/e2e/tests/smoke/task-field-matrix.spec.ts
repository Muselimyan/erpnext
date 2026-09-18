import { expect, test, type Page } from '@playwright/test';
import { assertButtonState, assertNoDuplicateButtons } from '../../src/assertions.js';
import { isFieldReadOnly, isFieldVisible } from '../../src/frappe-ui.js';
import { createRoleApiBundle, createOrderEntryTask, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { RoleName } from '../../src/types.js';

type TaskFieldCase = {
  taskKind: string;
  role: RoleName;
  visibleFields: string[];
  hiddenFields: string[];
};

const fieldCases: TaskFieldCase[] = [
  {
    taskKind: 'Order entry',
    role: 'orderCreating',
    visibleFields: ['task_kind', 'custom_assigned_to'],
    hiddenFields: ['delivery_status', 'new_payment_amount', 'payment_method']
  },
  {
    taskKind: 'Delivery',
    role: 'delivery',
    visibleFields: ['task_kind', 'custom_assigned_to'],
    hiddenFields: ['new_payment_amount', 'payment_method', 'approval_outcome']
  },
  {
    taskKind: 'Pickup Returns',
    role: 'delivery',
    visibleFields: ['task_kind'],
    hiddenFields: ['new_payment_amount', 'payment_method', 'approval_outcome']
  },
  {
    taskKind: 'Returns processing / verification',
    role: 'returns',
    visibleFields: ['task_kind'],
    hiddenFields: ['new_payment_amount', 'payment_method', 'approval_outcome']
  },
  {
    taskKind: 'Invoice preparation / create invoice',
    role: 'accounting',
    visibleFields: ['task_kind', 'custom_assigned_to'],
    hiddenFields: ['delivery_status', 'new_payment_amount', 'payment_method']
  },
  {
    taskKind: 'Debt Collection',
    role: 'finance',
    visibleFields: ['task_kind'],
    hiddenFields: ['delivery_status', 'warehouse_pickup_photo', 'warehouse_dropoff_photo']
  },
  {
    taskKind: 'Payment Received',
    role: 'accounting',
    visibleFields: ['task_kind'],
    hiddenFields: ['delivery_status', 'warehouse_pickup_photo', 'warehouse_dropoff_photo']
  },
  {
    taskKind: 'Discount Approval',
    role: 'directors',
    visibleFields: ['task_kind', 'approval_outcome'],
    hiddenFields: ['delivery_status', 'new_payment_amount', 'payment_method']
  },
  {
    taskKind: 'Other: Entry',
    role: 'orderAccepting',
    visibleFields: ['task_kind', 'custom_next_task_assign_to', 'custom_assigned_to'],
    hiddenFields: ['delivery_status', 'new_payment_amount', 'payment_method']
  },
  {
    taskKind: 'Account Details: Entry',
    role: 'orderAccepting',
    visibleFields: ['task_kind', 'custom_assigned_to'],
    hiddenFields: ['delivery_status', 'new_payment_amount', 'payment_method']
  }
];

const readOnlyCheckFields = ['customer', 'warehouse', 'dispatch_case', 'delivery_status', 'new_payment_amount', 'payment_method', 'approval_outcome', 'custom_next_task_assign_to'];

async function visibleExistingFields(page: Page, fieldnames: string[]): Promise<string[]> {
  const result: string[] = [];
  for (const fieldname of fieldnames) {
    if (await isFieldVisible(page, fieldname)) result.push(fieldname);
  }
  return result;
}

test.describe('Task field visibility and editability matrix @smoke', () => {
  for (const fieldCase of fieldCases) {
    test(`${fieldCase.taskKind} field visibility follows configured matrix`, async ({ browser }) => {
      const { context, api } = await createRoleApiBundle(fieldCase.role);
      try {
        const task = await createTask(api, fieldCase.taskKind);
        const page = await openTaskAsRole(browser, fieldCase.role, String(task.name));

        await expect(page.locator('body')).toBeVisible({ timeout: 20000 });

        for (const fieldname of fieldCase.visibleFields) {
          expect(await isFieldVisible(page, fieldname), `${fieldCase.taskKind}.${fieldname} visible`).toBe(true);
        }

        for (const fieldname of fieldCase.hiddenFields) {
          expect(await isFieldVisible(page, fieldname), `${fieldCase.taskKind}.${fieldname} hidden`).toBe(false);
        }

        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  for (const fieldCase of fieldCases) {
    test(`${fieldCase.taskKind} unaccepted task keeps visible workflow fields read-only`, async ({ browser }) => {
      const { context, api } = await createRoleApiBundle(fieldCase.role);
      try {
        const task = await createTask(api, fieldCase.taskKind);
        const page = await openTaskAsRole(browser, fieldCase.role, String(task.name));
        const fieldsToCheck = await visibleExistingFields(page, readOnlyCheckFields);

        for (const fieldname of fieldsToCheck) {
          expect(await isFieldReadOnly(page, fieldname), `${fieldCase.taskKind}.${fieldname} read_only before accept`).toBe(true);
        }

        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  test('accepted Order Entry exposes Create Dispatch Case but keeps completion hidden before case link', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const task = await createOrderEntryTask(api, false);
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Complete', 'hidden', viewportName);
      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('browser role can accept an Order Entry task without breaking task controls', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createRoleApiBundle('orderCreating');
    try {
      const task = await createTask(api, 'Order entry');
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const acceptButton = page.locator('button:has-text("Accept / Start Task"), .btn:has-text("Accept / Start Task")').first();

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Accept / Start Task', 'visible', viewportName);
      await acceptButton.click();
      await expect(page.locator('body')).toBeVisible({ timeout: 20000 });
      await assertNoDuplicateButtons(page, viewportName);

      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('completed task hides action buttons and keeps workflow fields read-only', async ({ browser }) => {
    const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createRoleApiBundle('orderAccepting');
    try {
      const task = await createTask(api, 'Other: Entry');
      await api.acceptTask(String(task.name));
      await api.updateDoc('Task', String(task.name), { status: 'Completed' });
      const page = await openTaskAsRole(browser, 'orderAccepting', String(task.name));
      const fieldsToCheck = await visibleExistingFields(page, readOnlyCheckFields);

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Accept / Start Task', 'hidden', viewportName);
      await assertButtonState(page, 'Complete', 'hidden', viewportName);

      for (const fieldname of fieldsToCheck) {
        expect(await isFieldReadOnly(page, fieldname), `completed ${fieldname} read_only`).toBe(true);
      }

      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
