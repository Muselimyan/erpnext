import type { Browser, BrowserContext, Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { RoleName, TestConfig } from './types.js';

export async function frappeLogin(page: Page, user: string, password: string): Promise<void> {
  await page.goto('/login');
  await page.locator('#login_email').fill(user);
  await page.locator('#login_password').fill(password);
  await page.locator('.btn-login').click();
  await page.waitForURL(/\/(app|desk)/, { timeout: 15000 });
}

export async function createAllSessions(browser: Browser, config: TestConfig): Promise<Map<RoleName, string>> {
  const sessionsDir = resolve(process.cwd(), 'sessions');
  await mkdir(sessionsDir, { recursive: true });

  const sessions = new Map<RoleName, string>();

  for (const [role, credentials] of config.roles.entries()) {
    const context = await browser.newContext({ baseURL: config.baseUrl });
    const page = await context.newPage();
    await frappeLogin(page, credentials.user, credentials.password);

    const sessionPath = resolve(sessionsDir, `${role}.json`);
    await context.storageState({ path: sessionPath });
    sessions.set(role, sessionPath);
    await context.close();
  }

  return sessions;
}

export async function asRole(browser: Browser, role: RoleName): Promise<BrowserContext> {
  return browser.newContext({ storageState: resolve(process.cwd(), 'sessions', `${role}.json`) });
}
