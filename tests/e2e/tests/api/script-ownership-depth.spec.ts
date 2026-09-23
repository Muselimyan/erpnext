import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import type { FrappeDoc } from '../../src/types.js';

type ScriptMarkerCase = {
  doctype: 'Client Script' | 'Server Script';
  name: string;
  markers: RegExp[];
};

const scriptMarkerCases: ScriptMarkerCase[] = [
  { doctype: 'Client Script', name: 'Task-Field-Visibility', markers: [/TFV_KIND_MAP/, /toggle_display|set_df_property/, /task_kind/] },
  { doctype: 'Client Script', name: 'Task-Field-Editability', markers: [/TFE_EDIT_MAP/, /tfe_can_edit/, /custom_accepted_by/] },
  { doctype: 'Client Script', name: 'Task-Accept Start', markers: [/Task|frm|refresh/i] },
  { doctype: 'Client Script', name: 'Task-Auto Reload', markers: [/reload|refresh/i, /Task/i, /status|modified/i] },
  { doctype: 'Client Script', name: 'Task-Packing Checkboxes', markers: [/packed|packing/i, /task_mark_item_packed|task_mark_items_packed_batch|task_update_return_item_quantities/, /dispatch_case/i] },
  { doctype: 'Client Script', name: 'Dispatch Case-Form', markers: [/Dispatch Case/i, /items|case_items|dispatch_case_items/i, /refresh|onload/i] },
  { doctype: 'Client Script', name: 'Dispatch Case-Products Button', markers: [/Add.*Item|Product|Category/i, /Dispatch Case/i, /frappe\.call/] },
  { doctype: 'Client Script', name: 'Global-Mobile Back Button List', markers: [/mobile|Back/i, /route|history/i, /frappe/] },
  { doctype: 'Server Script', name: 'Task-before-save-policy', markers: [/Task Access Policy/, /custom_assigned_to/, /task_kind/] },
  { doctype: 'Server Script', name: 'Task-before-save-dispatch-gates', markers: [/dispatch_case/, /Completed/, /frappe\.throw/] },
  { doctype: 'Server Script', name: 'Task-after-save-dispatch-flow', markers: [/Pack \/ prepare items|Delivery|Invoice preparation/, /dispatch_case/, /frappe\.get_doc|frappe\.new_doc/] },
  { doctype: 'Server Script', name: 'dispatch_task_accept', markers: [/custom_accepted_by/, /frappe\.session\.user/, /Task Access Policy|allowed_roles/] },
  { doctype: 'Server Script', name: 'task_create_dispatch_case', markers: [/Dispatch Case/, /dispatch_case/, /frappe\.response/] },
  { doctype: 'Server Script', name: 'task_add_dispatch_product', markers: [/item_code/, /qty/, /Dispatch Case|dispatch/i] },
  { doctype: 'Server Script', name: 'task_mark_items_packed_batch', markers: [/packed_indices/, /custom_packing_status|packed/i, /json/] },
  { doctype: 'Server Script', name: 'task_update_return_item_quantities', markers: [/returned_qty/, /lost_damaged_qty|lost/i, /Dispatch Case/] },
  { doctype: 'Server Script', name: 'Telegram Task Assignment Notification', markers: [/Telegram Settings/, /telegram_chat_id/, /custom_assigned_to/] },
  { doctype: 'Server Script', name: 'Telegram Task Status Update', markers: [/Telegram Settings/, /status/, /telegram_chat_id/] },
  { doctype: 'Server Script', name: 'Purchase Order-before-submit-director-approval', markers: [/director_approval_status/, /Approved/, /frappe\.throw/] },
  { doctype: 'Server Script', name: 'Task-purchase-approval-writeback', markers: [/Purchase Approval/, /director_approval_status/, /purchase_order/] }
];

const restrictedServerScriptCases = [
  'Task-before-save-policy',
  'Task-before-save-dispatch-gates',
  'Task-after-save-dispatch-flow',
  'dispatch_task_accept',
  'task_create_dispatch_case',
  'task_add_dispatch_product',
  'task_mark_items_packed_batch',
  'task_update_return_item_quantities',
  'Task-purchase-approval-writeback'
];

async function exportedScripts(doctype: ScriptMarkerCase['doctype']): Promise<FrappeDoc[]> {
  const fileName = doctype === 'Server Script' ? 'server-scripts.json' : 'client-scripts.json';
  const text = await readFile(resolve(process.cwd(), '..', '..', 'deploy', 'test', 'schema', fileName), 'utf8');
  const parsed = JSON.parse(text.replace(/^\uFEFF/, '')) as { records?: FrappeDoc[] };
  return parsed.records || [];
}

async function exportedScript(doctype: ScriptMarkerCase['doctype'], name: string): Promise<FrappeDoc> {
  const script = (await exportedScripts(doctype)).find((row) => row.name === name);
  expect(script, `${doctype} ${name} is present in exported test schema`).toBeTruthy();
  return script as FrappeDoc;
}

function scriptText(script: FrappeDoc): string {
  return String(script.script || script.javascript || script.code || '');
}

test.describe('Script ownership and static safety depth @api @audit', () => {
  for (const scriptCase of scriptMarkerCases) {
    test(`${scriptCase.name} contains expected ownership markers`, async () => {
      const script = await exportedScript(scriptCase.doctype, scriptCase.name);
      const text = scriptText(script);
      expect(text, `${scriptCase.name} script body`).not.toEqual('');
      for (const marker of scriptCase.markers) expect(text, `${scriptCase.name} marker ${marker}`).toMatch(marker);
    });
  }

  for (const scriptName of restrictedServerScriptCases) {
    test(`${scriptName} avoids high-risk RestrictedPython primitives`, async () => {
      const script = await exportedScript('Server Script', scriptName);
      const text = scriptText(script);
      expect(text, `${scriptName} import statement`).not.toMatch(/^\s*(from|import)\s+/m);
      expect(text, `${scriptName} exec/eval/compile`).not.toMatch(/\b(exec|eval|compile|__import__)\s*\(/);
      expect(text, `${scriptName} double underscore access`).not.toMatch(/\.[_]{2}|[_]{2}[A-Za-z]/);
    });
  }
});
