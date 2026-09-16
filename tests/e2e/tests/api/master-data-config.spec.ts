import { expect, test } from '@playwright/test';
import { createApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

type FieldExpectation = {
  doctype: string;
  fields: string[];
};

const requiredWarehouses = [
  'Main - Inmed',
  'Delivery In-Transit - Inmed',
  'Return Pickup In-Transit - Inmed',
  'Returns - Inmed'
];

const requiredCustomDocTypes = [
  'Dispatch Case',
  'Dispatch Case Item',
  'Task Access Policy',
  'Debt Collection Invoice',
  'Debt Collection Payment',
  'Tender Agreement',
  'Tender Agreement Item'
];

const requiredRoles = [
  'Ops - Order Accepting',
  'Ops - Order Creating',
  'Ops - Inventory',
  'Delivery Driver',
  'Ops - Returns',
  'Ops - Accounting',
  'Ops - Finance',
  'Ops - Directors'
];

const fieldExpectations: FieldExpectation[] = [
  {
    doctype: 'Task',
    fields: [
      'task_kind',
      'task_access_policy',
      'custom_assigned_to',
      'custom_accepted_by',
      'custom_accepted_at',
      'completed_at',
      'dispatch_case',
      'delivery_status',
      'approval_outcome'
    ]
  },
  {
    doctype: 'Dispatch Case',
    fields: [
      'customer',
      'client_location_warehouse',
      'return_expected',
      'status',
      'order_entry_task',
      'pack_task',
      'delivery_task',
      'invoice_task',
      'sales_invoice',
      'prepaid_amount',
      'outstanding_amount',
      'advance_payments'
    ]
  },
  {
    doctype: 'Dispatch Case Item',
    fields: [
      'item_code',
      'item_name',
      'dispatched_qty',
      'returned_qty',
      'lost_damaged_qty',
      'used_qty',
      'unit_price',
      'discount_pct',
      'custom_scanned_qty',
      'custom_packing_status',
      'custom_remaining_qty'
    ]
  },
  {
    doctype: 'Customer',
    fields: ['client_code', 'client_kind', 'debt_threshold_amd', 'is_provisional']
  },
  {
    doctype: 'Item',
    fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'pack_breaking_policy', 'reorder_change_reason']
  }
];

const requiredServerScripts = [
  'dispatch_task_accept',
  'task_create_dispatch_case',
  'task_add_dispatch_product',
  'task_mark_item_packed',
  'task_mark_items_packed_batch',
  'task_update_return_item_quantities',
  'Task-before-save-policy',
  'Task-before-save-dispatch-gates',
  'Task-after-save-dispatch-flow',
  'Telegram Task Assignment Notification',
  'Telegram Task Status Update'
];

const requiredClientScripts = [
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

async function getMetaFields(api: { callMethod<T = unknown>(method: string, data?: Record<string, unknown>): Promise<T> }, doctype: string): Promise<FrappeDoc[]> {
  const meta = await api.callMethod<{ fields?: FrappeDoc[]; docs?: FrappeDoc[]; doctype?: { fields?: FrappeDoc[] } }>('frappe.desk.form.load.getdoctype', { doctype }) || {};
  if (Array.isArray(meta.fields)) return meta.fields;
  if (Array.isArray(meta.doctype?.fields)) return meta.doctype.fields;
  const doc = (meta.docs || []).find((row) => row.name === doctype || row.doctype === 'DocType') || meta.docs?.[0];
  return Array.isArray(doc?.fields) ? doc.fields as FrappeDoc[] : [];
}

test.describe('Master data and configuration preflight @api @audit', () => {
  for (const warehouseName of requiredWarehouses) {
    test(`${warehouseName} warehouse exists and is usable`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const warehouse = await api.getDoc<FrappeDoc>('Warehouse', warehouseName);
        expect(warehouse.name).toBe(warehouseName);
        expect(warehouse.is_group, `${warehouseName} is not a group warehouse`).not.toBe(1);
        expect(warehouse.disabled, `${warehouseName} is enabled`).not.toBe(1);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const doctypeName of requiredCustomDocTypes) {
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

  for (const roleName of requiredRoles) {
    test(`${roleName} role exists and is enabled`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const role = await api.getDoc<FrappeDoc>('Role', roleName);
        expect(role.name).toBe(roleName);
        expect(role.disabled, `${roleName} disabled flag`).not.toBe(1);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const expectation of fieldExpectations) {
    test(`${expectation.doctype} has required operational fields`, async () => {
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

  test('Dispatch Case is submittable and uses the expected autoname pattern', async () => {
    const { context, api } = await createApiBundle();
    try {
      const doctype = await api.getDoc<FrappeDoc>('DocType', 'Dispatch Case');
      expect(doctype.is_submittable).toBe(1);
      expect(String(doctype.autoname || '')).toContain('DC-');
    } finally {
      await context.dispose();
    }
  });

  test('Task task_kind field is a Select with configured options', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Task');
      test.skip(fields.length === 0, 'Task metadata fields are not exposed by current getdoctype API response');
      const taskKind = fields.find((field) => field.fieldname === 'task_kind');
      expect(taskKind?.fieldtype).toBe('Select');
      expect(String(taskKind?.options || '')).toContain('Order entry');
      expect(String(taskKind?.options || '')).toContain('Pack / prepare items');
      expect(String(taskKind?.options || '')).toContain('Debt Collection');
    } finally {
      await context.dispose();
    }
  });

  test('required server scripts exist in ERPNext metadata', async () => {
    const { context, api } = await createApiBundle();
    try {
      for (const scriptName of requiredServerScripts) {
        const script = await api.getDoc<FrappeDoc>('Server Script', scriptName);
        expect(script.name, `${scriptName} exists`).toBe(scriptName);
      }
    } finally {
      await context.dispose();
    }
  });

  test('required client scripts exist in ERPNext metadata', async () => {
    const { context, api } = await createApiBundle();
    try {
      for (const scriptName of requiredClientScripts) {
        const script = await api.getDoc<FrappeDoc>('Client Script', scriptName);
        expect(script.name, `${scriptName} exists`).toBe(scriptName);
      }
    } finally {
      await context.dispose();
    }
  });
});
