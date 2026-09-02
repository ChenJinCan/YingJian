import { createHash, randomUUID } from 'node:crypto';

import { CAPABILITY_CONTRACTS } from '../domain/capability-contracts.mjs';
import { ProviderError } from '../providers/provider-error.mjs';
import { validateCapabilityMedia } from '../security/capability-media-policy.mjs';
import { CURRENT_POLICY_VERSION } from '../security/hmac-offer-authority.mjs';

const MAX_PRIVATE_MEDIA_BYTES = 25 * 1024 * 1024;
const DISPATCH_LEASE_MILLISECONDS = 2 * 60 * 1000;
const TERMINAL_STATES = new Set(['succeeded', 'failed', 'rejected', 'canceled']);

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function safeErrorCode(value, fallback = 'provider_error') {
  const code = String(value ?? '');
  return /^[a-z][a-z0-9_]{0,63}$/.test(code) ? code : fallback;
}

function json(status, body) {
  return Response.json(body, {
    status,
    headers: { 'cache-control': 'no-store' },
  });
}

function publicTask(task) {
  return {
    id: task.id,
    requestId: task.creationId,
    creationId: task.creationId,
    capability: task.capability,
    colorMode: task.colorMode,
    offerId: task.offerId,
    sourceMediaId: task.sourceMediaId,
    sourceSha256: task.sourceSha256,
    sourceUploadSha256: task.sourceUploadSha256,
    maskSha256: task.maskSha256,
    maskUploadSha256: task.maskUploadSha256,
    inputIdentity: task.inputIdentity,
    recipeVersion: task.recipeVersion,
    provider: task.provider,
    model: task.model,
    state: task.state,
    providerStatus: task.providerStatus,
    providerCancelable: task.providerCancelable,
    providerCancellation: task.providerCancellation,
    usageState: task.usageState,
    usageDisposition: task.usageDisposition,
    resultMediaId: task.resultMediaId,
    errorCode: task.errorCode,
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
  };
}

function requireString(value, code, maximumLength = 512) {
  if (
    typeof value !== 'string' ||
    value.trim().length === 0 ||
    value.length > maximumLength
  ) {
    throw new HttpError(400, code);
  }
  return value;
}

function requireSha256(value, code) {
  const digest = requireString(value, code, 64);
  if (!/^[a-f0-9]{64}$/.test(digest)) throw new HttpError(400, code);
  return digest;
}

function validateConsent(consent) {
  if (
    consent?.uploadConfirmed !== true ||
    consent?.costConfirmed !== true ||
    typeof consent?.offerId !== 'string' ||
    consent.offerId.length === 0 ||
    !Number.isInteger(consent?.policyVersion)
  ) {
    throw new HttpError(409, 'explicit_consent_required');
  }
}

async function readJson(request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) {
    throw new HttpError(415, 'json_content_type_required');
  }
  let body;
  try {
    body = await request.json();
  } catch {
    throw new HttpError(400, 'invalid_json');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'invalid_request');
  }
  return body;
}

function assertMethods(value, methods, name) {
  if (!value || methods.some((method) => typeof value[method] !== 'function')) {
    throw new TypeError(`${name} is required.`);
  }
}

export function createGenerationHttpHandler({
  authenticator,
  taskRepository,
  mediaStore,
  providers,
  offerAuthority,
  usageGuard,
  mediaRetentionHours = 24,
  dispatchReconciliationWindowMilliseconds = 60 * 60 * 1000,
  idFactory = randomUUID,
  dispatchIdFactory = randomUUID,
  mediaIdFactory = randomUUID,
  now = () => new Date(),
} = {}) {
  if (typeof authenticator !== 'function') {
    throw new TypeError('authenticator is required.');
  }
  assertMethods(
    taskRepository,
    ['reserve', 'compareAndSet', 'get', 'getByCreation'],
    'taskRepository',
  );
  assertMethods(
    mediaStore,
    ['resolveInput', 'storeProviderOutput'],
    'mediaStore',
  );
  if (!providers || typeof providers !== 'object') {
    throw new TypeError('providers are required.');
  }
  assertMethods(offerAuthority, ['issue', 'verify'], 'offerAuthority');
  assertMethods(
    usageGuard,
    [
      'reserveGeneration',
      'settleGeneration',
      'releaseGeneration',
      'reserveStorage',
      'commitStorage',
      'releaseStorage',
      'expireStorage',
    ],
    'usageGuard',
  );
  if (
    !Number.isInteger(mediaRetentionHours) ||
    mediaRetentionHours <= 0 ||
    mediaRetentionHours > 24
  ) {
    throw new TypeError('mediaRetentionHours must be an integer from 1 to 24.');
  }
  if (
    !Number.isInteger(dispatchReconciliationWindowMilliseconds) ||
    dispatchReconciliationWindowMilliseconds <= 0
  ) {
    throw new TypeError(
      'dispatchReconciliationWindowMilliseconds must be a positive integer.',
    );
  }

  function providerForContract(contract) {
    return providers[contract.executionProvider ?? contract.provider];
  }

  function providerForTask(task) {
    const contract = CAPABILITY_CONTRACTS[task.capability];
    return providers[
      task.executionProvider ??
        contract?.executionProvider ??
        task.provider
    ];
  }

  async function compareAndSet(task, changes) {
    const result = await taskRepository.compareAndSet({
      ownerId: task.ownerId,
      taskId: task.id,
      expectedVersion: task.version,
      task: {
        ...task,
        ...changes,
        updatedAt: changes.updatedAt ?? now().toISOString(),
      },
    });
    if (result.kind === 'missing') {
      throw new HttpError(404, 'task_not_found');
    }
    return result;
  }

  async function reconcileTerminalUsage(task) {
    if (task.usageState !== 'reserved' || !TERMINAL_STATES.has(task.state)) {
      return task;
    }
    let usageState;
    if (task.usageDisposition === 'settle') {
      await usageGuard.settleGeneration({
        ownerId: task.ownerId,
        reservationId: task.id,
      });
      usageState = 'settled';
    } else if (task.usageDisposition === 'release') {
      await usageGuard.releaseGeneration({
        ownerId: task.ownerId,
        reservationId: task.id,
      });
      usageState = 'released';
    } else {
      return task;
    }
    const result = await compareAndSet(task, { usageState });
    return result.task;
  }

  async function markDispatchReconciliation(task) {
    if (TERMINAL_STATES.has(task.state)) return task;
    const result = await compareAndSet(task, {
      state: 'failed',
      dispatchState: 'reconciliation_required',
      dispatchLeaseExpiresAt: null,
      errorCode: 'dispatch_reconciliation_required',
      providerCancelable: false,
      providerCancellation: 'not_available',
      usageDisposition: 'hold',
    });
    return result.task;
  }

  async function expireDispatchReconciliation(task) {
    if (
      task.dispatchState !== 'reconciliation_required' ||
      task.errorCode !== 'dispatch_reconciliation_required' ||
      task.providerTaskId ||
      task.usageState !== 'reserved' ||
      task.usageDisposition !== 'hold' ||
      !TERMINAL_STATES.has(task.state)
    ) {
      return task;
    }
    const updatedAt = Date.parse(task.updatedAt);
    if (
      !Number.isFinite(updatedAt) ||
      now().getTime() - updatedAt <=
        dispatchReconciliationWindowMilliseconds
    ) {
      return task;
    }
    const result = await compareAndSet(task, {
      dispatchState: 'reconciliation_expired',
      dispatchLeaseExpiresAt: null,
      errorCode: 'provider_outcome_unknown',
      providerCancelable: false,
      providerCancellation: 'not_available',
      usageDisposition: 'hold',
    });
    return result.task;
  }

  async function handleFindByCreation(ownerId, creationId, capability) {
    const confirmedCreationId = requireString(
      creationId,
      'creation_id_required',
    );
    const confirmedCapability = requireString(
      capability,
      'capability_required',
      64,
    );
    if (!CAPABILITY_CONTRACTS[confirmedCapability]) {
      throw new HttpError(400, 'unsupported_capability');
    }
    const task = await taskRepository.getByCreation({
      ownerId,
      creationKey: `${ownerId}:${confirmedCreationId}:${confirmedCapability}`,
    });
    if (!task) throw new HttpError(404, 'task_not_found');
    return handleObserve(ownerId, task.id);
  }

  async function recoverDispatchIntent(task) {
    const leaseExpiresAt = Date.parse(task.dispatchLeaseExpiresAt);
    if (Number.isFinite(leaseExpiresAt) && now().getTime() < leaseExpiresAt) {
      return task;
    }
    return markDispatchReconciliation(task);
  }

  async function storeProviderOutput({ ownerId, taskId, output }) {
    const storageReservationId = `provider-result:${taskId}`;
    return mediaStore.storeProviderOutput({
      ownerId,
      taskId,
      output,
      storageReservationId,
      reserveStorage: async ({ byteLength }) =>
        usageGuard.reserveStorage({
          ownerId,
          reservationId: storageReservationId,
          bytes: byteLength,
        }),
      commitStorage: async () =>
        usageGuard.commitStorage({ ownerId, reservationId: storageReservationId }),
      releaseStorage: async () =>
        usageGuard.releaseStorage({ ownerId, reservationId: storageReservationId }),
    });
  }

  async function handleUpload(request, ownerId) {
    if (typeof mediaStore.putSource !== 'function') {
      throw new HttpError(503, 'private_media_upload_not_configured');
    }
    const contentLength = Number(request.headers.get('content-length') ?? 0);
    if (Number.isFinite(contentLength) && contentLength > MAX_PRIVATE_MEDIA_BYTES) {
      throw new HttpError(413, 'media_too_large');
    }
    const mimeType = (request.headers.get('content-type') ?? '').split(';', 1)[0];
    const data = Buffer.from(await request.arrayBuffer());
    if (data.length === 0 || data.length > MAX_PRIVATE_MEDIA_BYTES) {
      throw new HttpError(413, 'media_size_invalid');
    }
    const claimedSha256 = request.headers.get('x-content-sha256');
    if (
      claimedSha256 !== null &&
      requireSha256(claimedSha256, 'media_sha256_invalid') !== sha256(data)
    ) {
      throw new HttpError(422, 'media_sha256_mismatch');
    }
    const mediaId = mediaIdFactory();
    await usageGuard.reserveStorage({
      ownerId,
      reservationId: mediaId,
      bytes: data.length,
    });
    let persisted = false;
    try {
      const stored = await mediaStore.putSource({ ownerId, mediaId, mimeType, data });
      persisted = true;
      await usageGuard.commitStorage({ ownerId, reservationId: mediaId });
      return json(201, {
        media: { id: stored.mediaId, sha256: stored.sha256 },
      });
    } catch (error) {
      if (!persisted) {
        await usageGuard.releaseStorage({ ownerId, reservationId: mediaId });
      }
      throw error;
    }
  }

  async function handleCapabilities(ownerId) {
    const capabilities = [];
    for (const [capability, contract] of Object.entries(CAPABILITY_CONTRACTS)) {
      const provider = providerForContract(contract);
      capabilities.push({
        capability,
        enabled:
          typeof provider?.submit === 'function' && provider.enabled !== false,
        provider: contract.provider,
        model: contract.model,
        recipeVersion: contract.recipeVersion,
        providerCancelable: provider?.cancelPolicy === 'pending-only',
        cancelBoundary:
          provider?.cancelPolicy === 'pending-only'
            ? 'provider_pending_only'
            : 'not_provider_cancelable',
        offer: await offerAuthority.issue({
          ownerId,
          capability,
          creditCost: contract.creditCost,
          policyVersion: CURRENT_POLICY_VERSION,
          now: now(),
        }),
      });
    }
    return json(200, { mediaRetentionHours, capabilities });
  }

  async function handleCancel(ownerId, taskId) {
    let task = await taskRepository.get({ ownerId, taskId });
    if (!task) throw new HttpError(404, 'task_not_found');
    if (TERMINAL_STATES.has(task.state)) {
      task = await expireDispatchReconciliation(task);
      task = await reconcileTerminalUsage(task);
      return json(200, { task: publicTask(task) });
    }
    if (task.dispatchState === 'result_importing') {
      return json(200, { task: publicTask(task) });
    }
    if (task.dispatchState === 'created') {
      const canceled = await compareAndSet(task, {
        state: 'canceled',
        providerCancelable: false,
        providerCancellation: 'local_before_dispatch',
        usageDisposition: 'release',
      });
      task = canceled.task;
      if (canceled.kind === 'updated') task = await reconcileTerminalUsage(task);
      return json(200, { task: publicTask(task) });
    }
    if (task.dispatchState === 'intent' && !task.providerTaskId) {
      task = await recoverDispatchIntent(task);
      return json(200, { task: publicTask(task) });
    }
    const provider = providerForTask(task);
    let providerStatus = task.providerStatus;
    let providerRequestId = task.providerRequestId;
    if (
      task.providerStatus === 'PENDING' &&
      provider?.cancelPolicy === 'pending-only' &&
      typeof provider.cancel === 'function'
    ) {
      const cancellation = await provider.cancel({
        providerTaskId: task.providerTaskId,
        providerStatus: task.providerStatus,
      });
      providerStatus = cancellation.providerStatus ?? task.providerStatus;
      providerRequestId =
        cancellation.providerRequestId ?? task.providerRequestId;
      if (cancellation.providerCancelled) {
        const canceled = await compareAndSet(task, {
          state: 'canceled',
          providerStatus: providerStatus ?? 'CANCELED',
          providerRequestId,
          providerCancellation: 'provider_confirmed',
          providerCancelable: false,
          usageDisposition: 'release',
        });
        task = canceled.task;
        if (canceled.kind === 'updated') task = await reconcileTerminalUsage(task);
        return json(200, { task: publicTask(task) });
      }
    }
    const remainsPending = providerStatus === 'PENDING';
    const result = await compareAndSet(task, {
      state: providerStatus === 'RUNNING' ? 'running' : task.state,
      providerStatus,
      providerRequestId,
      providerCancellation: remainsPending
        ? 'available_while_pending'
        : 'not_available',
      providerCancelable: remainsPending,
      usageDisposition: 'hold',
    });
    task = result.task;
    return json(200, { task: publicTask(task) });
  }

  async function handleObserve(ownerId, taskId) {
    let task = await taskRepository.get({ ownerId, taskId });
    if (!task) throw new HttpError(404, 'task_not_found');
    if (task.dispatchState === 'intent' && !task.providerTaskId) {
      task = await recoverDispatchIntent(task);
      return json(200, { task: publicTask(task) });
    }
    if (TERMINAL_STATES.has(task.state)) {
      task = await expireDispatchReconciliation(task);
      task = await reconcileTerminalUsage(task);
      return json(200, { task: publicTask(task) });
    }
    if (task.state !== 'pending' && task.state !== 'running') {
      return json(200, { task: publicTask(task) });
    }
    if (
      task.usageState === 'reserved' &&
      typeof usageGuard.touchGeneration === 'function'
    ) {
      await usageGuard.touchGeneration({
        ownerId: task.ownerId,
        reservationId: task.id,
      });
    }
    const provider = providerForTask(task);
    if (!provider || typeof provider.observe !== 'function') {
      throw new HttpError(503, 'capability_not_configured');
    }
    const providerResult = await provider.observe({
      providerTaskId: task.providerTaskId,
    });
    const observed = {
      providerStatus: providerResult.providerStatus,
      providerRequestId: providerResult.providerRequestId,
      providerCancelable: providerResult.providerCancelable,
    };
    if (providerResult.kind === 'succeeded') {
      const claim = await compareAndSet(task, {
        ...observed,
        dispatchState: 'result_importing',
        providerCancelable: false,
        providerCancellation: 'not_available',
      });
      if (claim.kind !== 'updated') {
        return json(200, { task: publicTask(claim.task) });
      }
      task = claim.task;
      let stored;
      try {
        stored = await storeProviderOutput({
          ownerId,
          taskId: task.id,
          output: providerResult.output,
        });
      } catch (error) {
        const failed = await compareAndSet(task, {
          state: 'failed',
          dispatchState: 'provider_recorded',
          errorCode: 'result_import_failed',
          usageDisposition: 'settle',
        });
        if (failed.kind === 'updated') await reconcileTerminalUsage(failed.task);
        throw error;
      }
      const completed = await compareAndSet(task, {
        state: 'succeeded',
        dispatchState: 'provider_recorded',
        resultMediaId: requireString(stored?.mediaId, 'result_media_store_failed'),
        usageDisposition: 'settle',
      });
      task = completed.task;
      if (completed.kind === 'updated') task = await reconcileTerminalUsage(task);
      return json(200, { task: publicTask(task) });
    }
    let changes;
    if (providerResult.kind === 'failed') {
      changes = {
        ...observed,
        state: 'failed',
        errorCode: 'provider_failed',
        providerCancellation: 'not_available',
        usageDisposition: 'release',
      };
    } else if (providerResult.kind === 'canceled') {
      changes = {
        ...observed,
        state: 'canceled',
        providerCancellation: 'provider_confirmed',
        usageDisposition: 'release',
      };
    } else if (providerResult.kind === 'running') {
      changes = {
        ...observed,
        state: 'running',
        providerCancellation: 'local_only',
      };
    } else {
      changes = {
        ...observed,
        state: 'pending',
        providerCancellation: 'available_while_pending',
      };
    }
    const updated = await compareAndSet(task, changes);
    task = updated.task;
    if (updated.kind === 'updated') task = await reconcileTerminalUsage(task);
    return json(200, { task: publicTask(task) });
  }

  async function handleCreate(request, ownerId) {
    const requestBody = await readJson(request);
    const creationId = requireString(requestBody.creationId, 'creation_id_required');
    const capability = requireString(requestBody.capability, 'capability_required');
    const sourceMediaId = requireString(
      requestBody.sourceMediaId,
      'source_media_id_required',
    );
    validateConsent(requestBody.consent);
    const contract = CAPABILITY_CONTRACTS[capability];
    if (!contract) throw new HttpError(400, 'unsupported_capability');
    const provider = providerForContract(contract);
    if (
      !provider ||
      typeof provider.submit !== 'function' ||
      provider.enabled === false
    ) {
      throw new HttpError(503, 'capability_not_configured');
    }
    const verifiedOffer = await offerAuthority.verify({
      offerId: requestBody.consent.offerId,
      ownerId,
      capability,
      policyVersion: requestBody.consent.policyVersion,
      now: now(),
    });
    if (verifiedOffer.creditCost !== contract.creditCost) {
      throw new HttpError(409, 'offer_mismatch');
    }

    const source = await mediaStore.resolveInput({
      ownerId,
      mediaId: sourceMediaId,
      purpose: 'source',
    });
    if (!/^[a-f0-9]{64}$/i.test(source?.sha256 ?? '')) {
      throw new HttpError(422, 'source_media_invalid');
    }
    const sourceUploadSha256 = requestBody.sourceUploadSha256 == null
      ? source.sha256
      : requireSha256(
          requestBody.sourceUploadSha256,
          'source_upload_sha256_required',
        );
    if (sourceUploadSha256 !== source.sha256) {
      throw new HttpError(422, 'source_upload_identity_mismatch');
    }
    const sourceSha256 = requestBody.sourceOriginalSha256 == null
      ? sourceUploadSha256
      : requireSha256(
          requestBody.sourceOriginalSha256,
          'source_original_sha256_required',
        );
    const providerInput = {
      capability,
      sourceUri: requireString(source.providerUri, 'source_media_invalid', 40_000_000),
    };
    let mask = null;
    let maskSha256 = null;
    let maskUploadSha256 = null;
    let inputIdentity = null;
    if (contract.requiresMask) {
      const maskMediaId = requireString(
        requestBody.maskMediaId,
        'mask_media_id_required',
      );
      mask = await mediaStore.resolveInput({
        ownerId,
        mediaId: maskMediaId,
        purpose: 'mask',
      });
      if (!/^[a-f0-9]{64}$/i.test(mask?.sha256 ?? '')) {
        throw new HttpError(422, 'mask_media_invalid');
      }
      maskUploadSha256 = requestBody.maskUploadSha256 == null
        ? mask.sha256
        : requireSha256(
            requestBody.maskUploadSha256,
            'mask_upload_sha256_required',
          );
      if (maskUploadSha256 !== mask.sha256) {
        throw new HttpError(422, 'mask_upload_identity_mismatch');
      }
      maskSha256 = requestBody.maskOriginalSha256 == null
        ? maskUploadSha256
        : requireSha256(
            requestBody.maskOriginalSha256,
            'mask_original_sha256_required',
          );
      inputIdentity = `mask-removal-v1:${maskSha256}`;
      providerInput.maskUri = requireString(
        mask.providerUri,
        'mask_media_invalid',
        40_000_000,
      );
    }
    validateCapabilityMedia({ capability, source, mask });

    let styleDefinitionSha256 = null;
    if (contract.requiresStyleDefinition) {
      const styleDefinition = requireString(
        requestBody.styleDefinition,
        'style_definition_required',
        4000,
      );
      if (requestBody.styleDefinitionConfirmed !== true) {
        throw new HttpError(409, 'style_definition_confirmation_required');
      }
      providerInput.styleDefinition = styleDefinition;
      styleDefinitionSha256 = sha256(styleDefinition);
      inputIdentity = `style-redraw-v1:${styleDefinitionSha256}`;
    }
    let colorMode = null;
    if (contract.requiresColorMode) {
      if (requestBody.colorMode !== 'preserve' && requestBody.colorMode !== 'colorize') {
        throw new HttpError(400, 'color_mode_required');
      }
      colorMode = requestBody.colorMode;
      inputIdentity = `old-photo-v1:${colorMode}`;
      providerInput.colorMode = colorMode;
    }

    const creationKey = `${ownerId}:${creationId}:${capability}`;
    const idempotencyKey = sha256(
      `${creationId}:${capability}:${sourceSha256}:${sourceUploadSha256}:${contract.recipeVersion}`,
    );
    const fingerprint = sha256(
      JSON.stringify({
        idempotencyKey,
        maskSha256,
        maskUploadSha256,
        sourceSha256,
        sourceUploadSha256,
        styleDefinitionSha256,
        colorMode,
        offerId: requestBody.consent.offerId,
        policyVersion: requestBody.consent.policyVersion,
        creditCost: verifiedOffer.creditCost,
      }),
    );
    const timestamp = now().toISOString();
    const proposedTask = {
      id: idFactory(),
      ownerId,
      creationId,
      creationKey,
      idempotencyKey,
      fingerprint,
      capability,
      colorMode,
      offerId: requestBody.consent.offerId,
      offerExpiresAt: verifiedOffer.expiresAt,
      policyVersion: CURRENT_POLICY_VERSION,
      creditCost: verifiedOffer.creditCost,
      sourceMediaId,
      inputIdentity,
      sourceSha256,
      sourceUploadSha256,
      maskSha256,
      maskUploadSha256,
      styleDefinitionSha256,
      recipeVersion: contract.recipeVersion,
      provider: contract.provider,
      executionProvider: contract.executionProvider ?? contract.provider,
      model: contract.model,
      providerTaskId: null,
      providerRequestId: null,
      providerStatus: null,
      providerCancelable: provider.cancelPolicy === 'pending-only',
      providerCancellation:
        provider.cancelPolicy === 'pending-only'
          ? 'available_while_pending'
          : 'not_available',
      dispatchAttemptId: null,
      dispatchState: 'created',
      dispatchLeaseExpiresAt: null,
      usageState: 'unreserved',
      usageDisposition: 'hold',
      state: 'created',
      resultMediaId: null,
      errorCode: null,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    const reservation = await taskRepository.reserve({
      creationKey,
      fingerprint,
      task: proposedTask,
    });
    if (reservation.kind === 'conflict') {
      throw new HttpError(409, 'idempotency_conflict');
    }
    let task = reservation.task;
    if (reservation.kind === 'existing') {
      if (task.dispatchState === 'intent' && !task.providerTaskId) {
        task = await recoverDispatchIntent(task);
        return json(200, { task: publicTask(task) });
      } else if (task.dispatchState !== 'created') {
        task = await expireDispatchReconciliation(task);
        task = await reconcileTerminalUsage(task);
        return json(200, { task: publicTask(task) });
      }
    }

    try {
      await usageGuard.reserveGeneration({
        ownerId,
        reservationId: task.id,
        fingerprint,
        creditCost: verifiedOffer.creditCost,
      });
    } catch (error) {
      // No provider request has occurred. Persist a terminal, non-billable
      // outcome so reconciliation never leaves an idempotency row looking
      // queued forever after a concurrency, credit, or rate-limit rejection.
      try {
        await compareAndSet(task, {
          state: 'rejected',
          dispatchState: 'provider_recorded',
          dispatchLeaseExpiresAt: null,
          errorCode: safeErrorCode(error?.code, 'usage_rejected'),
          providerCancelable: false,
          providerCancellation: 'not_available',
          usageDisposition: 'release',
        });
      } catch {
        // The original usage error remains the response. A later lookup reads
        // the durable task row and never resubmits this creation identity.
      }
      throw error;
    }
    let persisted = await compareAndSet(task, {
      usageState: 'reserved',
      dispatchState: 'intent',
      dispatchAttemptId: task.dispatchAttemptId ?? dispatchIdFactory(),
      dispatchLeaseExpiresAt: new Date(
        now().getTime() + DISPATCH_LEASE_MILLISECONDS,
      ).toISOString(),
    });
    if (persisted.kind !== 'updated') {
      task = persisted.task;
      if (task.dispatchState === 'intent') task = await recoverDispatchIntent(task);
      return json(reservation.kind === 'created' ? 201 : 200, {
        task: publicTask(task),
      });
    }
    task = persisted.task;

    try {
      const providerResult = await provider.submit(providerInput);
      if (providerResult.kind === 'succeeded') {
        let stored;
        try {
          stored = await storeProviderOutput({
            ownerId,
            taskId: task.id,
            output: providerResult.output,
          });
        } catch (error) {
          const failed = await compareAndSet(task, {
            providerRequestId: providerResult.providerRequestId,
            providerStatus: 'SUCCEEDED',
            providerCancelable: false,
            providerCancellation: 'not_available',
            dispatchState: 'provider_recorded',
            dispatchLeaseExpiresAt: null,
            state: 'failed',
            errorCode: 'result_import_failed',
            usageDisposition: 'settle',
          });
          task = failed.task;
          if (failed.kind === 'updated') task = await reconcileTerminalUsage(task);
          throw new HttpError(502, 'result_import_failed');
        }
        persisted = await compareAndSet(task, {
          providerRequestId: providerResult.providerRequestId,
          providerStatus: 'SUCCEEDED',
          providerCancelable: false,
          providerCancellation: 'not_available',
          dispatchState: 'provider_recorded',
          dispatchLeaseExpiresAt: null,
          state: 'succeeded',
          resultMediaId: requireString(stored?.mediaId, 'result_media_store_failed'),
          usageDisposition: 'settle',
        });
      } else if (providerResult.kind === 'accepted') {
        persisted = await compareAndSet(task, {
          providerRequestId: providerResult.providerRequestId,
          providerTaskId: requireString(
            providerResult.providerTaskId,
            'provider_invalid_response',
          ),
          providerStatus: providerResult.providerStatus,
          providerCancelable: providerResult.providerCancelable,
          dispatchState: 'provider_recorded',
          dispatchLeaseExpiresAt: null,
          state: providerResult.providerStatus === 'RUNNING' ? 'running' : 'pending',
        });
      } else {
        throw new ProviderError('Provider returned an unsupported task result.', {
          code: 'provider_invalid_response',
        });
      }
      task = persisted.task;
      if (persisted.kind !== 'updated') {
        throw new HttpError(502, 'dispatch_reconciliation_required');
      }
      task = await reconcileTerminalUsage(task);
      return json(201, { task: publicTask(task) });
    } catch (error) {
      if (!TERMINAL_STATES.has(task.state)) {
        const shouldRelease =
          error?.billingDisposition === 'release' || error?.code === 'capability_disabled';
        try {
          const failed = await compareAndSet(task, {
            state: error?.code === 'capability_disabled' ? 'rejected' : 'failed',
            dispatchState: shouldRelease
              ? 'provider_recorded'
              : 'reconciliation_required',
            dispatchLeaseExpiresAt: null,
            errorCode: shouldRelease
              ? safeErrorCode(error?.code)
              : 'dispatch_reconciliation_required',
            providerCancelable: false,
            providerCancellation: 'not_available',
            usageDisposition: shouldRelease ? 'release' : 'hold',
          });
          if (failed.kind === 'updated' && shouldRelease) {
            await reconcileTerminalUsage(failed.task);
          }
        } catch {
          // The durable dispatch intent remains the fail-closed recovery record.
        }
      }
      if (error instanceof HttpError) throw error;
      if (error?.billingDisposition === 'release') throw error;
      throw new HttpError(502, 'dispatch_reconciliation_required');
    }
  }

  return async function handleGenerationRequest(request) {
    try {
      const identity = await authenticator(request);
      if (typeof identity?.ownerId !== 'string' || identity.ownerId.length === 0) {
        throw new HttpError(401, 'unauthorized');
      }
      const ownerId = identity.ownerId;
      const url = new URL(request.url);
      if (request.method === 'POST' && url.pathname === '/v1/private-media') {
        return await handleUpload(request, ownerId);
      }
      const mediaMatch = /^\/v1\/private-media\/([^/]+)$/.exec(url.pathname);
      if (request.method === 'GET' && mediaMatch) {
        if (typeof mediaStore.read !== 'function') {
          throw new HttpError(503, 'private_media_download_not_configured');
        }
        const media = await mediaStore.read({
          ownerId,
          mediaId: decodeURIComponent(mediaMatch[1]),
        });
        const mediaKind = media.mediaKind ?? 'image';
        if (mediaKind !== 'image' && mediaKind !== 'imageMotion') {
          throw new HttpError(502, 'private_media_metadata_invalid');
        }
        if (
          !Number.isInteger(media.width) ||
          !Number.isInteger(media.height) ||
          media.width <= 0 ||
          media.height <= 0
        ) {
          throw new HttpError(502, 'private_media_metadata_invalid');
        }
        if (
          mediaKind === 'imageMotion' &&
          (!Number.isInteger(media.durationMilliseconds) ||
            media.durationMilliseconds <= 0)
        ) {
          throw new HttpError(502, 'private_media_metadata_invalid');
        }
        return new Response(media.data, {
          status: 200,
          headers: {
            'cache-control': 'no-store',
            'content-type': media.mimeType,
            'x-content-sha256': media.sha256,
            'x-media-kind': mediaKind,
            'x-media-width': String(media.width),
            'x-media-height': String(media.height),
            ...(mediaKind === 'imageMotion'
              ? {
                  'x-media-duration-ms': String(media.durationMilliseconds),
                  'x-media-codec': String(media.codec ?? ''),
                }
              : {}),
          },
        });
      }
      if (request.method === 'GET' && url.pathname === '/v1/generation-capabilities') {
        return await handleCapabilities(ownerId);
      }
      const cancelMatch = /^\/v1\/generation-tasks\/([^/]+)\/cancel$/.exec(
        url.pathname,
      );
      if (request.method === 'POST' && cancelMatch) {
        return await handleCancel(ownerId, decodeURIComponent(cancelMatch[1]));
      }
      const creationMatch =
        /^\/v1\/generation-tasks\/by-creation\/([^/]+)$/.exec(url.pathname);
      if (request.method === 'GET' && creationMatch) {
        return await handleFindByCreation(
          ownerId,
          decodeURIComponent(creationMatch[1]),
          url.searchParams.get('capability'),
        );
      }
      const taskMatch = /^\/v1\/generation-tasks\/([^/]+)$/.exec(url.pathname);
      if (request.method === 'GET' && taskMatch) {
        return await handleObserve(ownerId, decodeURIComponent(taskMatch[1]));
      }
      if (request.method === 'POST' && url.pathname === '/v1/generation-tasks') {
        return await handleCreate(request, ownerId);
      }
      throw new HttpError(404, 'not_found');
    } catch (error) {
      if (
        error instanceof HttpError ||
        error instanceof ProviderError ||
        (Number.isInteger(error?.status) && typeof error?.code === 'string')
      ) {
        return json(error.status ?? 502, {
          error: { code: safeErrorCode(error.code) },
        });
      }
      return json(500, { error: { code: 'internal_error' } });
    }
  };
}
