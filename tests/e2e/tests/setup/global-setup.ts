import { chromium, request, test } from '@playwright/test';
import { createAllSessions } from '../../src/auth.js';
import { getConfig } from '../../src/config.js';

test('global setup', async () => {
  test.setTimeout(120000);
  const config = getConfig();
  const api = await request.newContext({
    baseURL: config.baseUrl,
    extraHTTPHeaders: {
      Authorization: `token ${config.apiKey}:${config.apiSecret}`
    }
  });

  try {
    const response = await api.get('/api/method/frappe.auth.get_logged_user');
    if (!response.ok()) {
      throw new Error(`API access check failed: ${response.status()} ${response.statusText()}`);
    }

    const body = (await response.json()) as { message?: string };
    if (!body.message) {
      throw new Error('API access check failed: missing logged user response');
    }
  } finally {
    await api.dispose();
  }

  const browser = await chromium.launch();
  try {
    const sessions = await createAllSessions(browser, config);
    console.log(`Regression setup OK: ${config.baseUrl}; sessions=${Array.from(sessions.keys()).join(',')}`);
  } finally {
    await browser.close();
  }
});
