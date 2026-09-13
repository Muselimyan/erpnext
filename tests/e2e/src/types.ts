export type RoleName =
  | 'orderAccepting'
  | 'orderCreating'
  | 'inventory'
  | 'delivery'
  | 'returns'
  | 'accounting'
  | 'finance'
  | 'directors';

export type RoleCredentials = {
  user: string;
  password: string;
};

export type TestConfig = {
  baseUrl: string;
  apiKey: string;
  apiSecret: string;
  roles: Map<RoleName, RoleCredentials>;
};

export type FrappeDoc = {
  name?: string;
  doctype?: string;
  [key: string]: unknown;
};

export type FrappeListOptions = {
  filters?: unknown[] | Record<string, unknown>;
  fields?: string[];
  limit?: number;
  orderBy?: string;
};

export type FrappeErrorKind = 'validation' | 'unexpected';

export class FrappeError extends Error {
  readonly status: number;
  readonly kind: FrappeErrorKind;
  readonly details: unknown;

  constructor(message: string, status: number, kind: FrappeErrorKind, details: unknown) {
    super(message);
    this.name = 'FrappeError';
    this.status = status;
    this.kind = kind;
    this.details = details;
  }
}

export type ManifestRecord = {
  doctype: string;
  name: string;
  purpose: string;
};

export type RunManifest = {
  runId: string;
  baseUrl: string;
  environment: string;
  startTime: string;
  endTime?: string;
  records: ManifestRecord[];
};

export type StepStatus = 'passed' | 'failed' | 'skipped' | 'blocked';

export type StepResult = {
  name: string;
  status: StepStatus;
  expected?: string;
  actual?: string;
  screenshotPath?: string;
  durationMs?: number;
  error?: string;
};

export type TestReport = {
  runId: string;
  scenarioName: string;
  environment: string;
  status: StepStatus;
  startTime: string;
  endTime: string;
  durationMs: number;
  steps: StepResult[];
  summary: Record<StepStatus, number>;
};

export type ConsoleEntry = {
  type: string;
  text: string;
  url?: string;
  timestamp: string;
};

export type NetworkEntry = {
  url: string;
  method: string;
  status?: number;
  failureText?: string;
  timestamp: string;
};
