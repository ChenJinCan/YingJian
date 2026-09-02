import { isAbsolute, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import { createGenerationHttpHandler } from './http/generation-http-handler.mjs';
import { FilePrivateMediaStore } from './infrastructure/file-private-media-store.mjs';
import { FileTaskRepository } from './infrastructure/file-task-repository.mjs';
import { createLocalSharedBearerAuthenticator } from './infrastructure/local-shared-bearer-authenticator.mjs';
import {
  BaiduImageRepairProvider,
  createBaiduAccessTokenProvider,
} from './providers/baidu-image-repair.mjs';
import { AlibabaImageProvider } from './providers/alibaba-image.mjs';
import { AlibabaImageToVideoProvider } from './providers/alibaba-image-to-video.mjs';
import { VolcengineOldPhotoProvider } from './providers/volcengine-old-photo.mjs';
import { HmacOfferAuthority } from './security/hmac-offer-authority.mjs';
import { LocalFixedUsageGuard } from './security/local-fixed-usage-guard.mjs';
import { createAlibabaResultDownloader } from './security/restricted-result-downloader.mjs';

function requiredEnvironment(env, name) {
  const value = env[name];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function assertLoopbackEvaluation(env) {
  const host = env.GENERATION_HOST || '127.0.0.1';
  if (host !== '127.0.0.1' && host !== '::1' && host !== 'localhost') {
    throw new Error('Local evaluation authentication and guards require loopback.');
  }
}

async function loadAuthenticator(env) {
  if (env.GENERATION_AUTH_MODULE) {
    const modulePath = isAbsolute(env.GENERATION_AUTH_MODULE)
      ? env.GENERATION_AUTH_MODULE
      : resolve(process.cwd(), env.GENERATION_AUTH_MODULE);
    const authenticationModule = await import(pathToFileURL(modulePath).href);
    const authenticator =
      typeof authenticationModule.createAuthenticator === 'function'
        ? await authenticationModule.createAuthenticator()
        : authenticationModule.authenticate;
    if (typeof authenticator !== 'function') {
      throw new Error(
        'GENERATION_AUTH_MODULE must export authenticate or createAuthenticator.',
      );
    }
    return authenticator;
  }
  if (env.GENERATION_ALLOW_SHARED_BEARER_AUTH === 'true') {
    assertLoopbackEvaluation(env);
    return createLocalSharedBearerAuthenticator({
      bearerToken: requiredEnvironment(env, 'GENERATION_LOCAL_BEARER_TOKEN'),
      ownerId: requiredEnvironment(env, 'GENERATION_LOCAL_OWNER_ID'),
    });
  }
  throw new Error(
    'No authenticator configured. Set GENERATION_AUTH_MODULE; shared bearer auth is local evaluation only.',
  );
}

function requiredPositiveInteger(env, name) {
  const value = Number(requiredEnvironment(env, name));
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return value;
}

function mediaRetentionHours(env) {
  if (!env.GENERATION_MEDIA_RETENTION_HOURS) return 24;
  const value = Number(env.GENERATION_MEDIA_RETENTION_HOURS);
  if (!Number.isInteger(value) || value < 1 || value > 24) {
    throw new Error(
      'GENERATION_MEDIA_RETENTION_HOURS must be an integer from 1 to 24.',
    );
  }
  return value;
}

async function loadUsageGuard(env) {
  if (env.GENERATION_GUARD_MODULE) {
    const modulePath = isAbsolute(env.GENERATION_GUARD_MODULE)
      ? env.GENERATION_GUARD_MODULE
      : resolve(process.cwd(), env.GENERATION_GUARD_MODULE);
    const guardModule = await import(pathToFileURL(modulePath).href);
    const usageGuard =
      typeof guardModule.createUsageGuard === 'function'
        ? await guardModule.createUsageGuard()
        : guardModule.usageGuard;
    if (!usageGuard || typeof usageGuard !== 'object') {
      throw new Error(
        'GENERATION_GUARD_MODULE must export usageGuard or createUsageGuard.',
      );
    }
    return usageGuard;
  }
  if (env.GENERATION_ALLOW_SHARED_BEARER_AUTH === 'true') {
    assertLoopbackEvaluation(env);
    return new LocalFixedUsageGuard({
      maxCreditsPerOwner: requiredPositiveInteger(
        env,
        'GENERATION_LOCAL_MAX_CREDITS',
      ),
      maxConcurrentGenerationsPerOwner: requiredPositiveInteger(
        env,
        'GENERATION_LOCAL_MAX_CONCURRENT',
      ),
      maxGenerationReservationsPerWindow: requiredPositiveInteger(
        env,
        'GENERATION_LOCAL_MAX_RESERVATIONS_PER_WINDOW',
      ),
      rateWindowMilliseconds: requiredPositiveInteger(
        env,
        'GENERATION_LOCAL_RATE_WINDOW_MS',
      ),
      maxStorageBytesPerOwner: requiredPositiveInteger(
        env,
        'GENERATION_LOCAL_MAX_STORAGE_BYTES',
      ),
    });
  }
  throw new Error(
    'No production usage guard configured. Set GENERATION_GUARD_MODULE.',
  );
}

export async function createGenerationRuntime({
  env = process.env,
  fetchImpl = globalThis.fetch,
} = {}) {
  const authenticator = await loadAuthenticator(env);
  const usageGuard = await loadUsageGuard(env);
  const retentionHours = mediaRetentionHours(env);
  const dispatchReconciliationWindowMilliseconds =
    env.GENERATION_LOCAL_RATE_WINDOW_MS == null
      ? 60 * 60 * 1000
      : requiredPositiveInteger(env, 'GENERATION_LOCAL_RATE_WINDOW_MS');
  const offerAuthority = new HmacOfferAuthority({
    signingKey: requiredEnvironment(env, 'GENERATION_OFFER_SIGNING_KEY'),
  });
  const taskRepository = new FileTaskRepository({
    rootDirectory: requiredEnvironment(env, 'GENERATION_TASK_DIRECTORY'),
  });
  const mediaStore = new FilePrivateMediaStore({
    rootDirectory: requiredEnvironment(env, 'GENERATION_MEDIA_DIRECTORY'),
    remoteDownloader: createAlibabaResultDownloader(),
    retentionMilliseconds: retentionHours * 60 * 60 * 1000,
    onExpired: ({ ownerId, reservationId }) =>
      usageGuard.expireStorage({ ownerId, reservationId }),
  });
  await mediaStore.initializeExpirationSweep();
  const providers = {};
  if (env.BAIDU_IMAGE_REPAIR_ENABLED === 'true') {
    const baiduAccessToken = createBaiduAccessTokenProvider({
      apiKey: requiredEnvironment(env, 'BAIDU_API_KEY'),
      secretKey: requiredEnvironment(env, 'BAIDU_SECRET_KEY'),
      fetchImpl,
    });
    providers.baidu = new BaiduImageRepairProvider({
      accessTokenProvider: baiduAccessToken,
      fetchImpl,
    });
  }
  if (env.ALIBABA_IMAGE_ENABLED === 'true') {
    providers.alibaba = new AlibabaImageProvider({
      apiKey: requiredEnvironment(env, 'ALIBABA_DASHSCOPE_API_KEY'),
      workspaceId: requiredEnvironment(env, 'ALIBABA_WORKSPACE_ID'),
      fetchImpl,
    });
  }
  if (env.ALIBABA_VIDEO_ENABLED === 'true') {
    providers.alibabaMotion = new AlibabaImageToVideoProvider({
      apiKey: requiredEnvironment(env, 'ALIBABA_DASHSCOPE_API_KEY'),
      workspaceId: requiredEnvironment(env, 'ALIBABA_WORKSPACE_ID'),
      fetchImpl,
    });
  }
  if (env.VOLC_LENS_OPR_ENABLED === 'true') {
    providers.volcengine = new VolcengineOldPhotoProvider({
      enabled: true,
      accessKeyId: requiredEnvironment(env, 'VOLC_ACCESS_KEY_ID'),
      secretAccessKey: requiredEnvironment(env, 'VOLC_SECRET_ACCESS_KEY'),
      fetchImpl,
    });
  }
  return {
    handler: createGenerationHttpHandler({
      authenticator,
      taskRepository,
      mediaStore,
      providers,
      offerAuthority,
      usageGuard,
      mediaRetentionHours: retentionHours,
      dispatchReconciliationWindowMilliseconds,
    }),
    mediaStore,
    close: () => mediaStore.close(),
  };
}
