import type { APIRequestContext, APIResponse } from '@playwright/test';
import { validateEnvironment } from './safety.js';
import { FrappeError, type FrappeDoc, type FrappeListOptions } from './types.js';

export class FrappeApiClient {
  readonly baseUrl: string;
  private readonly request: APIRequestContext;

  constructor(request: APIRequestContext, baseUrl: string) {
    this.baseUrl = validateEnvironment(baseUrl).origin;
    this.request = request;
  }

  async getDoc<T extends FrappeDoc = FrappeDoc>(doctype: string, name: string): Promise<T> {
    const response = await this.request.get(`/api/resource/${encodeURIComponent(doctype)}/${encodeURIComponent(name)}`);
    return this.unwrapData<T>(response);
  }

  async getList<T extends FrappeDoc = FrappeDoc>(doctype: string, opts: FrappeListOptions = {}): Promise<T[]> {
    const params: Record<string, string> = {};

    if (opts.filters) params.filters = JSON.stringify(opts.filters);
    if (opts.fields) params.fields = JSON.stringify(opts.fields);
    if (opts.limit) params.limit_page_length = String(opts.limit);
    if (opts.orderBy) params.order_by = opts.orderBy;

    const response = await this.request.get(`/api/resource/${encodeURIComponent(doctype)}`, { params });
    return this.unwrapData<T[]>(response);
  }

  async createDoc<T extends FrappeDoc = FrappeDoc>(doctype: string, fields: FrappeDoc): Promise<T> {
    const response = await this.request.post(`/api/resource/${encodeURIComponent(doctype)}`, { data: fields });
    return this.unwrapData<T>(response);
  }

  async updateDoc<T extends FrappeDoc = FrappeDoc>(doctype: string, name: string, fields: FrappeDoc): Promise<T> {
    const response = await this.request.put(`/api/resource/${encodeURIComponent(doctype)}/${encodeURIComponent(name)}`, { data: fields });
    return this.unwrapData<T>(response);
  }

  async callMethod<T = unknown>(method: string, data: Record<string, unknown> = {}): Promise<T> {
    const response = await this.request.post(`/api/method/${method}`, { data });
    return this.unwrapMessage<T>(response);
  }

  async saveDoc<T extends FrappeDoc = FrappeDoc>(doc: FrappeDoc): Promise<T> {
    return this.callMethod<T>('frappe.client.save', { doc });
  }

  async acceptTask<T = unknown>(taskName: string): Promise<T> {
    return this.callMethod<T>('dispatch_task_accept', { task_name: taskName });
  }

  async createDispatchCase<T = unknown>(taskName: string): Promise<T> {
    return this.callMethod<T>('task_create_dispatch_case', { task_name: taskName });
  }

  async addProduct<T = unknown>(taskName: string, itemCode: string, qty: number, unitPrice?: number): Promise<T> {
    return this.callMethod<T>('task_add_dispatch_product', { task_name: taskName, item_code: itemCode, qty, unit_price: unitPrice });
  }

  async markItemPacked<T = unknown>(caseName: string, itemIdx: number, packed: boolean): Promise<T> {
    return this.callMethod<T>('task_mark_item_packed', { case_name: caseName, item_idx: itemIdx, packed });
  }

  async markItemsPackedBatch<T = unknown>(caseName: string, packedIndices: number[], taskKind = ''): Promise<T> {
    return this.callMethod<T>('task_mark_items_packed_batch', { case_name: caseName, packed_indices: JSON.stringify(packedIndices), task_kind: taskKind });
  }

  private async unwrapData<T>(response: APIResponse): Promise<T> {
    const body = await this.parse(response);
    if (!response.ok()) throw this.toError(response, body);
    return (body as { data: T }).data;
  }

  private async unwrapMessage<T>(response: APIResponse): Promise<T> {
    const body = await this.parse(response);
    if (!response.ok()) throw this.toError(response, body);
    return (body as { message: T }).message;
  }

  private async parse(response: APIResponse): Promise<unknown> {
    const text = await response.text();
    if (!text) return {};

    try {
      return JSON.parse(text) as unknown;
    } catch {
      return { text };
    }
  }

  private toError(response: APIResponse, body: unknown): FrappeError {
    const message = extractFrappeMessage(body) || `${response.status()} ${response.statusText()}`;
    const kind = response.status() === 417 ? 'validation' : 'unexpected';
    return new FrappeError(message, response.status(), kind, body);
  }
}

function extractFrappeMessage(body: unknown): string | null {
  if (!body || typeof body !== 'object') return null;

  const data = body as Record<string, unknown>;
  const serverMessages = data._server_messages;

  if (typeof serverMessages === 'string') {
    try {
      const messages = JSON.parse(serverMessages) as string[];
      const parsed = messages.map((message) => JSON.parse(message) as { message?: string });
      return parsed.map((message) => message.message).filter(Boolean).join('\n') || null;
    } catch {
      return serverMessages;
    }
  }

  if (typeof data.exc === 'string') return data.exc;
  if (typeof data.exception === 'string') return data.exception;
  if (typeof data.message === 'string') return data.message;

  return null;
}
