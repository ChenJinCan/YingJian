import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';

const DATABASE_NAME = 'yingjian-generation-production';
const CREDIT_LIMIT = 5;
const LIFETIME_MILLISECONDS = 10 * 60 * 1000;

const code = randomBytes(32).toString('base64url');
const codeHash = createHash('sha256').update(code).digest('hex');
const expiresAt = Date.now() + LIFETIME_MILLISECONDS;
const sql =
  `INSERT INTO enrollment_codes ` +
  `(code_hash, expires_at_ms, credit_limit, bound_key_id, ` +
  `bound_installation_id, consumed_at_ms) VALUES ` +
  `('${codeHash}', ${expiresAt}, ${CREDIT_LIMIT}, NULL, NULL, NULL);`;

const wrangler = spawn(
  'npx',
  [
    'wrangler',
    'd1',
    'execute',
    DATABASE_NAME,
    '--remote',
    '--command',
    sql,
  ],
  {
    cwd: new URL('../..', import.meta.url),
    env: process.env,
    stdio: ['ignore', 'ignore', 'pipe'],
  },
);

let failureOutputBytes = 0;
wrangler.stderr.on('data', (chunk) => {
  // Drain output so Wrangler cannot block. Never echo provider/account details.
  failureOutputBytes += chunk.length;
});

wrangler.once('error', () => {
  process.stderr.write('Enrollment provisioning could not start.\n');
  process.exitCode = 1;
});

wrangler.once('exit', (status) => {
  if (status !== 0) {
    process.stderr.write(
      `Enrollment provisioning failed (${failureOutputBytes > 0 ? 'details suppressed' : 'no details'}).\n`,
    );
    process.exitCode = 1;
    return;
  }
  process.stdout.write(
    `yingjian://generation-activate?code=${encodeURIComponent(code)}\n`,
  );
});
