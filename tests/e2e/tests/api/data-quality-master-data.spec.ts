import { expect, test } from '@playwright/test';
import { createRoleApiBundle } from '../../src/test-data.js';
import type { FrappeDoc } from '../../src/types.js';

test.describe('Data quality and master data integrity @api @audit', () => {
  test('enabled stock items have item group and stock UOM populated', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const items = await api.getList<FrappeDoc>('Item', {
        fields: ['name', 'item_code', 'item_group', 'stock_uom'],
        filters: [['disabled', '=', 0], ['is_stock_item', '=', 1]],
        limit: 100
      });
      expect(items.length, 'enabled stock item sample exists').toBeGreaterThan(0);
      const invalid = items.filter((item) => !item.item_group || !item.stock_uom);
      expect(invalid, 'stock items missing item_group or stock_uom').toEqual([]);
    } finally {
      await context.dispose();
    }
  });

  test('enabled customers have unique non-empty client code when client code is assigned', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const customers = await api.getList<FrappeDoc>('Customer', {
        fields: ['name', 'client_code'],
        filters: [['disabled', '=', 0]],
        limit: 500
      });
      expect(customers.length, 'enabled customer sample exists').toBeGreaterThan(0);
      const assignedCodes = customers.map((customer) => String(customer.client_code || '').trim()).filter(Boolean);
      const duplicateCount = assignedCodes.length - new Set(assignedCodes).size;
      expect(duplicateCount, 'duplicate assigned client codes observed in current data sample').toBe(0);
    } finally {
      await context.dispose();
    }
  });

  test('operational warehouses are leaves under an Inmed company context', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const warehouses = await api.getList<FrappeDoc>('Warehouse', {
        fields: ['name', 'warehouse_name', 'company', 'is_group', 'disabled'],
        filters: [['name', 'in', ['Main - Inmed', 'Delivery In-Transit - Inmed', 'Return Pickup In-Transit - Inmed', 'Returns - Inmed']]],
        limit: 10
      });
      expect(warehouses.length).toBe(4);
      for (const warehouse of warehouses) {
        expect(warehouse.is_group, `${warehouse.name} is leaf`).not.toBe(1);
        expect(warehouse.disabled, `${warehouse.name} enabled`).not.toBe(1);
        expect(String(warehouse.company || warehouse.name || ''), `${warehouse.name} company/name context`).toMatch(/Inmed/i);
      }
    } finally {
      await context.dispose();
    }
  });

  test('enabled buying item prices point to enabled items', async () => {
    test.skip(true, 'DIAGNOSTIC-ONLY: live Item Price records are not readable by ordinary regression roles');
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const prices = await api.getList<FrappeDoc>('Item Price', {
        fields: ['name', 'item_code', 'price_list_rate', 'currency'],
        filters: [['buying', '=', 1]],
        limit: 50
      });
      expect(prices.length, 'buying price sample exists').toBeGreaterThan(0);
      for (const price of prices) {
        const item = await api.getDoc<FrappeDoc>('Item', String(price.item_code));
        expect(item.disabled, `${price.item_code} enabled`).not.toBe(1);
        expect(Number(price.price_list_rate || 0), `${price.item_code} buying price`).toBeGreaterThan(0);
        expect(String(price.currency || ''), `${price.item_code} currency`).not.toEqual('');
      }
    } finally {
      await context.dispose();
    }
  });

  test('enabled selling item prices point to enabled items', async () => {
    test.skip(true, 'DIAGNOSTIC-ONLY: live Item Price records are not readable by ordinary regression roles');
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const prices = await api.getList<FrappeDoc>('Item Price', {
        fields: ['name', 'item_code', 'price_list_rate', 'currency'],
        filters: [['selling', '=', 1]],
        limit: 50
      });
      expect(prices.length, 'selling price sample exists').toBeGreaterThan(0);
      for (const price of prices) {
        const item = await api.getDoc<FrappeDoc>('Item', String(price.item_code));
        expect(item.disabled, `${price.item_code} enabled`).not.toBe(1);
        expect(Number(price.price_list_rate || 0), `${price.item_code} selling price`).toBeGreaterThan(0);
        expect(String(price.currency || ''), `${price.item_code} currency`).not.toEqual('');
      }
    } finally {
      await context.dispose();
    }
  });

  test('Task Access Policy default team users exist and are enabled User records', async () => {
    test.skip(true, 'DIAGNOSTIC-ONLY: live User records are not readable by ordinary regression roles');
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const policies = await api.getList<FrappeDoc>('Task Access Policy', { fields: ['name', 'default_team_user'], limit: 100 });
      expect(policies.length, 'policy records').toBeGreaterThan(0);
      const withTeam = policies.filter((policy) => String(policy.default_team_user || '').trim());
      expect(withTeam.length, 'policies with teams').toBeGreaterThan(0);
      for (const policy of withTeam) {
        const user = await api.getDoc<FrappeDoc>('User', String(policy.default_team_user));
        expect(String(user.name || ''), `${policy.name} default team user exists`).not.toEqual('');
      }
    } finally {
      await context.dispose();
    }
  });

  test('open operational tasks have single-source assignment and policy links when task kind is set', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const tasks = await api.getList<FrappeDoc>('Task', {
        fields: ['name', 'task_kind', 'task_access_policy', 'custom_assigned_to', 'status'],
        filters: [['status', 'not in', ['Completed', 'Cancelled']], ['task_kind', 'is', 'set']],
        limit: 100
      });
      const missingAssignment = tasks.filter((task) => !String(task.custom_assigned_to || '').trim());
      const missingPolicy = tasks.filter((task) => !String(task.task_access_policy || '').trim());
      expect(missingAssignment, 'open operational tasks missing assignment in current sample').toEqual([]);
      expect(missingPolicy, 'open operational tasks missing policy link in current sample').toEqual([]);
    } finally {
      await context.dispose();
    }
  });

  test('submitted Dispatch Cases have required coordinator links populated according to current state', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const cases = await api.getList<FrappeDoc>('Dispatch Case', {
        fields: ['name', 'docstatus', 'status', 'order_entry_task', 'pack_task', 'delivery_task'],
        filters: [['docstatus', '=', 1]],
        limit: 50
      });
      const missingOrderTask = cases.filter((dispatchCase) => !String(dispatchCase.order_entry_task || '').trim());
      const missingPackTask = cases.filter((dispatchCase) => /Pack|Delivery|Return|Invoice|Payment|Closed/i.test(String(dispatchCase.status || ''))) .filter((dispatchCase) => !String(dispatchCase.pack_task || '').trim());
      expect(missingOrderTask, 'submitted Dispatch Cases missing order task in current sample').toEqual([]);
      expect(missingPackTask, 'submitted Dispatch Cases missing pack task in current sample').toEqual([]);
    } finally {
      await context.dispose();
    }
  });

  test('negative stock data quality report is runnable for current stock state', async () => {
    const { context, api } = await createRoleApiBundle('directors');
    try {
      const reports = await api.getList<FrappeDoc>('Report', { fields: ['name'], filters: [['name', '=', 'RPT - Data Quality - Negative Stock']], limit: 1 });
      test.skip(reports.length === 0, 'negative stock report is not deployed in current environment');
      const result = await api.callMethod<Record<string, unknown>>('frappe.desk.query_report.run', { report_name: 'RPT - Data Quality - Negative Stock', filters: {} });
      const columns = Array.isArray(result?.columns) ? result.columns : [];
      expect(columns.length, 'negative stock report columns').toBeGreaterThan(0);
    } finally {
      await context.dispose();
    }
  });
});
