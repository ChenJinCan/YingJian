import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = JSON.parse(
  await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8'),
);

test('production keeps workers.dev while exposing the managed custom domain', () => {
  assert.equal(config.workers_dev, true);
  assert.deepEqual(config.routes, [
    {
      pattern: 'yingjian-ai.520orz.com',
      custom_domain: true,
    },
  ]);
  assert.equal(
    config.vars.GENERATION_SESSION_ISSUER,
    'https://yingjian-ai.520orz.com',
  );
});
