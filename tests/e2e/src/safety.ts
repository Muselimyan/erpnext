const productionHost = 'erpnext.am';
const allowedHost = 'test.erpnext.am';

export function validateEnvironment(baseUrl: string): URL {
  let parsed: URL;

  try {
    parsed = new URL(baseUrl);
  } catch {
    throw new Error(`REFUSED: invalid URL ${baseUrl}`);
  }

  if (parsed.hostname === productionHost) {
    throw new Error('REFUSED: production URL');
  }

  if (parsed.hostname !== allowedHost) {
    throw new Error(`REFUSED: unknown host ${parsed.hostname}`);
  }

  if (parsed.protocol !== 'https:') {
    throw new Error(`REFUSED: non-HTTPS URL ${baseUrl}`);
  }

  return parsed;
}
