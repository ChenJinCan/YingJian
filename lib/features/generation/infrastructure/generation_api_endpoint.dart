/// Stable first-party origins used by released generation clients.
abstract final class GenerationApiEndpoint {
  /// Managed custom domain used by production mobile builds.
  static const production = 'https://yingjian-ai.520orz.com';

  /// Legacy Cloudflare origin retained during the client migration.
  static const legacyWorkersDev =
      'https://yingjian-generation-api.baby-animals-ai-cjc.workers.dev';
}
