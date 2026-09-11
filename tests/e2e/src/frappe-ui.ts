import type { Page } from '@playwright/test';

export async function waitForFrappeFormReady(page: Page, doctype: string): Promise<void> {
  await page.waitForFunction(
    (expectedDoctype) => {
      const currentWindow = window as typeof window & { cur_frm?: { doctype?: string; doc?: { name?: string }; fields_dict?: Record<string, unknown> } };
      return Boolean(
        currentWindow.cur_frm &&
          currentWindow.cur_frm.doctype === expectedDoctype &&
          currentWindow.cur_frm.doc &&
          currentWindow.cur_frm.doc.name &&
          currentWindow.cur_frm.fields_dict
      );
    },
    doctype,
    { timeout: 15000 }
  );
}

export async function waitForSaveComplete(page: Page): Promise<void> {
  await Promise.race([
    page.locator('.indicator-pill:has-text("Saved")').waitFor({ state: 'visible', timeout: 15000 }),
    page.locator('.modal.show').waitFor({ state: 'visible', timeout: 15000 }),
    page.waitForLoadState('networkidle', { timeout: 15000 })
  ]);
}

export async function getFieldValue<T = unknown>(page: Page, fieldname: string): Promise<T> {
  return page.evaluate((name) => {
    const currentWindow = window as typeof window & { cur_frm?: { doc?: Record<string, unknown> } };
    return currentWindow.cur_frm?.doc?.[name];
  }, fieldname) as Promise<T>;
}

export async function isFieldVisible(page: Page, fieldname: string): Promise<boolean> {
  return page.evaluate((name) => {
    const currentWindow = window as typeof window & { cur_frm?: { fields_dict?: Record<string, { df?: { hidden?: boolean } }> } };
    const wrapper = document.querySelector(`[data-fieldname="${name}"]`) as HTMLElement | null;
    const field = currentWindow.cur_frm?.fields_dict?.[name];
    if (!wrapper || field?.df?.hidden) return false;

    const style = window.getComputedStyle(wrapper);
    const rect = wrapper.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  }, fieldname);
}

export async function isFieldReadOnly(page: Page, fieldname: string): Promise<boolean> {
  return page.evaluate((name) => {
    const currentWindow = window as typeof window & { cur_frm?: { fields_dict?: Record<string, { df?: { read_only?: boolean | number } }> } };
    return Boolean(currentWindow.cur_frm?.fields_dict?.[name]?.df?.read_only);
  }, fieldname);
}

export async function readDialogText(page: Page): Promise<string | null> {
  const dialog = page.locator('.modal.show').last();
  if (!(await dialog.count())) return null;
  return dialog.innerText();
}

export async function closeDialog(page: Page): Promise<void> {
  const dialog = page.locator('.modal.show').last();
  if (!(await dialog.count())) return;

  const primary = dialog.locator('.modal-footer .btn-primary').first();
  if (await primary.count()) {
    await primary.click();
    return;
  }

  await dialog.locator('.btn-modal-close, .close').first().click();
}
