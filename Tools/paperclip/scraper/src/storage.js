// Output writer. Persists the per-run handoff JSON that the BDR Paperclip agent
// reads. The schema is intentionally tiny and stable so BDR can rely on it
// without us versioning a separate contract.

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_OUTPUT_PATH = path.join(__dirname, '..', 'output', 'raw-prospects.json');

export async function writeOutput({ sessionId, magnetsUsed, stats, prospects, outputPath = DEFAULT_OUTPUT_PATH }) {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  const payload = {
    version: 1,
    scraped_at: new Date().toISOString(),
    session_id: sessionId,
    magnets_used: magnetsUsed,
    stats,
    prospects,
  };
  await fs.writeFile(outputPath, JSON.stringify(payload, null, 2));
  return outputPath;
}

export const OUTPUT_PATH = DEFAULT_OUTPUT_PATH;
