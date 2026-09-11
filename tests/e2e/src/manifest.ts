import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { ManifestRecord, RunManifest } from './types.js';

export class Manifest {
  readonly data: RunManifest;

  constructor(runId: string, baseUrl: string) {
    this.data = {
      runId,
      baseUrl,
      environment: new URL(baseUrl).hostname,
      startTime: new Date().toISOString(),
      records: []
    };
  }

  track(doctype: string, name: string, purpose: string): void {
    this.data.records.push({ doctype, name, purpose });
  }

  async save(runDir: string): Promise<void> {
    this.data.endTime = new Date().toISOString();
    await mkdir(runDir, { recursive: true });
    await writeFile(join(runDir, 'run-manifest.json'), `${JSON.stringify(this.data, null, 2)}\n`, 'utf8');
  }
}
