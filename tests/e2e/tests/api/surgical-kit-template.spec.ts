import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createRoleApiBundle } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc } from '../../src/types.js';

type FieldExpectation = {
  doctype: string;
  fields: string[];
};

const templateDocTypes = ['Surgical Kit Template', 'Surgical Kit Template Item'];

const fieldExpectations: FieldExpectation[] = [
  { doctype: 'Surgical Kit Template', fields: ['template_name', 'describtion', 'template_items'] },
  { doctype: 'Surgical Kit Template Item', fields: ['item_code', 'item_name', 'qty'] },
  { doctype: 'Dispatch Case', fields: ['custom_select_surgical_kit_template', 'case_items'] },
  { doctype: 'Dispatch Case Item', fields: ['item_code', 'item_name', 'dispatched_qty', 'unit_price', 'discount_pct'] }
];

const itemSelectionClientScripts = ['Dispatch Case-Template Auto Fill', 'Dispatch Case-Products Button', 'Dispatch Case-Form'];

async function getMetaFields(api: FrappeApiClient, doctype: string): Promise<FrappeDoc[]> {
  const meta = await api.callMethod<{ fields?: FrappeDoc[]; docs?: FrappeDoc[]; doctype?: { fields?: FrappeDoc[] } }>('frappe.desk.form.load.getdoctype', { doctype }) || {};
  if (Array.isArray(meta.fields)) return meta.fields;
  if (Array.isArray(meta.doctype?.fields)) return meta.doctype.fields;
  const doc = (meta.docs || []).find((row) => row.name === doctype || row.doctype === 'DocType') || meta.docs?.[0];
  return Array.isArray(doc?.fields) ? doc.fields as FrappeDoc[] : [];
}

async function exportedRecords(fileName: 'client-scripts.json' | 'custom-doctypes.json'): Promise<FrappeDoc[]> {
  const text = await readFile(resolve(process.cwd(), '..', '..', 'deploy', 'test', 'schema', fileName), 'utf8');
  const parsed = JSON.parse(text.replace(/^\uFEFF/, '')) as { records?: FrappeDoc[] };
  return parsed.records || [];
}

async function exportedClientScript(scriptName: string): Promise<FrappeDoc> {
  const script = (await exportedRecords('client-scripts.json')).find((row) => row.name === scriptName);
  expect(script, `${scriptName} is present in exported test schema`).toBeTruthy();
  return script as FrappeDoc;
}

async function exportedCustomDoctype(doctypeName: string): Promise<FrappeDoc> {
  const doctype = (await exportedRecords('custom-doctypes.json')).find((row) => row.name === doctypeName);
  expect(doctype, `${doctypeName} is present in exported test schema`).toBeTruthy();
  return doctype as FrappeDoc;
}

function exportedFieldnames(doctype: FrappeDoc): string[] {
  return Array.isArray(doctype.fields) ? doctype.fields.map((field) => String(field.fieldname || '')).filter(Boolean) : [];
}

function scriptText(doc: FrappeDoc): string {
  return String(doc.script || doc.javascript || doc.code || '');
}

test.describe('Surgical Kit Template and Dispatch Case item selection @api @audit', () => {
  for (const doctypeName of templateDocTypes) {
    test(`${doctypeName} DocType exists`, async () => {
      const doctype = await exportedCustomDoctype(doctypeName);
      expect(doctype.name).toBe(doctypeName);
    });
  }

  for (const expectation of fieldExpectations) {
    test(`${expectation.doctype} supports template/item selection fields`, async () => {
      const customDoctype = (await exportedRecords('custom-doctypes.json')).find((row) => row.name === expectation.doctype);
      if (customDoctype) {
        const fieldnames = exportedFieldnames(customDoctype);
        for (const fieldname of expectation.fields) expect(fieldnames, `${expectation.doctype}.${fieldname}`).toContain(fieldname);
        return;
      }

      const { context, api } = await createRoleApiBundle('inventory');
      try {
        const fields = await getMetaFields(api, expectation.doctype);
        const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
        test.skip(fieldnames.length === 0, `${expectation.doctype} metadata fields are not exposed by current getdoctype API response`);
        for (const fieldname of expectation.fields) {
          expect(fieldnames, `${expectation.doctype}.${fieldname}`).toContain(fieldname);
        }
      } finally {
        await context.dispose();
      }
    });
  }

  for (const scriptName of itemSelectionClientScripts) {
    test(`${scriptName} client script exists for item/template workflow`, async () => {
      const script = await exportedClientScript(scriptName);
      expect(script.name).toBe(scriptName);
      expect(scriptText(script).length, `${scriptName} script text`).toBeGreaterThan(10);
    });
  }

  test('template auto fill script references Surgical Kit Template and template_items', async () => {
    const script = await exportedClientScript('Dispatch Case-Template Auto Fill');
    const text = scriptText(script);
    expect(text).toMatch(/Surgical Kit Template/);
    expect(text).toMatch(/template_items/);
    expect(text).toMatch(/case_items/);
  });

  test('products button script exposes category and search add item flows', async () => {
    const script = await exportedClientScript('Dispatch Case-Products Button');
    const text = scriptText(script);
    expect(text).toMatch(/Add Items by Category|Category/i);
    expect(text).toMatch(/Search.*Add Item|Search/i);
    expect(text).toMatch(/item_code/);
    expect(text).toMatch(/case_items/);
  });

  test('Surgical Kit Template fixture exists or metadata supports fixture creation', async () => {
    const doctype = await exportedCustomDoctype('Surgical Kit Template');
    expect(exportedFieldnames(doctype)).toContain('template_items');
  });

  test('Surgical Kit Template Item metadata links to Item and quantity', async () => {
    const doctype = await exportedCustomDoctype('Surgical Kit Template Item');
    const fields = Array.isArray(doctype.fields) ? doctype.fields as FrappeDoc[] : [];
    const itemField = fields.find((field) => field.fieldname === 'item_code');
    const qtyField = fields.find((field) => field.fieldname === 'qty');
    expect(itemField?.options, 'template item links to Item').toBe('Item');
    expect(String(qtyField?.fieldtype || ''), 'template qty numeric').toMatch(/Float|Int|Currency/);
  });

  test('Dispatch Case template selector links to Surgical Kit Template', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const fields = await getMetaFields(api, 'Dispatch Case');
      const selector = fields.find((field) => field.fieldname === 'custom_select_surgical_kit_template');
      test.skip(fields.length === 0, 'Dispatch Case metadata fields are not exposed by current getdoctype API response');
      expect(selector?.fieldtype).toBe('Link');
      expect(selector?.options).toBe('Surgical Kit Template');
    } finally {
      await context.dispose();
    }
  });
});
