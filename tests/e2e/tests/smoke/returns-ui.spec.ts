import { expect, test } from '@playwright/test';
import { attachConsoleCapture, attachNetworkCapture } from '../../src/capture.js';
import { assertNoDuplicateButtons } from '../../src/assertions.js';
import { createRoleApiBundle, createTask, openTaskAsRole } from '../../src/test-data.js';
import type { RoleName } from '../../src/types.js';

type ReturnsUiCase = {
  taskKind: string;
  role: RoleName;
};

const returnsUiCases: ReturnsUiCase[] = [
  {
    taskKind: 'Return Call',
    role: 'returns'
  },
  {
    taskKind: 'Pickup Returns',
    role: 'delivery'
  },
  {
    taskKind: 'Returns processing / verification',
    role: 'returns'
  },
  {
    taskKind: 'Returns restocking',
    role: 'returns'
  }
];

test.describe('Returns browser smoke @smoke', () => {
  for (const returnsCase of returnsUiCases) {
    test(`${returnsCase.taskKind} returns task opens cleanly`, async ({ browser }) => {
      const viewportName = test.info().project.name === 'mobile' ? 'mobile' : 'desktop';
      const { context, api } = await createRoleApiBundle(returnsCase.role);
      try {
        const task = await createTask(api, returnsCase.taskKind);
        const page = await openTaskAsRole(browser, returnsCase.role, String(task.name));
        const consoleEntries = attachConsoleCapture(page);
        const networkEntries = attachNetworkCapture(page);

        await assertNoDuplicateButtons(page, viewportName);
        await expect(page.locator('.title-text, .page-title, h3').first()).toBeVisible();

        expect(consoleEntries.filter((entry) => entry.type === 'error' || entry.type === 'pageerror')).toEqual([]);
        expect(networkEntries.filter((entry) => entry.status && entry.status >= 500)).toEqual([]);
        await page.context().close();
      } finally {
        await context.dispose();
      }
    });
  }

  test('Returns processing phone layout exposes compact or detailed return work area', async ({ browser }) => {
    const { context, api } = await createRoleApiBundle('returns');
    try {
      const task = await createTask(api, 'Returns processing / verification');
      const page = await openTaskAsRole(browser, 'returns', String(task.name));
      const compactTable = page.getByText('Ret?').first();
      const detailedToggle = page.getByText(/Use Detailed|Use Compact/).first();
      const returnInputs = page.getByText(/Returned Qty|Lost\/Damaged|Used|Sent/).first();
      const visibleCount = Number(await compactTable.count()) + Number(await detailedToggle.count()) + Number(await returnInputs.count());
      expect(visibleCount, 'return work area marker is visible').toBeGreaterThan(0);
      await page.context().close();
    } finally {
      await context.dispose();
    }
  });
});
