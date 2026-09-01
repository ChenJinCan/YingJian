import assert from 'node:assert/strict';
import test from 'node:test';

import { validateCapabilityMedia } from '../src/security/capability-media-policy.mjs';

const validSource = {
  byteLength: 1024,
  width: 1024,
  height: 1024,
  format: 'jpeg',
  isBlackWhite: false,
};

test('capability media policy enforces provider dimensions and byte limits', () => {
  assert.doesNotThrow(() =>
    validateCapabilityMedia({ capability: 'optimizeAiRepair', source: validSource }),
  );
  assert.throws(
    () =>
      validateCapabilityMedia({
        capability: 'optimizeAiRepair',
        source: { ...validSource, width: 5001 },
      }),
    (error) => error.code === 'source_dimensions_unsupported' && error.status === 422,
  );
  assert.throws(
    () =>
      validateCapabilityMedia({
        capability: 'styleAiRedraw',
        source: { ...validSource, byteLength: 20 * 1024 * 1024 + 1 },
      }),
    (error) => error.code === 'source_media_too_large' && error.status === 422,
  );
  assert.throws(
    () =>
      validateCapabilityMedia({
        capability: 'optimizeAiRepair',
        source: { ...validSource, byteLength: 8 * 1024 * 1024 },
      }),
    (error) => error.code === 'source_media_too_large',
  );
  assert.throws(
    () =>
      validateCapabilityMedia({
        capability: 'optimizeAiRepair',
        source: { ...validSource, format: 'webp' },
      }),
    (error) => error.code === 'source_format_unsupported',
  );
});

test('cleanup mask must be PNG, binary black-white, and source-sized', () => {
  const source = { ...validSource, format: 'png' };
  const mask = { ...source, isBlackWhite: true };
  assert.doesNotThrow(() =>
    validateCapabilityMedia({
      capability: 'cleanupBrushRemove',
      source,
      mask,
    }),
  );
  for (const [change, code] of [
    [{ format: 'jpeg' }, 'mask_png_required'],
    [{ isBlackWhite: false }, 'mask_black_white_required'],
    [{ width: 1023 }, 'mask_dimensions_mismatch'],
  ]) {
    assert.throws(
      () =>
        validateCapabilityMedia({
          capability: 'cleanupRemovePasserby',
          source,
          mask: { ...mask, ...change },
        }),
      (error) => error.code === code,
    );
  }
});
