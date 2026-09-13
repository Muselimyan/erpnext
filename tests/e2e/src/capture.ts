import type { Page } from '@playwright/test';
import type { ConsoleEntry, NetworkEntry } from './types.js';

export function attachConsoleCapture(page: Page): ConsoleEntry[] {
  const entries: ConsoleEntry[] = [];

  page.on('console', (message) => {
    if (!['error', 'warning'].includes(message.type())) return;

    entries.push({
      type: message.type(),
      text: redact(message.text()),
      url: message.location().url,
      timestamp: new Date().toISOString()
    });
  });

  page.on('pageerror', (error) => {
    entries.push({
      type: 'pageerror',
      text: redact(error.message),
      timestamp: new Date().toISOString()
    });
  });

  return entries;
}

export function attachNetworkCapture(page: Page): NetworkEntry[] {
  const entries: NetworkEntry[] = [];

  page.on('requestfailed', (request) => {
    if (!request.url().includes('/api/')) return;

    entries.push({
      url: redactUrl(request.url()),
      method: request.method(),
      failureText: request.failure()?.errorText,
      timestamp: new Date().toISOString()
    });
  });

  page.on('response', (response) => {
    const url = response.url();
    if (!url.includes('/api/method/') && !url.includes('/api/resource/')) return;
    if (response.status() < 400) return;

    entries.push({
      url: redactUrl(url),
      method: response.request().method(),
      status: response.status(),
      timestamp: new Date().toISOString()
    });
  });

  return entries;
}

function redact(value: string): string {
  return value.replace(/(api_key|api_secret|password|pwd|token|sid)=([^&\s]+)/gi, '$1=<redacted>');
}

function redactUrl(value: string): string {
  try {
    const url = new URL(value);
    for (const key of Array.from(url.searchParams.keys())) {
      if (/api_key|api_secret|password|pwd|token|sid/i.test(key)) url.searchParams.set(key, '<redacted>');
    }
    return url.toString();
  } catch {
    return redact(value);
  }
}
