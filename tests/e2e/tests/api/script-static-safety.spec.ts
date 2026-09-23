import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { FrappeDoc } from '../../src/types.js';

const criticalServerScripts = [
  'dispatch_task_accept',
  'task_create_dispatch_case',
  'task_add_dispatch_product',
  'task_mark_item_packed',
  'task_mark_items_packed_batch',
  'task_update_return_item_quantities',
  'Task-before-save-policy',
  'Task-before-save-dispatch-gates',
  'Task-after-save-dispatch-flow',
  'Task-purchase-approval-writeback',
  'Telegram Task Assignment Notification',
  'Telegram Task Status Update'
];

const criticalClientScripts = [
  'Task-Accept Start',
  'Task-Field-Visibility',
  'Task-Field-Editability',
  'Task-Auto Reload',
  'Task-Packing Checkboxes',
  'Global-Mobile Back Button List',
  'Dispatch Case-Form',
  'Dispatch Case-Products Button',
  'Dispatch Case-Price Visibility'
];

async function exportedScripts(fileName: 'server-scripts.json' | 'client-scripts.json'): Promise<FrappeDoc[]> {
  const text = await readFile(resolve(process.cwd(), '..', '..', 'deploy', 'test', 'schema', fileName), 'utf8');
  const parsed = JSON.parse(text.replace(/^\uFEFF/, '')) as { records?: FrappeDoc[] };
  return parsed.records || [];
}

async function exportedScript(fileName: 'server-scripts.json' | 'client-scripts.json', name: string): Promise<FrappeDoc> {
  const script = (await exportedScripts(fileName)).find((row) => row.name === name);
  expect(script, `${name} is present in exported test schema`).toBeTruthy();
  return script as FrappeDoc;
}

function scriptText(doc: FrappeDoc): string {
  return String(doc.script || doc.javascript || doc.code || '');
}

test.describe('Client and server script static safety @api @audit', () => {
  for (const scriptName of criticalServerScripts) {
    test(`${scriptName} server script has executable text`, async () => {
      const script = await exportedScript('server-scripts.json', scriptName);
      expect(script.name).toBe(scriptName);
      expect(scriptText(script).length, `${scriptName} script text`).toBeGreaterThan(10);
    });
  }

  for (const scriptName of criticalServerScripts) {
    test(`${scriptName} server script avoids blocked RestrictedPython primitives`, async () => {
      const script = await exportedScript('server-scripts.json', scriptName);
      const text = scriptText(script);
      expect(text, `${scriptName} import statements`).not.toMatch(/^\s*(from\s+\S+\s+import|import\s+\S+)/m);
      expect(text, `${scriptName} exec/eval/compile/import primitives`).not.toMatch(/\b(exec|eval|compile|__import__)\s*\(/);
      expect(text, `${scriptName} double underscore attribute access`).not.toMatch(/\.__/);
    });
  }

  for (const scriptName of criticalClientScripts) {
    test(`${scriptName} client script has executable text`, async () => {
      const script = await exportedScript('client-scripts.json', scriptName);
      expect(script.name).toBe(scriptName);
      expect(scriptText(script).length, `${scriptName} script text`).toBeGreaterThan(10);
    });
  }

  test('Task-Field-Visibility remains the Task field visibility owner', async () => {
    const script = await exportedScript('client-scripts.json', 'Task-Field-Visibility');
    const text = scriptText(script);
    expect(text).toMatch(/TFV_KIND_MAP|toggle_display|set_df_property/);
    expect(String(script.dt || script.reference_doctype || ''), 'Task-Field-Visibility target').toMatch(/^Task$/);
  });

  test('Task-Field-Editability remains the Task field editability owner', async () => {
    const script = await exportedScript('client-scripts.json', 'Task-Field-Editability');
    const text = scriptText(script);
    expect(text).toMatch(/TFE_EDIT_MAP|tfe_can_edit|read_only/);
    expect(String(script.dt || script.reference_doctype || ''), 'Task-Field-Editability target').toMatch(/^Task$/);
  });

  test('Task editability owner keeps acceptance lock without admin exemption markers', async () => {
    const script = await exportedScript('client-scripts.json', 'Task-Field-Editability');
    const text = scriptText(script);
    expect(text, 'acceptance check exists').toMatch(/custom_accepted_by|accepted_by/);
    expect(text, 'session user check exists').toMatch(/session\.user|frappe\.session\.user/);
    expect(text, 'no System Manager edit bypass marker').not.toMatch(/System Manager|Administrator|is_admin/i);
  });

  test('Telegram assignment script reads Telegram Settings and avoids hardcoded bot token marker', async () => {
    const script = await exportedScript('server-scripts.json', 'Telegram Task Assignment Notification');
    const text = scriptText(script);
    expect(text).toMatch(/Telegram Settings/);
    expect(text, 'no literal bot token pattern').not.toMatch(/\b\d{8,12}:[A-Za-z0-9_-]{30,}\b/);
  });

  test('Telegram status script reads Telegram Settings and avoids hardcoded bot token marker', async () => {
    const script = await exportedScript('server-scripts.json', 'Telegram Task Status Update');
    const text = scriptText(script);
    expect(text).toMatch(/Telegram Settings/);
    expect(text, 'no literal bot token pattern').not.toMatch(/\b\d{8,12}:[A-Za-z0-9_-]{30,}\b/);
  });

  test('Task field visibility scripts do not multiply-own TFV mapped fields', async () => {
    const scripts = (await exportedScripts('client-scripts.json')).filter((script) => script.dt === 'Task');
    const visibilityOwners = scripts.filter((script) => /toggle_display|set_df_property\([^)]*hidden|\.hide\(|\.show\(/.test(scriptText(script))).map((script) => String(script.name || ''));
    expect(visibilityOwners, 'Task visibility script owners include TFV').toContain('Task-Field-Visibility');
  });

  test('Task field editability scripts do not multiply-own TFE controlled read only logic', async () => {
    const scripts = (await exportedScripts('client-scripts.json')).filter((script) => script.dt === 'Task');
    const editabilityOwners = scripts.filter((script) => /read_only|disable_save|set_read_only|\.prop\([^)]*disabled/.test(scriptText(script))).map((script) => String(script.name || ''));
    expect(editabilityOwners, 'Task editability script owners include TFE').toContain('Task-Field-Editability');
  });
});
