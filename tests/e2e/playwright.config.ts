import { defineConfig, devices } from '@playwright/test';
import { config as loadEnv } from 'dotenv';
import { resolve } from 'node:path';
import { validateEnvironment } from './src/safety.js';

loadEnv({ path: resolve(process.cwd(), '.env.local') });

const baseUrl = process.env.BASE_URL || 'https://test.erpnext.am';
validateEnvironment(baseUrl);

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  retries: 0,
  outputDir: '../../ERPNext-Automation-Reports/test-results',
  use: {
    baseURL: baseUrl,
    trace: 'retain-on-failure'
  },
  projects: [
    {
      name: 'setup',
      testMatch: /tests[\\/]e2e[\\/]tests[\\/]setup[\\/]global-setup\.ts$/,
      use: {}
    },
    {
      name: 'api',
      testMatch: /tests[\\/]e2e[\\/]tests[\\/]api[\\/].*\.spec\.ts$/,
      dependencies: ['setup'],
      use: {}
    },
    {
      name: 'desktop',
      testMatch: /tests[\\/]e2e[\\/]tests[\\/]smoke[\\/].*\.spec\.ts$/,
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 720 },
        screenshot: 'only-on-failure'
      }
    },
    {
      name: 'mobile',
      testMatch: /tests[\\/]e2e[\\/]tests[\\/]smoke[\\/].*\.spec\.ts$/,
      dependencies: ['setup'],
      use: {
        ...devices['Pixel 5'],
        viewport: { width: 375, height: 812 },
        screenshot: 'only-on-failure'
      }
    },
    {
      name: 'e2e',
      testMatch: /tests[\\/]e2e[\\/]tests[\\/]e2e[\\/].*\.spec\.ts$/,
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        headless: false,
        screenshot: 'on'
      }
    }
  ]
});
