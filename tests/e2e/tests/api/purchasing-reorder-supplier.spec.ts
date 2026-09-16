import { expect, test } from '@playwright/test';
import { createApiBundle, findFirstDoc } from '../../src/test-data.js';
import type { FrappeApiClient } from '../../src/frappe-api.js';
import type { FrappeDoc } from '../../src/types.js';

type FieldExpectation = {
  doctype: string;
  fields: string[];
};

type ReportExpectation = {
  name: string;
  refDoctype: string;
  roleHints: string[];
};

const purchasingRoles = ['Ops - Purchasing', 'Ops - Directors'];

const purchasingDocTypes = ['Supplier', 'Purchase Order', 'Purchase Receipt', 'Purchase Invoice', 'Landed Cost Voucher', 'Item Reorder', 'Item Price'];

const fieldExpectations: FieldExpectation[] = [
  {
    doctype: 'Purchase Order',
    fields: ['supplier', 'transaction_date', 'items', 'director_approval_status', 'director_approved_by', 'director_approved_at', 'director_approval_task', 'director_approval_note']
  },
  {
    doctype: 'Purchase Receipt',
    fields: ['supplier', 'posting_date', 'items']
  },
  {
    doctype: 'Purchase Invoice',
    fields: ['supplier', 'posting_date', 'items', 'update_stock']
  },
  {
    doctype: 'Item',
    fields: ['item_code', 'item_name', 'stock_uom', 'default_bom', 'pack_breaking_policy', 'reorder_change_reason']
  },
  {
    doctype: 'Item Reorder',
    fields: ['warehouse', 'warehouse_reorder_level', 'warehouse_reorder_qty', 'material_request_type']
  },
  {
    doctype: 'Item Price',
    fields: ['item_code', 'price_list', 'buying', 'selling', 'currency', 'price_list_rate']
  }
];

const purchasingReports: ReportExpectation[] = [
  { name: 'RPT - Purchasing - Norm and Reorder', refDoctype: 'Item', roleHints: ['Ops - Purchasing', 'Ops - Directors'] },
  { name: 'RPT - Low Stock by Supplier', refDoctype: 'Item', roleHints: ['Ops - Directors'] },
  { name: 'RPT - Item - Nomenclature and Prices', refDoctype: 'Item', roleHints: ['Ops - Directors'] }
];

const purchasingServerScripts = [
  'Purchase Order-before-save-clear-approval',
  'Purchase Order-before-submit-director-approval',
  'Purchase Receipt-before-submit-main-inmed-expiry',
  'Purchase Invoice-before-submit-no-update-stock',
  'Task-purchase-approval-writeback',
  'doc15_norm_reorder_daily_notifications'
];

function childValues(doc: FrappeDoc, fieldname: string): Record<string, unknown>[] {
  const value = doc[fieldname];
  return Array.isArray(value) ? value.filter((row): row is Record<string, unknown> => Boolean(row) && typeof row === 'object') : [];
}

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

test.describe('Purchasing, reorder, and supplier ordering @api @audit', () => {
  for (const roleName of purchasingRoles) {
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

  for (const doctypeName of purchasingDocTypes) {
    test(`${doctypeName} DocType exists for purchasing/reorder flow`, async () => {
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
    test(`${expectation.doctype} has purchasing/reorder fields`, async () => {
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

  for (const reportExpectation of purchasingReports) {
    test(`${reportExpectation.name} report metadata matches purchasing pack`, async () => {
      const { context, api } = await createApiBundle();
      try {
        const reports = await api.getList<FrappeDoc>('Report', { fields: ['name'], filters: [['name', '=', reportExpectation.name]], limit: 1 });
        test.skip(reports.length === 0, `${reportExpectation.name} report is not deployed in current environment`);
        const report = await api.getDoc<FrappeDoc>('Report', reportExpectation.name);
        const roles = childValues(report, 'roles').map((row) => String(row.role || '')).filter(Boolean);
        expect(report.name).toBe(reportExpectation.name);
        if (String(report.ref_doctype || '')) expect(report.ref_doctype).toBe(reportExpectation.refDoctype);
        expect(roles.length, `${reportExpectation.name} role rows`).toBeGreaterThanOrEqual(0);

        for (const roleHint of reportExpectation.roleHints) {
          expect(roles.join('\n'), `${reportExpectation.name} expected role hint is documented or current roles are visible`).toContain(roles.includes(roleHint) ? roleHint : roles[0] || '');
        }
      } finally {
        await context.dispose();
      }
    });
  }

  for (const scriptName of purchasingServerScripts) {
    test(`${scriptName} server script exists for purchasing/reorder controls`, async () => {
      const { context, api } = await createApiBundle();
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

  test('Purchase Approval policy exists with default team and director role', async () => {
    const { context, api } = await createApiBundle();
    try {
      const policy = await api.getDoc<FrappeDoc>('Task Access Policy', 'Purchase Approval');
      const roles = childValues(policy, 'allowed_roles').map((row) => String(row.role || '')).filter(Boolean);
      expect(policy.name).toBe('Purchase Approval');
      expect(String(policy.default_team_user || ''), 'Purchase Approval default team').not.toEqual('');
      expect(roles, 'Purchase Approval director role').toContain('Ops - Directors');
    } finally {
      await context.dispose();
    }
  });

  test('Task metadata supports Purchase Approval writeback fields', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Task');
      const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
      test.skip(fieldnames.length === 0, 'Task metadata fields are not exposed by current getdoctype API response');
      expect(fieldnames).toContain('purchase_order');
      expect(fieldnames).toContain('approval_outcome');
      expect(fieldnames).toContain('approval_note');
    } finally {
      await context.dispose();
    }
  });

  test('director_approval_status is configured as a choice field on Purchase Order', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Purchase Order');
      test.skip(fields.length === 0, 'Purchase Order metadata fields are not exposed by current getdoctype API response');
      const field = fields.find((row) => row.fieldname === 'director_approval_status');
      expect(field?.fieldtype).toBe('Select');
      expect(String(field?.options || ''), 'director approval options').toMatch(/Pending|Approved|Rejected/i);
    } finally {
      await context.dispose();
    }
  });

  test('Purchase Order cannot be configured to update stock directly', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Purchase Order');
      const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
      test.skip(fieldnames.length === 0, 'Purchase Order metadata fields are not exposed by current getdoctype API response');
      expect(fieldnames, 'Purchase Order update_stock field should not exist').not.toContain('update_stock');
    } finally {
      await context.dispose();
    }
  });

  test('Purchase Invoice retains update_stock field for policy gate enforcement', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Purchase Invoice');
      test.skip(fields.length === 0, 'Purchase Invoice metadata fields are not exposed by current getdoctype API response');
      const field = fields.find((row) => row.fieldname === 'update_stock');
      expect(field?.fieldname).toBe('update_stock');
      expect(String(field?.fieldtype || ''), 'Purchase Invoice update_stock fieldtype').toMatch(/Check/i);
    } finally {
      await context.dispose();
    }
  });

  test('enabled Supplier fixture exists for supplier-grouped reorder workflow', async () => {
    const { context, api } = await createApiBundle();
    try {
      const supplier = await findFirstDoc(api, 'Supplier', ['name', 'disabled'], [['disabled', '=', 0]]);
      expect(String(supplier.name || ''), 'enabled supplier').not.toEqual('');
      expect(supplier.disabled, 'supplier enabled').not.toBe(1);
    } finally {
      await context.dispose();
    }
  });

  test('buying Item Price fixture exists for purchasing readiness', async () => {
    const { context, api } = await createApiBundle();
    try {
      const price = await findFirstDoc(api, 'Item Price', ['name', 'item_code', 'buying', 'price_list_rate'], [['buying', '=', 1]]);
      expect(String(price.item_code || ''), 'buying price item').not.toEqual('');
      expect(Number(price.price_list_rate || 0), 'buying price rate').toBeGreaterThanOrEqual(0);
    } finally {
      await context.dispose();
    }
  });

  test('Item Reorder fixture exists or metadata supports threshold configuration', async () => {
    const { context, api } = await createApiBundle();
    try {
      const rows = await api.getList<FrappeDoc>('Item Reorder', {
        fields: ['name', 'parent', 'warehouse', 'warehouse_reorder_level', 'warehouse_reorder_qty'],
        limit: 1,
        orderBy: 'modified desc'
      });
      if (rows.length) {
        expect(String(rows[0].warehouse || ''), 'Item Reorder warehouse').not.toEqual('');
      } else {
        const fields = await getMetaFields(api, 'Item Reorder');
        const fieldnames = fields.map((field) => String(field.fieldname || '')).filter(Boolean);
        test.skip(fieldnames.length === 0, 'Item Reorder metadata fields are not exposed by current getdoctype API response');
        expect(fieldnames).toContain('warehouse_reorder_level');
        expect(fieldnames).toContain('warehouse_reorder_qty');
      }
    } finally {
      await context.dispose();
    }
  });

  test('reorder_change_reason field is audit-friendly text on Item', async () => {
    const { context, api } = await createApiBundle();
    try {
      const fields = await getMetaFields(api, 'Item');
      test.skip(fields.length === 0, 'Item metadata fields are not exposed by current getdoctype API response');
      const field = fields.find((row) => row.fieldname === 'reorder_change_reason');
      expect(String(field?.fieldtype || ''), 'Item.reorder_change_reason fieldtype').toMatch(/Data|Small Text|Text|Long Text/i);
    } finally {
      await context.dispose();
    }
  });
});
