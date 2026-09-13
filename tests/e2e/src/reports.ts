import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import type { ConsoleEntry, NetworkEntry, StepStatus, TestReport } from './types.js';

export async function createRunDir(label: string): Promise<string> {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const runDir = resolve(process.cwd(), '..', '..', 'ERPNext-Automation-Reports', `${timestamp}_${label}`);
  await mkdir(join(runDir, 'screenshots'), { recursive: true });
  await mkdir(join(runDir, 'dom'), { recursive: true });
  await mkdir(join(runDir, 'traces'), { recursive: true });
  await mkdir(join(runDir, 'videos'), { recursive: true });
  await mkdir(join(runDir, 'downloads'), { recursive: true });
  return runDir;
}

export function buildSummary(statuses: StepStatus[]): Record<StepStatus, number> {
  return {
    passed: statuses.filter((status) => status === 'passed').length,
    failed: statuses.filter((status) => status === 'failed').length,
    skipped: statuses.filter((status) => status === 'skipped').length,
    blocked: statuses.filter((status) => status === 'blocked').length
  };
}

export async function writeReport(runDir: string, report: TestReport): Promise<void> {
  await mkdir(runDir, { recursive: true });
  await writeFile(join(runDir, 'report.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  await writeFile(join(runDir, 'report.html'), renderHtml(report), 'utf8');
}

export async function writeJsonLines<T extends ConsoleEntry | NetworkEntry>(runDir: string, fileName: string, entries: T[]): Promise<void> {
  const content = entries.map((entry) => JSON.stringify(entry)).join('\n');
  await writeFile(join(runDir, fileName), content ? `${content}\n` : '', 'utf8');
}

function renderHtml(report: TestReport): string {
  const rows = report.steps
    .map(
      (step) => `<tr><td>${escapeHtml(step.name)}</td><td>${step.status}</td><td>${escapeHtml(step.expected || '')}</td><td>${escapeHtml(step.actual || '')}</td><td>${escapeHtml(step.error || '')}</td></tr>`
    )
    .join('');

  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(report.scenarioName)}</title><style>body{font-family:Arial,sans-serif;margin:24px}.passed{color:#0a7f35}.failed,.blocked{color:#b00020}.skipped{color:#8a6d00}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ddd;padding:8px;text-align:left}</style></head><body><h1>${escapeHtml(report.scenarioName)}</h1><h2 class="${report.status}">${report.status.toUpperCase()}</h2><p><strong>Environment:</strong> ${escapeHtml(report.environment)}</p><p><strong>Run:</strong> ${escapeHtml(report.runId)}</p><table><thead><tr><th>Step</th><th>Status</th><th>Expected</th><th>Actual</th><th>Error</th></tr></thead><tbody>${rows}</tbody></table></body></html>`;
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
