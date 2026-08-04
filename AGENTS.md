# 映见 Agent Guide

## 产品目标

映见是一款以本地图像处理引擎为核心的智能修图应用，核心承诺是“一张精修，整组好看”。MVP 优先交付稳定、可控、可撤销的一张细腻编辑和整组一致性，不以昂贵且不可预测的云端生成替代基础修图能力。

产品能力优先级固定为：本地修图质量、单张精修、整组一致性、智能配方、可选生成式 AI。默认三套推荐只计算参数配方，不创建云端图片生成任务。

## Agent skills

### Issue tracker

需求、Spec 和 tickets 使用 `.scratch/<feature-slug>/` 下的本地 Markdown；不创建远程 issue。详见 `docs/agents/issue-tracker.md`。

### Triage labels

使用默认角色：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。详见 `docs/agents/triage-labels.md`。

### Domain docs

使用单一上下文：根目录 `CONTEXT.md` 维护领域词汇，难以逆转的重要决策记录在 `docs/adr/`。详见 `docs/agents/domain.md`。

## 仓库与工具链

- `lib/`：Flutter UI、交互、编辑状态、配方和任务编排。
- `lib/app/`：应用组装、主题和路由，不放修图业务规则。
- `lib/app/settings/`：由 Provider 注入并持久化的主题、语言等轻量应用设置。
- `lib/startup/`：首屏关键初始化和首屏后延迟任务协调。
- `lib/observability/`：事件白名单、崩溃与性能供应商隔离；不得被业务流程反向依赖。
- `lib/review/`：系统评分资格策略与永久商店入口。
- `assets/l10n/`、`lib/l10n/`：官方 gen-l10n 的源资源与生成代码。
- `lib/features/<feature>/presentation/`：页面和用户交互。
- `lib/features/<feature>/application/`：用例、任务编排与会话状态。
- `lib/features/<feature>/domain/`：不依赖 UI、插件或供应商的配方和值对象。
- `ios/`、`android/`：平台工程以及未来的原生图像处理桥接。
- `test/`：单元和 Widget 行为测试。
- `docs/`：产品、架构、质量和发布契约。
- `docs/architecture/flutter-foundation.md`：Flutter 分层、依赖方向和 Module seam 的基准说明。
- `docs/architecture/cross-app-foundation-audit.md`：与三款现有应用逐项对照后的采用/拒绝决定。
- `docs/product/`：竞品基线、产品上下文和当前 MVP 交付合同。
- `docs/quality/mvp-quality-baseline.md`：图像样片、盲评、物理设备和性能门禁。
- `quality/corpus-manifest.yaml`：本地、被忽略样片的可校验清单；未补齐时完整质量检查必须失败。
- `CONTEXT.md`：跨产品、设计和工程使用的规范领域词汇。
- `release/release-policy.yaml`：非密钥的发布规则，必须保持 schema 2。
- `scripts/check_release_contract.rb`：发布规则、环境、候选和源码身份校验器。
- Flutter stable 基线：Flutter 3.44.8、Dart 3.12.2；变更基线前先验证依赖兼容性。
- iOS deployment target 基线为 15.0；降低前必须验证 Firebase 与所有原生插件兼容性。

常用验证命令：

```sh
flutter pub get
flutter gen-l10n
dart format -o none --set-exit-if-changed lib test
flutter analyze
flutter test
bash scripts/test_release_contract.sh
ruby scripts/check_release_contract.rb validate-config
```

依赖升级、签名变更、Release 构建、TestFlight/Google Play 上传和审核提交都需要用户明确授权。

## 工程架构边界

- Flutter 负责 UI、交互、项目状态、编辑配方和任务编排。
- 高频像素处理、预览纹理和高清导出位于 iOS/Android 原生能力边界之后。
- Flutter 与原生层只传递文件路径、参数、区域、进度和结果状态；滑块交互中不得往返传输完整图片字节。
- 原图只读；编辑必须非破坏、可撤销、可恢复，并从原图进行高清导出。
- 商业人像 SDK、云端模型和本地算法都封装在供应商无关接口之后，业务层不得直接依赖供应商对象。
- 生成式 AI 是可选增强层；失败、超时或质量门拒绝不能破坏本地编辑结果。
- 优先沿用邻近代码和已有架构，未经批准不引入新的生产依赖或大型框架。

## Runtime 安全

- debug-only、test-only、assert-only 或非 Debug 构建不可用的 API，不得无保护进入生产路径。
- Flutter 的 `debugNeedsPaint`、`debugNeedsLayout` 等 debug-only framework member 必须用短路的 `kDebugMode && ...` 保护，或在求值前返回；`kReleaseMode` 不能替代该保护，因为 Profile 既不是 Debug 也不是 Release。
- 设备敏感生产路径变更后，运行窄回归测试并在受影响平台执行 Profile 或 Release 冒烟。
- iOS 渲染、分享、插件、签名和生命周期差异需要物理设备证据，才能宣称真机问题完成。
- Review 时搜索变更的生产源码是否新增 debug-only API；`debugPrint` 等安全工具不自动构成违规，应依据 API 契约判断。

## 图像、隐私与 AI 成本

- 默认本地处理，未经用户明确选择不上传原图。
- 云端语义编辑只上传用户确认的照片和必要区域，并明确展示会消耗云端权益。
- 不把图片、人脸特征、签名 URL、密钥、完整个人提示或其他个人数据写入普通日志。
- Analytics、Crashlytics 和 Performance 默认关闭；仅在用户明确开启匿名诊断后启用，关闭后必须立即停止。
- 新增遥测前先更新 `docs/operations/telemetry-event-catalog.md` 和事件白名单测试；禁止自由文本事件与任意参数 Map。
- 推荐方案、预览和参数微调默认走确定性的本地配方；不得因用户浏览三套方案而自动产生三次云端出图费用。
- 云端任务必须可取消、可重试、可去重并具备超时和成本上限；失败、取消或质量门拒绝不得错误扣权益。
- AI 服务端密钥不得进入 Flutter 客户端、提交历史、文档、日志、截图或命令参数。

## 测试与完成标准

- 测试公开行为接缝，不耦合内部 Widget、Shader 或供应商实现对象。
- 图像处理使用固定样片、固定参数和明确数值容差；主观人像质量另以盲评补充。
- UI 行为用 Widget 测试；算法和配方使用单元/黄金样片测试；完整导入、预览、撤销、导出路径再使用集成或真机验证。
- Debug 或模拟器结果不能代替 Profile/Release 真机性能证据。
- 用户可见 UI 变更必须检查布局、加载、空态、错误态、取消、无障碍和关键交互；无法取得截图或真机证据时明确标记未验证。
- 完成前运行最窄相关测试、`flutter analyze`、必要的完整测试，并检查 `git diff --check`。

## Git 与变更边界

- 保持改动和提交范围单一，保留用户已有的无关修改。
- 不提交 `.env`、密钥、签名材料、原始用户图片、生成缓存、APK/AAB/IPA/XCArchive 或临时证据。
- 应用密钥和签名路径只存在于被忽略的本地环境文件；示例文件只记录变量名和占位值。
- 除非用户明确要求，不推送远程、不创建 PR、不修改商店状态、不部署服务。
- 需求、缺陷和计划默认记录为仓库内 Markdown，不擅自创建远程 issue。

## 本地发布与候选完整性

- Android APK/AAB 和 Apple archive/IPA 必须在本机完成构建与签名。没有逐次明确授权时，不得创建或触发 GitHub Actions 打包、签名、TestFlight 或商店上传工作流。
- 每个 checkout/worktree 在改版本、构建或上传前，必须包含 schema 2 的 `release/release-policy.yaml`，且 `identity.version_rule` 为 `reuse_testing_else_patch_public`。
- 先从已认证商店读取公开版本、最新上传营销版本和该平台所有版本列车中的最高 build；基线超过 30 分钟即失效。
- 如果最新上传营销版本高于公开版本，继续使用该测试版本，只把平台全局 build 加一；两者相等时才把 patch 版本加一，同时使用全局下一 build。营销版本变化不能重置 build。
- 正式候选只能从干净、已推送并与 upstream 完全同步的 release worktree 构建。没有远程分支、ahead、behind、diverged 或源码提交不匹配都应阻断。
- 构建前冻结平台、track、公开基线、源码完整 SHA、版本、build 和获准终止阶段。
- 构建后单独验证包名/Bundle ID、版本、build、配置、必要资源、数据 schema/记录数量、源码提交和 SHA-256；源码身份不能代替产物身份。
- 当前任一平台 `release_ready: false` 时，表示签名、商店记录或产物验证链尚未完成，禁止绕过校验器发布。
- Firebase 原生配置、公开隐私/支持 URL、Apple App Privacy 与 Google Play Data Safety 均为独立发布门禁；缺失时预检必须失败。

发布前入口：

```sh
RELEASE_PUBLIC_VERSION=... \
RELEASE_REMOTE_LATEST_VERSION=... \
RELEASE_REMOTE_LATEST_BUILD=... \
RELEASE_BASELINE_VERIFIED_AT=... \
RELEASE_SOURCE_COMMIT=... \
bash scripts/release_contract_preflight.sh ios <version> <build>
```

Android 将平台参数改为 `android`。运行该命令不代表获准构建或上传。

## 商店与交付状态边界

- 以下状态必须分别报告：本地构建、已上传、provider processing、provider valid、测试组分发、真实测试者可达、已提交审核、审核中、已批准、公开可用。
- 成功上传不等于候选可测试；必须轮询同一 build/upload ID 到 provider 终态。仍在处理时继续只读查询，不得因等待超时另传新 build。
- 测试轨道没有活跃测试者或不可安装时，不能称为“可供内部测试”。
- App Review 或 Play 生产提交前，需检查完整 locale × device 素材矩阵、出口合规/加密、年龄分级、社交声明、审核说明和账号、候选选择与发布模式。
- Managed publishing 以及 Apple 手动/自动发布属于独立的公开发布控制；提交审核前必须说明批准后是否会自动公开，并取得相应授权。

## Apple 订阅与法律元数据保护

- App Store 必须保留有效的隐私政策 URL，应用内也必须可访问；如果未来提供自动续订订阅，应用和商店元数据都必须提供有效的 Terms of Use 与 Privacy Policy。
- 隐私 URL、User Privacy Choices、App Privacy 问卷、Terms URL/法律页脚、自定义 EULA 及地区、订阅产品/组名称、描述、周期、价格、试用和优惠都是受保护字段。
- 普通文案、关键词、截图、版本说明或“更新商店元数据”的请求，不授权修改任何受保护字段，也不授权切换 Apple 标准/自定义 EULA。
- 修改受保护字段前必须按 locale 获取最新远程快照并记录 EULA 模式，只上传明确字段白名单，之后逐字段重新读取验证。发现缺失或不一致时作为单独 blocker 报告，不得顺手修复。

## Agent 工作流

1. 先读本文件和任务涉及的产品/架构文档。
2. 检查工作树和相邻实现，确认已有修改和真实行为。
3. 把需求转成可观察验收标准和测试计划。
4. 实施最小且完整的改动，保持层级边界和隐私约束。
5. 运行与风险相称的自动化、静态检查、Profile/Release 和真机验证。
6. UI 变更检查重要状态并保留本地、Git 忽略的视觉证据。
7. 报告行为变化、验证证据、已知基线、未验证项及交付状态；不得把合同测试通过描述成已构建、已上传或已发布。
