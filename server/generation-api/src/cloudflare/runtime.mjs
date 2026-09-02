import { createGenerationHttpHandler } from '../http/generation-http-handler.mjs';
import { D1TaskRepository } from '../infrastructure/d1-task-repository.mjs';
import { R2PrivateMediaStore } from '../infrastructure/r2-private-media-store.mjs';
import { AlibabaImageProvider } from '../providers/alibaba-image.mjs';
import { AlibabaImageToVideoProvider } from '../providers/alibaba-image-to-video.mjs';
import {
  BaiduImageRepairProvider,
  createBaiduAccessTokenProvider,
} from '../providers/baidu-image-repair.mjs';
import { VolcengineOldPhotoProvider } from '../providers/volcengine-old-photo.mjs';
import { D1UsageGuard } from '../security/d1-usage-guard.mjs';
import { HmacOfferAuthority } from '../security/hmac-offer-authority.mjs';
import { createCloudflareAlibabaResultDownloader } from './alibaba-result-downloader.mjs';
import { createCloudflareSessionSecurity } from './session-security.mjs';

function requiredEnvironment(env, name) {
  const value = env[name];
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function requiredPositiveInteger(env, name) {
  const value = Number(requiredEnvironment(env, name));
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return value;
}

function mediaRetentionHours(env) {
  const value = Number(env.GENERATION_MEDIA_RETENTION_HOURS ?? 24);
  if (!Number.isInteger(value) || value < 1 || value > 24) {
    throw new Error(
      'GENERATION_MEDIA_RETENTION_HOURS must be an integer from 1 to 24.',
    );
  }
  return value;
}

function requireD1(database) {
  if (
    !database ||
    typeof database.prepare !== 'function' ||
    typeof database.batch !== 'function'
  ) {
    throw new Error('DB D1 binding is required.');
  }
  return database;
}

function requireR2(bucket) {
  if (
    !bucket ||
    typeof bucket.put !== 'function' ||
    typeof bucket.get !== 'function' ||
    typeof bucket.list !== 'function'
  ) {
    throw new Error('MEDIA R2 binding is required.');
  }
  return bucket;
}

export function createCloudflareGenerationRuntime({
  env,
  fetchImpl = globalThis.fetch,
  now = () => new Date(),
} = {}) {
  if (!env || typeof env !== 'object') throw new TypeError('env is required.');
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('fetchImpl is required.');
  }
  const database = requireD1(env.DB);
  const bucket = requireR2(env.MEDIA);
  const retentionHours = mediaRetentionHours(env);
  const maxCreditsPerOwner = requiredPositiveInteger(
    env,
    'GENERATION_MAX_CREDITS',
  );
  const rateWindowMilliseconds = requiredPositiveInteger(
    env,
    'GENERATION_RATE_WINDOW_MS',
  );
  const usageGuard = new D1UsageGuard({
    database,
    maxCreditsPerOwner,
    maxConcurrentGenerationsPerOwner: requiredPositiveInteger(
      env,
      'GENERATION_MAX_CONCURRENT',
    ),
    maxGenerationReservationsPerWindow: requiredPositiveInteger(
      env,
      'GENERATION_MAX_RESERVATIONS_PER_WINDOW',
    ),
    maxGlobalGenerationReservationsPerWindow: requiredPositiveInteger(
      env,
      'GENERATION_MAX_GLOBAL_RESERVATIONS_PER_WINDOW',
    ),
    rateWindowMilliseconds,
    activeReservationWindowMilliseconds: rateWindowMilliseconds,
    maxStorageBytesPerOwner: requiredPositiveInteger(
      env,
      'GENERATION_MAX_STORAGE_BYTES',
    ),
    now,
  });
  const sessionSecurity = createCloudflareSessionSecurity({
    database,
    signingKey: requiredEnvironment(env, 'GENERATION_SESSION_SIGNING_KEY'),
    issuer: requiredEnvironment(env, 'GENERATION_SESSION_ISSUER'),
    installationCreditLimit: maxCreditsPerOwner,
    now,
  });
  const taskRepository = new D1TaskRepository({ database });
  const mediaStore = new R2PrivateMediaStore({
    bucket,
    remoteDownloader: createCloudflareAlibabaResultDownloader({ fetchImpl }),
    retentionMilliseconds: retentionHours * 60 * 60 * 1000,
    now,
    onExpired: ({ ownerId, reservationId }) =>
      usageGuard.expireStorage({ ownerId, reservationId }),
  });
  const providers = {};
  if (env.BAIDU_IMAGE_REPAIR_ENABLED === 'true') {
    providers.baidu = new BaiduImageRepairProvider({
      accessTokenProvider: createBaiduAccessTokenProvider({
        apiKey: requiredEnvironment(env, 'BAIDU_API_KEY'),
        secretKey: requiredEnvironment(env, 'BAIDU_SECRET_KEY'),
        fetchImpl,
        now,
      }),
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
      now,
    });
  }
  const offerAuthority = new HmacOfferAuthority({
    signingKey: requiredEnvironment(env, 'GENERATION_OFFER_SIGNING_KEY'),
  });
  return {
    handler: createGenerationHttpHandler({
      authenticator: sessionSecurity.authenticate,
      taskRepository,
      mediaStore,
      providers,
      offerAuthority,
      usageGuard,
      mediaRetentionHours: retentionHours,
      dispatchReconciliationWindowMilliseconds: rateWindowMilliseconds,
      now,
    }),
    mediaStore,
    sessionSecurity,
  };
}
