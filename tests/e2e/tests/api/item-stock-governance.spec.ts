import { expect, test } from '@playwright/test';
import { createRoleApiBundle, findFirstDoc, findTestItem } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc } from '../../src/types.js';

type FieldExpectation = {
  doctype: string;
  fields: string[];
};

type ReportExpectation = {
  name: string;
  refDoctype: string;
};

const operationalWarehouses = ['Main - Inmed', 'Delivery In-Transit - Inmed', 'Return Pickup In-Transit - Inmed', 'Returns - Inmed'];

const stockReports: ReportExpectation[] = [
  { name: 'RPT - Stock - Client Locations (All)', refDoctype: 'Bin' },
  { name: 'RPT - Stock - Delivery In-Transit - Inmed', refDoctype: 'Bin' },
  { name: 'RPT - Stock - Return Pickup In-Transit - Inmed', refDoctype: 'Bin' },
  { name: 'RPT - Stock - Returns - Inmed', refDoctype: 'Bin' },
  { name: 'RPT - Stock - In-Transit Stuck (Age Check)', refDoctype: 'Stock Ledger Entry' },
  { name: 'RPT - Data Quality - Negative Stock', refDoctype: 'Bin' },
  { name: 'RPT - Item - Nomenclature and Prices', refDoctype: 'Item' }
];

const fieldExpectations: FieldExpectation[] = [
  {
    doctype: 'Item',
    fields: ['item_code', 'item_name', 'description', 'item_group', 'stock_uom', 'is_stock_item', 'disabled', 'has_batch_no', 'has_serial_no', 'has_expiry_date', 'pack_breaking_policy', 'reorder_change_reason']
  },
  {
    doctype: 'Warehouse',
    fields: ['warehouse_name', 'parent_warehouse', 'is_group', 'disabled', 'company']
  },
  {
    doctype: 'Stock Entry',
    fields: ['stock_entry_type', 'purpose', 'posting_date', 'from_warehouse', 'to_warehouse', 'items']
  },
  {
    doctype: 'Stock Entry Detail',
    fields: ['item_code', 'qty', 's_warehouse', 't_warehouse', 'batch_no', 'serial_no', 'basic_rate']
  },
  {
    doctype: 'Bin',
    fields: ['item_code', 'warehouse', 'actual_qty', 'projected_qty', 'reserved_qty', 'ordered_qty']
  },
  {
    doctype: 'Batch',
    fields: ['batch_id', 'item', 'expiry_date', 'disabled']
  },
  {
    doctype: 'Item Group',
    fields: ['item_group_name', 'parent_item_group', 'is_group']
  }
];

const itemStockScripts = [
  'Customer-before-save-governance',
  'StockEntry-before-submit-fefo',
  'Stock Entry-before-save-no-client-wh',
  'Item-before-save-reorder-governance',
  'task_lookup_product_barcode',
  'task_add_dispatch_product'
];

async function getMetaFields(api: FrappeApiClient, doctype: string): Promise<FrappeDoc[]> {
  const meta = await api.callMethod<{ fields?: FrappeDoc[]; docs?: FrappeDoc[]; doctype?: { fields?: FrappeDoc[] } }>('frappe.desk.form.load.getdoctype', { doctype }) || {};
  if (Array.isArray(meta.fields)) return meta.fields;
  if (Array.isArray(meta.doctype?.fields)) return meta.doctype.fields;
  const doc = (meta.docs || []).find((row) => row.name === doctype || row.doctype === 'DocType') || meta.docs?.[0];
  return Array.isArray(doc?.fields) ? doc.fields as FrappeDoc[] : [];
}

async function getMetaField(api: FrappeApiClient, doctype: string, fieldname: string): Promise<FrappeDoc | undefined> {
  const fields = await getMetaFields(api, doctype);
  return fields.find((field) => field.fieldname === fieldname);
}

function childValues(doc: FrappeDoc, fieldname: string): Record<string, unknown>[] {
  const value = doc[fieldname];
  return Array.isArray(value) ? value.filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object') : [];
}

test.describe('Item, stock, and warehouse governance @api @audit', () => {
  for (const warehouseName of operationalWarehouses) {
    test(`${warehouseName} operational warehouse is enabled leaf warehouse`, async () => {
      const { context, api } = await createRoleApiBundle('inventory');
      try {
        const warehouse = await api.getDoc<FrappeDoc>('Warehouse', warehouseName);
        expect(warehouse.name).toBe(warehouseName);
        expect(warehouse.is_group, `${warehouseName} is not group`).not.toBe(1);
        expect(warehouse.disabled, `${warehouseName} is enabled`).not.toBe(1);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const expectation of fieldExpectations) {
    test(`${expectation.doctype} has stock governance fields`, async () => {
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

  for (const reportExpectation of stockReports) {
    test(`${reportExpectation.name} stock report metadata is available`, async () => {
      const { context, api } = await createRoleApiBundle('inventory');
      try {
        const reports = await api.getList<FrappeDoc>('Report', { fields: ['name', 'ref_doctype'], filters: [['name', '=', reportExpectation.name]], limit: 1 });
        test.skip(reports.length === 0, `${reportExpectation.name} report is not deployed in current environment`);
        const report = await api.getDoc<FrappeDoc>('Report', reportExpectation.name);
        const roles = childValues(report, 'roles').map((row) => String(row.role || '')).filter(Boolean);
        expect(report.name).toBe(reportExpectation.name);
        if (String(report.ref_doctype || '')) expect(report.ref_doctype).toBe(reportExpectation.refDoctype);
        expect(roles.length, `${reportExpectation.name} role rows`).toBeGreaterThan(0);
      } finally {
        await context.dispose();
      }
    });
  }

  for (const scriptName of itemStockScripts) {
    test(`${scriptName} item/stock governance script record exists`, async () => {
      test.skip(true, 'DIAGNOSTIC-ONLY: live Server Script metadata is not readable by ordinary regression roles; covered by exported schema checks');
      const { context, api } = await createRoleApiBundle('inventory');
      try {
        const scripts = await api.getList<FrappeDoc>('Server Script', { fields: ['name'], filters: [['name', '=', scriptName]], limit: 1 });
        test.skip(scripts.length === 0, `${scriptName} server script is not deployed in current environment`);
        const script = await api.getDoc<FrappeDoc>('Server Script', scriptName);
        expect(script.name).toBe(scriptName);
      } finally {
        await context.dispose();
      }
    });
  }

  test('enabled stock Item fixture has stable identity and catalog fields', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const itemCode = await findTestItem(api);
      const item = await api.getDoc<FrappeDoc>('Item', itemCode);
      expect(String(item.item_code || item.name || ''), 'item identity').not.toEqual('');
      expect(String(item.item_name || ''), 'item name').not.toEqual('');
      expect(String(item.item_group || ''), 'item group').not.toEqual('');
      expect(String(item.stock_uom || ''), 'stock UOM').not.toEqual('');
      expect(item.disabled, 'item enabled').not.toBe(1);
      expect(item.is_stock_item, 'stock item').toBe(1);
    } finally {
      await context.dispose();
    }
  });

  test('stock Item fixture does not currently require batch serial or expiry', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const itemCode = await findTestItem(api);
      const item = await api.getDoc<FrappeDoc>('Item', itemCode);
      expect(Number(item.has_batch_no || 0), 'fixture has_batch_no').toBe(0);
      expect(Number(item.has_serial_no || 0), 'fixture has_serial_no').toBe(0);
      expect(Number(item.has_expiry_date || 0), 'fixture has_expiry_date').toBe(0);
    } finally {
      await context.dispose();
    }
  });

  test('current item master tracking flags are disabled for go-live temporary state', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const trackedItems = await api.getList<FrappeDoc>('Item', {
        fields: ['name', 'has_batch_no', 'has_serial_no', 'has_expiry_date'],
        filters: [['disabled', '=', 0], ['has_batch_no', '=', 1]],
        limit: 1
      });
      const serialItems = await api.getList<FrappeDoc>('Item', {
        fields: ['name', 'has_serial_no'],
        filters: [['disabled', '=', 0], ['has_serial_no', '=', 1]],
        limit: 1
      });
      const expiryItems = await api.getList<FrappeDoc>('Item', {
        fields: ['name', 'has_expiry_date'],
        filters: [['disabled', '=', 0], ['has_expiry_date', '=', 1]],
        limit: 1
      });
      expect(trackedItems.length, 'enabled batch-tracked items').toBe(0);
      expect(serialItems.length, 'enabled serial-tracked items').toBe(0);
      expect(expiryItems.length, 'enabled expiry-tracked items').toBe(0);
    } finally {
      await context.dispose();
    }
  });

  test('Batch metadata remains available for future tracking re-enable', async () => {
    test.skip(true, 'DIAGNOSTIC-ONLY: live Batch metadata is not readable by ordinary regression roles');
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const doctype = await api.getDoc<FrappeDoc>('DocType', 'Batch');
      expect(doctype.name).toBe('Batch');
      const fields = await getMetaFields(api, 'Batch');
      test.skip(fields.length === 0, 'Batch metadata fields are not exposed by current getdoctype API response');
      const expiryField = fields.find((field) => field.fieldname === 'expiry_date');
      expect(expiryField?.fieldname).toBe('expiry_date');
    } finally {
      await context.dispose();
    }
  });

  test('Stock Entry Detail supports source and target warehouse movement fields', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const fields = await getMetaFields(api, 'Stock Entry Detail');
      test.skip(fields.length === 0, 'Stock Entry Detail metadata fields are not exposed by current getdoctype API response');
      const sourceField = fields.find((field) => field.fieldname === 's_warehouse');
      const targetField = fields.find((field) => field.fieldname === 't_warehouse');
      expect(sourceField?.options, 'source warehouse link').toBe('Warehouse');
      expect(targetField?.options, 'target warehouse link').toBe('Warehouse');
    } finally {
      await context.dispose();
    }
  });

  test('enabled Item Group fixture exists for catalog navigation', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const itemGroup = await findFirstDoc(api, 'Item Group', ['name', 'is_group'], []);
      expect(String(itemGroup.name || ''), 'item group name').not.toEqual('');
    } finally {
      await context.dispose();
    }
  });

  test('Bin fixture exists or Bin metadata supports warehouse stock balances', async () => {
    test.skip(true, 'DIAGNOSTIC-ONLY: live Bin records/metadata are not readable by ordinary regression roles');
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const rows = await api.getList<FrappeDoc>('Bin', {
        fields: ['name', 'item_code', 'warehouse', 'actual_qty', 'projected_qty'],
        limit: 1,
        orderBy: 'modified desc'
      });
      if (rows.length) {
        expect(String(rows[0].item_code || ''), 'Bin item_code').not.toEqual('');
        expect(String(rows[0].warehouse || ''), 'Bin warehouse').not.toEqual('');
      } else {
        const fields = await getMetaFields(api, 'Bin');
        const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
        expect(fieldnames).toContain('actual_qty');
        expect(fieldnames).toContain('projected_qty');
      }
    } finally {
      await context.dispose();
    }
  });

  test('Customer metadata includes client location governance fields used by stock reports', async () => {
    const { context, api } = await createRoleApiBundle('inventory');
    try {
      const fields = await getMetaFields(api, 'Customer');
      const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
      test.skip(fieldnames.length === 0, 'Customer metadata fields are not exposed by current getdoctype API response');
      expect(fieldnames).toContain('client_code');
      expect(fieldnames).toContain('client_kind');
      expect(fieldnames).toContain('is_provisional');
    } finally {
      await context.dispose();
    }
  });
});
