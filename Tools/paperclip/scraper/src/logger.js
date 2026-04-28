// Per-run structured JSON logger. Writes a single .log file per session,
// one JSON object per line. Also mirrors to stdout in human-readable form so
// the operator can watch a run live.

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOG_DIR = path.join(__dirname, '..', 'logs');

export async function createLogger(sessionId) {
  await fs.mkdir(LOG_DIR, { recursive: true });
  const logFile = path.join(LOG_DIR, `${sessionId}.log`);

  async function write(level, msg, meta = {}) {
    const ts = new Date().toISOString();
    const line = JSON.stringify({ ts, level, msg, ...meta }) + '\n';
    try {
      await fs.appendFile(logFile, line);
    } catch (e) {
      // If the log file write fails, do not crash the run
      process.stderr.write(`[logger error] ${e.message}\n`);
    }
    process.stdout.write(`[${level.toUpperCase()}] ${msg}\n`);
  }

  return {
    info: (msg, meta) => write('info', msg, meta),
    warn: (msg, meta) => write('warn', msg, meta),
    error: (msg, meta) => write('error', msg, meta),
    file: logFile,
  };
}
