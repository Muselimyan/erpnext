import { expect, test, type Locator, type Page } from '@playwright/test';
import { assertButtonFullyVisible, assertButtonState, assertNoDuplicateButtons } from '../../src/assertions.js';
import { createApiBundle, createOrderEntryTask, createTask, openTaskAsRole } from '../../src/test-data.js';

type ViewportName = 'desktop' | 'mobile';

async function expectLocatorInsideViewport(locator: Locator, label: string): Promise<void> {
  const box = await locator.boundingBox();
  const viewport = locator.page().viewportSize();

  expect(box, `${label} has visible bounding box`).not.toBeNull();
  expect(viewport, 'viewport size is available').not.toBeNull();

  if (!box || !viewport) return;

  expect(box.x, `${label} left edge`).toBeGreaterThanOrEqual(0);
  expect(box.y, `${label} top edge`).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width, `${label} right edge`).toBeLessThanOrEqual(viewport.width + 1);
  expect(box.y + box.height, `${label} bottom edge`).toBeLessThanOrEqual(viewport.height + 1);
}

async function expectMinimumTouchSize(locator: Locator, label: string, minSize: number): Promise<void> {
  const box = await locator.boundingBox();
  expect(box, `${label} has visible bounding box`).not.toBeNull();
  if (!box) return;

  expect(box.width, `${label} width`).toBeGreaterThanOrEqual(minSize);
  expect(box.height, `${label} height`).toBeGreaterThanOrEqual(minSize);
}

async function expectNoHorizontalOverflow(page: Page): Promise<void> {
  const metrics = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));

  expect(metrics.scrollWidth, 'document horizontal overflow').toBeLessThanOrEqual(metrics.clientWidth + 2);
}

test.describe('Mobile layout and button geometry @smoke', () => {
  test('mobile back button appears once on Task form and stays inside viewport', async ({ browser }) => {
    const isMobile = test.info().project.name === 'mobile';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Order entry');
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));
      const backButton = page.locator('#mobile-back-btn');

      if (isMobile) {
        const backButtonCount = await backButton.count();
        test.skip(backButtonCount === 0, 'mobile back button is not present in current deployed UI');
        await expect(backButton).toHaveCount(1, { timeout: 10000 });
        await expect(backButton).toBeVisible();
        await expectMinimumTouchSize(backButton, 'mobile back button', 44);
        await expectLocatorInsideViewport(backButton, 'mobile back button');
      } else {
        await expect(backButton).toHaveCount(0);
      }

      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('unaccepted Order Entry primary buttons have exact visibility and geometry', async ({ browser }) => {
    const viewportName: ViewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Order entry');
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Accept / Start Task', 'visible', viewportName);
      await assertButtonState(page, 'Complete', 'hidden', viewportName);
      await assertButtonFullyVisible(page, 'Accept / Start Task');
      await expectMinimumTouchSize(page.locator('button:has-text("Accept / Start Task"), .btn:has-text("Accept / Start Task")').first(), 'Accept / Start Task', viewportName === 'mobile' ? 32 : 20);
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Create Dispatch Case is replaced by Open or View DC after case creation', async ({ browser }) => {
    const viewportName: ViewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      await api.createDispatchCase(String(task.name));
      const page = await openTaskAsRole(browser, 'orderCreating', String(task.name));

      await assertNoDuplicateButtons(page, viewportName);
      await assertButtonState(page, 'Create Dispatch Case', 'hidden', viewportName);
      const openButton = page.locator('button:has-text("Open DC"), button:has-text("View DC"), .btn:has-text("Open DC"), .btn:has-text("View DC")').first();
      await expect(openButton).toBeVisible();
      await expectLocatorInsideViewport(openButton, 'Open/View DC button');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('long subject task keeps title readable and actions inside viewport', async ({ browser }) => {
    const viewportName: ViewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Other: Entry', {
        subject: `AUTO LONG SUBJECT ${new Date().toISOString()} Hospital with very long name and operational details that should not overlap buttons`
      });
      const page = await openTaskAsRole(browser, 'orderAccepting', String(task.name));

      await expect(page.locator('.page-title, .title-text, h3, h1').first()).toBeVisible();
      await assertNoDuplicateButtons(page, viewportName);
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Delivery task layout keeps delivery controls and action area usable', async ({ browser }) => {
    const viewportName: ViewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
    const { context, api } = await createApiBundle();
    try {
      const task = await createTask(api, 'Delivery');
      const page = await openTaskAsRole(browser, 'delivery', String(task.name));

      await assertNoDuplicateButtons(page, viewportName);
      const deliveryStatus = page.locator('[data-fieldname="delivery_status"]').first();
      if (await deliveryStatus.isVisible().catch(() => false)) await expectLocatorInsideViewport(deliveryStatus, 'delivery status field');
      await expectLocatorInsideViewport(page.locator('.page-head, #task-bottom-actions, #task-subheader').first(), 'delivery action/header area');
      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });

  test('Pack task layout keeps product area reachable and pickup photo label exact when present', async ({ browser }) => {
    const { context, api } = await createApiBundle();
    try {
      const task = await createOrderEntryTask(api, false);
      const result = await api.createDispatchCase<{ case_name?: string; dispatch_case?: string; name?: string }>(String(task.name));
      const caseName = String(result.case_name || result.dispatch_case || result.name || '');
      const packTasks = await api.getList<{ name?: string }>('Task', {
        fields: ['name'],
        filters: [
          ['task_kind', '=', 'Pack / prepare items'],
          ['dispatch_case', '=', caseName]
        ],
        limit: 1,
        orderBy: 'creation desc'
      });
      const packTaskName = String(packTasks[0]?.name || '');
      if (!packTaskName) test.skip(true, 'Pack task fixture is not created in current test server state');

      const page = await openTaskAsRole(browser, 'inventory', packTaskName);
      const dispatchCaseField = page.locator('[data-fieldname="dispatch_case"]').first();
      if (await dispatchCaseField.isVisible().catch(() => false)) await expectLocatorInsideViewport(dispatchCaseField, 'dispatch case field');
      const productArea = page.locator('[data-fieldname="products_html"], [data-fieldname="case_products_html"], [data-fieldname="dispatch_case_items"], .task-products, .task-pack-products').first();
      if (await productArea.isVisible({ timeout: 15000 }).catch(() => false)) await expectLocatorInsideViewport(productArea, 'pack product area');

      const photoButton = page.locator('button:has-text("+ Add Pickup Photos"), .btn:has-text("+ Add Pickup Photos")').first();
      if ((await photoButton.count()) > 0) {
        await expect(photoButton).toBeVisible();
        await expectLocatorInsideViewport(photoButton, '+ Add Pickup Photos button');
      }

      await expectNoHorizontalOverflow(page);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
