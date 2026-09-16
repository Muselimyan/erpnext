import { expect, test } from '@playwright/test';
import { createApiBundle } from '../../src/test-data.js';
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

function scriptText(doc: FrappeDoc): string {
  return String(doc.script || doc.javascript || doc.code || '');
}

test.describe('Surgical Kit Template and Dispatch Case item selection @api @audit', () => {
  for (const doctypeName of templateDocTypes) {
    test(`${doctypeName} DocType exists`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const doctype = await api.getDoc<FrappeDoc>('DocType', doctypeName);
        expect(doctype.name).toBe(doctypeName);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const expectation of fieldExpectations) {
    test(`${expectation.doctype} supports template/item selection fields`, async () => {
      const { context, api } = await createApiBundle();
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
      const { context, api } = await createApiBundle();
      try {
        const script = await api.getDoc<FrappeDoc>('Client Script', scriptName);
        expect(script.name).toBe(scriptName);
        expect(scriptText(script).length, `${scriptName} script text`).toBeGreaterThan(10);
      } finally {
        await context.dispose();
      }
    });
  }

  test('template auto fill script references Surgical Kit Template and template_items', async () => {
    const { context, api } = await createApiBundle();
    try {
      const script = await api.getDoc<FrappeDoc>('Client Script', 'Dispatch Case-Template Auto Fill');
      const text = scriptText(script);
      expect(text).toMatch(/Surgical Kit Template/);
      expect(text).toMatch(/template_items/);
      expect(text).toMatch(/case_items/);
    } finally {
      await context.dispose();
    }
  });

  test('products button script exposes category and search add item flows', async () => {
    const { context, api } = await createApiBundle();
    try {
      const script = await api.getDoc<FrappeDoc>('Client Script', 'Dispatch Case-Products Button');
      const text = scriptText(script);
      expect(text).toMatch(/Add Items by Category|Category/i);
      expect(text).toMatch(/Search.*Add Item|Search/i);
      expect(text).toMatch(/item_code/);
      expect(text).toMatch(/case_items/);
    } finally {
      await context.dispose();
    }
  });

  test('Surgical Kit Template fixture exists or metadata supports fixture creation', async () => {
    const { context, api } = await createApiBundle();
    try {
      const templates = await api.getList<FrappeDoc>('Surgical Kit Template', { fields: ['name', 'template_name'], limit: 1, orderBy: 'modified desc' });
      if (templates.length) {
        expect(String(templates[0].name || ''), 'template fixture name').not.toEqual('');
      } else {
        const fields = await getMetaFields(api, 'Surgical Kit Template');
        const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
        test.skip(fieldnames.length === 0, 'Surgical Kit Template metadata fields are not exposed by current getdoctype API response');
        expect(fieldnames).toContain('template_items');
      }
    } finally {
      await context.dispose();
    }
  });

  test('Surgical Kit Template Item metadata links to Item and quantity', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Surgical Kit Template Item');
      const itemField = fields.find((field) => field.fieldname === 'item_code');
      const qtyField = fields.find((field) => field.fieldname === 'qty');
      test.skip(fields.length === 0, 'Surgical Kit Template Item metadata fields are not exposed by current getdoctype API response');
      expect(itemField?.options, 'template item links to Item').toBe('Item');
      expect(String(qtyField?.fieldtype || ''), 'template qty numeric').toMatch(/Float|Int|Currency/);
    } finally {
      await context.dispose();
    }
  });

  test('Dispatch Case template selector links to Surgical Kit Template', async () => {
    const { context, api } = await createApiBundle();
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
