import { expect, request, type APIRequestContext, type Browser, type Page } from '@playwright/test';
import { createReadStream } from 'node:fs';
import { resolve } from 'node:path';
import { asRole } from './auth.js';
import { FrappeApiClient } from './frappe-api.js';
import { waitForFrappeFormReady } from './frappe-ui.js';
import { getConfig } from './config.js';
import type { FrappeDoc, RoleName } from './types.js';

export type ApiBundle = {
  context: APIRequestContext;
  api: FrappeApiClient;
};

export async function createApiBundle(): Promise<ApiBundle> {
  const config = getConfig();
  const context = await request.newContext({
    baseURL: config.baseUrl,
    extraHTTPHeaders: {
      Authorization: `token ${config.apiKey}:${config.apiSecret}`
    }
  });
  return { context, api: new FrappeApiClient(context, config.baseUrl) };
}

export async function findFirstDoc(api: FrappeApiClient, doctype: string, fields: string[], filters?: unknown[]): Promise<FrappeDoc> {
  const docs = await api.getList(doctype, { fields, filters, limit: 1, orderBy: 'modified desc' });
  expect(docs.length, `${doctype} test fixture exists`).toBeGreaterThan(0);
  return docs[0];
}

export async function findPolicyTeam(api: FrappeApiClient, taskKind: string): Promise<string> {
  const policy = await api.getDoc<FrappeDoc>('Task Access Policy', taskKind);
  const team = String(policy.default_team_user || '');
  expect(team, `Task Access Policy ${taskKind} has default_team_user`).not.toEqual('');
  return team;
}

export async function findTestCustomer(api: FrappeApiClient): Promise<string> {
  const customer = await findFirstDoc(api, 'Customer', ['name'], [['disabled', '=', 0]]);
  return String(customer.name);
}

export async function findTestItem(api: FrappeApiClient): Promise<string> {
  const item = await findFirstDoc(api, 'Item', ['name', 'item_code'], [['disabled', '=', 0], ['is_stock_item', '=', 1]]);
  return String(item.item_code || item.name);
}

export async function findTestWarehouse(api: FrappeApiClient): Promise<string> {
  const warehouse = await findFirstDoc(api, 'Warehouse', ['name'], [['disabled', '=', 0], ['is_group', '=', 0]]);
  return String(warehouse.name);
}

export async function createTask(api: FrappeApiClient, taskKind: string, overrides: FrappeDoc = {}): Promise<FrappeDoc> {
  const assignedTo = String(overrides.custom_assigned_to || (await findPolicyTeam(api, taskKind)));
  const subject = `AUTO ${taskKind} ${new Date().toISOString()}`;
  return api.createDoc('Task', {
    doctype: 'Task',
    subject,
    task_kind: taskKind,
    status: 'Open',
    custom_assigned_to: assignedTo,
    ...overrides
  });
}

export async function createOrderEntryTask(api: FrappeApiClient, returnExpected = false): Promise<FrappeDoc> {
  const customer = await findTestCustomer(api);
  const item = await findTestItem(api);
  const warehouse = await findTestWarehouse(api);
  const task = await createTask(api, 'Order entry', { customer, warehouse, return_expected: returnExpected ? 1 : 0 });
  await api.acceptTask(String(task.name));
  await api.addProduct(String(task.name), item, 1, 100);
  return api.getDoc('Task', String(task.name));
}

export async function expectRejects(action: () => Promise<unknown>, messagePattern?: RegExp): Promise<void> {
  let failed = false;
  try {
    await action();
  } catch (error) {
    failed = true;
    if (messagePattern) expect(String(error), messagePattern.source).toMatch(messagePattern);
  }
  expect(failed, 'operation should be rejected').toBe(true);
}

export async function openTaskAsRole(browser: Browser, role: RoleName, taskName: string): Promise<Page> {
  const context = await asRole(browser, role);
  const page = await context.newPage();
  await page.goto(`/app/task/${encodeURIComponent(taskName)}`);
  await waitForFrappeFormReady(page, 'Task');
  return page;
}

export async function uploadSamplePhoto(page: Page, fieldname: string): Promise<void> {
  const chooserPromise = page.waitForEvent('filechooser');
  await page.locator(`[data-fieldname="${fieldname}"] button, [data-fieldname="${fieldname}"] .btn`).first().click();
  const chooser = await chooserPromise;
  await chooser.setFiles(resolve(process.cwd(), 'fixtures', 'sample-photo.png'));
}

export async function uploadSamplePhotoByApi(apiContext: APIRequestContext, doctype: string, docname: string, fieldname: string): Promise<void> {
  await apiContext.post('/api/method/upload_file', {
    multipart: {
      doctype,
      docname,
      fieldname,
      is_private: '0',
      file: createReadStream(resolve(process.cwd(), 'fixtures', 'sample-photo.png'))
    }
  });
}
