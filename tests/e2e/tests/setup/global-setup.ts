import { chromium, test } from '@playwright/test';
import { createAllSessions } from '../../src/auth.js';
import { getConfig } from '../../src/config.js';

test('global setup', async () => {
  test.setTimeout(120000);
  const config = getConfig();
  const browser = await chromium.launch();
  try {
    const sessions = await createAllSessions(browser, config);
    console.log(`Regression setup OK: ${config.baseUrl}; sessions=${Array.from(sessions.keys()).join(',')}`);
  } finally {
    await browser.close();
  }
});
