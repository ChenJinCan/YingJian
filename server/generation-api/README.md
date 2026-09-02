# 映见 Generation API（中国大陆 MVP）

这是 Node.js 24、零第三方运行依赖的第一方生成网关。它只接当前确定的六项云能力，不做供应商自动选择、自动重试、自动降级或能力串联：

| `capability` | 供应商合同 | 服务端固定约束 |
| --- | --- | --- |
| `optimizeAiRepair` | 百度 `image_definition_enhance` | 单次同步清晰度增强 |
| `styleAiRedraw` | 阿里 `wan2.7-image` | `size=2K`、`n=1`、固定 seed、`watermark=true`、组图关闭 |
| `cleanupRemovePasserby` | 阿里 `wanx2.1-imageedit` / `description_edit_with_mask` | 只使用用户上传的 Mask 和固定去路人提示词 |
| `cleanupBrushRemove` | 阿里同上 | 只使用用户上传的 Mask 和固定去物提示词 |
| `optimizeOldPhoto` | 火山 `LensOpr` / `lens_opr` | 默认关闭；用户必须明确传 `colorMode=preserve|colorize`，只映射为 `if_color=0|1` |
| `motionAiNatural` | 阿里 `wan2.6-i2v-flash` | 用户显式选择的独立 AI 自然动效；`720P`、3 秒、无声、禁用 prompt 改写、固定 seed 和水印 |

供应商密钥只从环境变量读取。服务端不记录原图、Mask、提示全文、签名 URL 或密钥。阿里结果只允许从官方北京 OSS 域名下载；DNS 解析后的私网、loopback、link-local、重定向、超时或超限响应都会被拒绝。成功结果立即导入第一方私有媒体目录，API 只返回 `resultMediaId`。

## Cloudflare Workers 生产运行时

生产入口是 `src/cloudflare/worker.mjs`，配置位于 `wrangler.jsonc`：

- `DB` 是 D1 绑定，持久化任务、创建幂等、CAS 版本、权益、存储额度、兼容旧客户端的一次性激活码、安装公钥与会话 Challenge。
- `MEDIA` 是私有 R2 Standard bucket 绑定；客户端无法取得 R2 地址或 R2 凭据，所有上传和下载都经过已认证 Worker。
- `REGISTRATION_RATE_LIMITER` 按安装公钥 `keyId` 限制公开注册突发请求，`SESSION_RATE_LIMITER` 按 `installationId` 限制短期会话刷新；两者都不读取图片或保存客户端 IP。
- 每小时 Cron 只清理已过期 Challenge、激活码和不超过 24 小时的私有媒体，不执行付费供应商任务。
- Worker 使用 Cloudflare Secrets 读取会话、Offer 和供应商密钥。`wrangler.jsonc` 的 `vars` 只能放非密钥配置与显式能力开关。

必须以隐藏输入方式分别写入 Secrets：

```sh
npx wrangler secret put GENERATION_SESSION_SIGNING_KEY
npx wrangler secret put GENERATION_OFFER_SIGNING_KEY
npx wrangler secret put BAIDU_API_KEY
npx wrangler secret put BAIDU_SECRET_KEY
npx wrangler secret put ALIBABA_DASHSCOPE_API_KEY
npx wrangler secret put VOLC_ACCESS_KEY_ID
npx wrangler secret put VOLC_SECRET_ACCESS_KEY
```

不能把这些值写入 `wrangler.jsonc`、Flutter `dart-define`、原生工程、日志或命令参数。百度、阿里图片、阿里视频和火山开关分别为 `BAIDU_IMAGE_REPAIR_ENABLED`、`ALIBABA_IMAGE_ENABLED`、`ALIBABA_VIDEO_ENABLED`、`VOLC_LENS_OPR_ENABLED`；版本化配置全部从 `false` 起步。写入并核验对应 Secrets 后，才显式把该供应商开关改成 `true`。密钥存在本身不会启用能力，也不会导致供应商切换。

当前 D1 已绑定 `yingjian-generation-production`，R2 bucket 名为 `yingjian-generation-private`。首次发布顺序：

```sh
npx wrangler whoami
npx wrangler r2 bucket create yingjian-generation-private --location apac
npm run worker:migrate:remote
npx wrangler deploy --dry-run
npm run worker:deploy
```

实际部署输出的 HTTPS origin 必须与 `GENERATION_SESSION_ISSUER` 完全一致；不一致时先修正 issuer 并重新部署，不能放宽 JWT 验证。

### 自动安装注册与短期会话

Worker 不接受公开共享 Bearer，也没有“传 installationId 即换 Token”的路由。新版 iOS 与 Android 客户端在首次使用云能力时自动创建平台 KeyStore 中的 P-256 安装密钥，通过 120 秒 Challenge/签名注册安装，再取得 10 分钟 `scope=generation` HS256 JWT；不需要逐台生成或输入激活码。相同公钥可以在响应丢失后恢复同一 installation，重新注册不会重置额度或恢复已撤销 installation。D1 只保存公钥和 Challenge nonce SHA-256；供应商密钥始终只在 Worker Secrets 中。

旧客户端的 v1 一次性激活合同暂时保留兼容。只有需要验证旧 build 时才在本机运行：

```sh
npm run worker:provision-enrollment
```

脚本在进程内生成激活码，只把 SHA-256 通过 Wrangler 写入远程 D1，不写文件、不把原码放入 shell argv，成功时只输出一次 `yingjian://generation-activate?code=...`。该 URL 是短期凭据，不应进入聊天、截图或日志。

会话 HTTP 合同：

- `POST /v1/installation-challenges`：新版自动注册提交 `{version:2,keyId}`；旧激活流程仍可提交 `version:1`。
- `POST /v1/installations`：v2 提交 Challenge、P-256 X9.63 公钥和 raw `r||s` 签名；v1 额外提交一次性码。成功均返回 `installationId`、`bearerToken`、`expiresAtEpochMilliseconds`。
- `POST /v1/generation-session-challenges`：`{version:1,installationId,keyId}`，只接受已激活且未撤销安装。
- `POST /v1/generation-sessions`：提交一次性 Challenge 的 P-256 签名，成功返回新的 10 分钟会话。

自动注册的 PoP 证明同一安装持续持有私钥，但尚不能证明请求一定来自未篡改的官方 App。当前 MVP 以每安装固定额度、任务速率/并发/存储上限、按安装身份的 Cloudflare 突发限速，以及 D1 同一条件写入内的全局生成窗口保险丝控制成本。生产配置当前每个安装最多 5 次、每小时全局最多创建 20 个生成预留；达到全局上限时所有新付费生成返回 `generation_global_rate_exceeded`，但不阻止新客户端注册或刷新会话。Cloudflare 限速按边缘节点且最终一致，不能作为精确计费账本。提高免费额度或扩大公开付费规模前，必须在同一注册接缝加入 Apple DeviceCheck/App Attest 与 Android 对等证明，或绑定真实账号权益；不得回退为共享 Token。

## 安全启动边界

默认没有认证器、权益守卫或 Offer 签名密钥；任一缺失时进程都会拒绝启动。生产环境必须通过 `GENERATION_AUTH_MODULE` 注入应用自己的会话认证器；模块需导出以下任一接口：

```js
export async function authenticate(request) {
  // 成功返回 { ownerId: 'stable-user-id' }，失败返回 null。
}
```

或：

```js
export async function createAuthenticator() {
  return async (request) => ({ ownerId: 'stable-user-id' });
}
```

`GENERATION_ALLOW_SHARED_BEARER_AUTH=true` 只用于本机联调；启用后服务强制绑定 loopback，且仍必须显式提供不少于 16 字符的 token。共享 token 不能作为线上付费接口的用户身份方案。

生产环境还必须通过 `GENERATION_GUARD_MODULE` 注入持久化、原子化的权益/额度实现。模块导出 `usageGuard`，或导出异步 `createUsageGuard()`；对象必须实现：

```js
reserveGeneration(input)
settleGeneration(input)
releaseGeneration(input)
reserveStorage(input)
commitStorage(input)
releaseStorage(input)
expireStorage(input)
```

`reserveGeneration` 必须以 `ownerId + reservationId` 原子幂等，并拒绝相同 ID 的不同 fingerprint/费用；还必须执行用户权益、速率和并发上限。只有供应商确定成功才 settle，确定拒绝、确定失败或供应商确认取消才 release；网络超时、未知 dispatch 结果和本地取消保持 hold，等待人工/账务对账。未知 dispatch 的活动并发租约以速率窗口为安全上限：窗口内继续阻止第二个付费请求，窗口后只释放活动并发，原预留仍为 `reserved/hold`、继续计入额度且不得再次 submit。`pending|running` 任务在观察时调用 `touchGeneration` 续租。生产模块不得使用进程内 Map 代替持久化账本。

## 本地运行

```sh
cd server/generation-api
cp .env.example .env.local
# 在被 Git 忽略的 .env.local 中填写本地配置
node --env-file=.env.local src/server.mjs
```

最小本地认证配置为：

```text
GENERATION_ALLOW_SHARED_BEARER_AUTH=true
GENERATION_LOCAL_BEARER_TOKEN=<至少 16 字符的本地随机值>
GENERATION_LOCAL_OWNER_ID=<本地测试用户 ID>
GENERATION_OFFER_SIGNING_KEY=<至少 32 字节的本地随机值>
GENERATION_LOCAL_MAX_CREDITS=<固定正整数>
GENERATION_LOCAL_MAX_CONCURRENT=<固定正整数>
GENERATION_LOCAL_MAX_RESERVATIONS_PER_WINDOW=<固定正整数>
GENERATION_LOCAL_RATE_WINDOW_MS=<固定正整数>
GENERATION_LOCAL_MAX_STORAGE_BYTES=<固定正整数>
GENERATION_MEDIA_RETENTION_HOURS=<1～24；省略时为 24>
GENERATION_TASK_DIRECTORY=<仓库外或被忽略的私有任务目录>
GENERATION_MEDIA_DIRECTORY=<仓库外或被忽略的私有媒体目录>
```

三家供应商能力都使用独立、显式且默认关闭的开关：

```text
BAIDU_IMAGE_REPAIR_ENABLED=false
ALIBABA_IMAGE_ENABLED=false
ALIBABA_VIDEO_ENABLED=false
VOLC_LENS_OPR_ENABLED=false
```

只有开关精确等于 `true` 时，runtime 才实例化对应供应商并要求其密钥：百度要求 `BAIDU_API_KEY` 与 `BAIDU_SECRET_KEY`，阿里图片与视频分别使用 `ALIBABA_IMAGE_ENABLED` 和 `ALIBABA_VIDEO_ENABLED`，但均只在服务端读取 `ALIBABA_DASHSCOPE_API_KEY` 与 `ALIBABA_WORKSPACE_ID`，火山要求 `VOLC_ACCESS_KEY_ID` 与 `VOLC_SECRET_ACCESS_KEY`。开关缺失、为空、为 `false` 或其他值时，对应能力在能力接口中保持 `disabled`，且不读取、不校验其密钥。仅配置密钥不得自动启用能力；阿里图片开关不得隐式启用视频。任一供应商关闭或失败也不得自动改走其他供应商或本地动效。

运行测试：

```sh
npm test
```

## HTTP 合同

除下述说明外，所有路由都必须携带由注入认证器识别的 `Authorization`。JSON 响应都带 `Cache-Control: no-store`。

### 能力状态

```http
GET /v1/generation-capabilities
```

返回顶层 `mediaRetentionHours`（固定不超过 24），以及六项能力的 `enabled`、`provider`、`model`、`recipeVersion`、`providerCancelable`、`cancelBoundary=provider_pending_only|not_provider_cancelable` 和 `offer={id, creditCost, expiresAt}`。Offer 是绑定认证用户、能力、费用和 `policyVersion=1` 的 HMAC 不透明值，15 分钟后失效；创建时会实际验证归属、签名、期限和精确策略版本。首版六项云能力固定消耗 1 次权益；该顺序是产品目录，不是推荐或自动排序。尚无经供应商样片确认的稳定等待时长，因此 API 不虚构 `estimatedWait`。

### 上传私有输入

```http
POST /v1/private-media
Content-Type: image/jpeg
X-Content-Sha256: <本次实际上传代理文件的 SHA-256>

<方向归一化且满足所选供应商边界的代理图片二进制>
```

允许真实可探测的 JPEG、PNG、WEBP、BMP，通用上传硬上限为 25 MB；伪造 MIME、非法 header、超过 8000 边长或超过 4000 万像素会被拒绝。上传前按认证用户原子预留存储配额，持久化成功后才 commit。源图、Mask 和结果的逻辑与物理保留期都不超过 24 小时：每个文件有固定过期时间，进程运行时由单定时器 sweep，重启时立即 sweep；过期读取返回 `410 media_expired` 并删除文件、释放存储记账。环境变量只接受 1～24 小时，不能延长到 24 小时以上。返回：

```json
{"media":{"id":"...","sha256":"..."}}
```

源图代理和 Mask 代理分别上传；返回的 ID 作为 `sourceMediaId` 和 `maskMediaId`。客户端声明 `X-Content-Sha256` 时服务端会与实际字节比对。媒体按认证用户隔离。

### 创建任务

```http
POST /v1/generation-tasks
Content-Type: application/json
```

AI 修复示例：

```json
{
  "creationId": "client-attempt-id",
  "capability": "optimizeAiRepair",
  "sourceMediaId": "source-media-id",
  "sourceOriginalSha256": "<只读 ProjectPhoto 的 SHA-256>",
  "sourceUploadSha256": "<实际上传代理文件的 SHA-256>",
  "consent": {
    "offerId": "<能力接口刚返回的不透明 Offer ID>",
    "uploadConfirmed": true,
    "costConfirmed": true,
    "policyVersion": 1
  }
}
```

能力专属字段：

- `styleAiRedraw`：必须传 `styleDefinition` 以及 `styleDefinitionConfirmed=true`。
- 两项去物：必须传用户明确制作的 `maskMediaId`、`maskOriginalSha256` 与同方向/同尺寸代理的 `maskUploadSha256`；服务端不会识别人物、扩展 Mask 或替用户选择区域。
- `optimizeOldPhoto`：必须传 `colorMode`，且只能是 `preserve` 或 `colorize`。

供应商输入门禁在任何付费调用前执行：百度修复的 Base64 编码后不超过 10 MB、边长 10–5000、比例不超过 4:1，格式限 JPEG/PNG/BMP；阿里风格图不超过 20 MB、边长 240–8000、比例不超过 8:1；去物源图与 Mask 各不超过 10 MB、边长 512–4096，Mask 必须是与源图同尺寸的纯黑白 PNG。

`consent.offerId` 必须是能力接口返回且尚未过期的当前 Offer，`policyVersion` 必须精确为 `1`。原始来源身份与实际上传代理身份分别绑定并写入幂等 fingerprint；转码 SHA 不能冒充 `ProjectPhoto` 身份。首次创建返回 201；完全相同的创建、输入和 Offer 返回 200，既不会再次预留权益，也不会再次请求供应商；同一 `creationId + capability` 改变原图身份、代理字节、Mask、风格定义、颜色模式、Offer 或策略版本返回 `409 idempotency_conflict`。

任务字段：

```json
{
  "task": {
    "id": "...",
    "requestId": "client-attempt-id",
    "creationId": "...",
    "capability": "styleAiRedraw",
    "colorMode": null,
    "offerId": "<已验证的不透明 Offer ID>",
    "sourceMediaId": "...",
    "sourceSha256": "<原始来源身份>",
    "sourceUploadSha256": "<实际代理身份>",
    "maskSha256": null,
    "maskUploadSha256": null,
    "inputIdentity": "style-redraw-v1:<definition-sha256>",
    "recipeVersion": "style-ai-redraw@1",
    "provider": "alibaba",
    "model": "wan2.7-image",
    "state": "pending",
    "providerStatus": "PENDING",
    "providerCancelable": true,
    "providerCancellation": "available_while_pending",
    "usageState": "reserved",
    "usageDisposition": "hold",
    "resultMediaId": null,
    "errorCode": null,
    "createdAt": "...",
    "updatedAt": "..."
  }
}
```

### 查询与取消

```http
GET /v1/generation-tasks/{taskId}
POST /v1/generation-tasks/{taskId}/cancel
```

查询阿里任务时会读取同一个供应商任务 ID；不会因为网络失败新建任务。付费调用前先持久化 append-only dispatch intent；若供应商已经可能接收、但其任务 ID 未能持久化，安全窗口内后续 POST/GET 只返回 `dispatch_reconciliation_required`，权益保持 hold，绝不会二次 submit。窗口结束仍无供应商 ID 时，同一任务转为 `provider_outcome_unknown`，保留权益冻结与审计记录但不再永久占用活动并发；重放原 creation identity 仍只返回原任务，不会再次 submit。任务观察和取消使用版本 CAS，过期响应不能覆盖更新状态。

阿里仅在 `PENDING` 时请求供应商取消。供应商确认取消才进入 `canceled` 并 release 权益；若取消响应表明任务已经 `RUNNING`，服务端保持真实的 `running` 状态、设 `providerCancelable=false` 并保持权益 hold，绝不把它误报为已取消、停止计费或已退款。百度和火山是同步接口，从不声称支持供应商取消。

客户端必须同时解释 `providerCancellation`、`usageState` 和 `usageDisposition`：取消已确认且 `usageState=released` 才能显示权益已释放；任务仍运行或状态待对账且 `usageDisposition=hold` 时，必须保留并刷新同一个任务，不能重新创建或宣称已退款。

### 下载私有结果

```http
GET /v1/private-media/{resultMediaId}
```

返回原始图片二进制，并带 `Content-Type`、`X-Content-Sha256`、`Cache-Control: no-store`。客户端把二进制写入应用私有文件后再预览、导出或分享。

## Flutter 会话接入与 Debug 联调

Profile/Release 只从供应商无关的 `GenerationSessionCredentialSource` 获取按安装签发的短期 Bearer。默认 MethodChannel 接缝为 `yingjian/generation_session` / `getShortLivedBearerCredential`，iOS/iPadOS 与 Android 原生宿主都会在首次明确使用云能力时自动注册当前安装，并返回 `bearerToken` 和 `expiresAtEpochMilliseconds`；剩余有效期不足 30 秒、超过 1 小时或响应不合法时，云端能力保持不可用。App 不持久化或记录 Bearer，也不会改用共享 token。历史安装包不会获得这段新代码；自动注册从包含该实现的下一版客户端开始覆盖所有已支持移动端。

若启动时没有会话或首次连接失败，App 不在后台自动重试。只有用户在能力页明确点击现有“重试”，使 `GenerationCoordinator.refreshCapabilities()` 被调用时，客户端才会重新读取当前短期凭据并连接同一个已配置的第一方地址；不会切换供应商、降级能力或重新创建任务。并发的同一次显式刷新会合并为一个连接请求。

Debug 仅在第一方地址为 loopback 时允许使用本机共享 token。复制 `config/generation.debug.example.json` 为被 Git 忽略的 `config/generation.debug.local.json`，填写与服务端一致的 loopback token，然后运行：

```sh
flutter run -d <simulator-id> --dart-define-from-file=config/generation.debug.local.json
```

不要把 token 直接写入命令参数、源码、日志或提交记录。loopback 共享 token 只用于 Debug；Profile/Release 走上述平台 KeyStore 自动注册与短期会话，不需要把供应商或会话密钥放入客户端。

## 本地导入媒体（可选）

HTTP 上传之外，也可在同一台机器上预置一张测试图：

```sh
npm run import-media -- <owner-id> <media-id> image/jpeg /absolute/path/input.jpg
```

这只写入 `GENERATION_MEDIA_DIRECTORY`，不会调用供应商。

## 尚未完成的外部状态

本目录没有部署、没有创建云账号、没有写入真实密钥，也没有进行真实图片调用或账单验证。三家供应商 runtime 开关默认关闭；生产启用仍需分别完成账号与能力开通、当前价格/SLA、内容治理和真实固定样片验收，其中火山老照片还要求企业账号资格。
