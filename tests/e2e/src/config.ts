import { config as loadEnv } from 'dotenv';
import { resolve } from 'node:path';
import { validateEnvironment } from './safety.js';
import type { RoleCredentials, RoleName, TestConfig } from './types.js';

loadEnv({ path: resolve(process.cwd(), '.env.local') });

function requireEnv(name: string): string {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

function optionalEnv(name: string): string | undefined {
  return process.env[name] || undefined;
}

function role(userName: string, passwordName: string): RoleCredentials {
  return {
    user: requireEnv(userName),
    password: requireEnv(passwordName)
  };
}

function optionalRole(userName: string, passwordName: string): RoleCredentials | null {
  const user = optionalEnv(userName);
  const password = optionalEnv(passwordName);
  return user && password ? { user, password } : null;
}

export function getConfig(): TestConfig {
  const baseUrl = requireEnv('BASE_URL');
  validateEnvironment(baseUrl);

  const roles = new Map<RoleName, RoleCredentials>([
    ['orderAccepting', role('USER_ORDER_ACCEPTING', 'PASS_ORDER_ACCEPTING')],
    ['orderCreating', role('USER_ORDER_CREATING', 'PASS_ORDER_CREATING')],
    ['inventory', role('USER_INVENTORY', 'PASS_INVENTORY')],
    ['delivery', role('USER_DELIVERY', 'PASS_DELIVERY')],
    ['returns', role('USER_RETURNS', 'PASS_RETURNS')],
    ['accounting', role('USER_ACCOUNTING', 'PASS_ACCOUNTING')],
    ['finance', role('USER_FINANCE', 'PASS_FINANCE')],
    ['directors', role('USER_DIRECTORS', 'PASS_DIRECTORS')]
  ]);
  const purchasing = optionalRole('USER_PURCHASING', 'PASS_PURCHASING');
  if (purchasing) roles.set('purchasing', purchasing);

  return {
    baseUrl,
    apiKey: optionalEnv('API_KEY'),
    apiSecret: optionalEnv('API_SECRET'),
    roles
  };
}
