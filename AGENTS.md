# 映见 Agent Guide

## 原型速度原则

- 原型设计和开发以快速获得验证结论为目标，不追求完美。优先做出最小可用、可交互的功能切片，尽早验证核心假设。
- 验证前暂缓精细打磨、通用化架构和推测性的完整实现；验证后再明确选择产品化、调整或废弃。
- 速度原则不豁免隐私、安全、数据完整性、破坏性操作和发布授权等硬门槛。

## 产品目标

映见的品牌 Slogan 是“让变美更容易”。首页在选图前用四个清晰任务确定本次创作：

- **优化照片**：调亮、清晰、增强质感。选图后进入本地静态优化；原图只读，结果可恢复。
- **换风格**：日系、胶片、插画、电影感。选图后定风格并应用可复现的静态结果。
- **去背景 / 去杂物**：当前只提供语义白底/背景处理和本地擦除；不是透明 alpha 抠图，也不是无限制的生成式去物。
- **做动态效果**：让静态照片自然动起来。它是独立生成任务；当前生成服务未接入，必须明确显示不可用，不能上传、创建任务或扣费。

`CreationTask=optimize|style|cleanup|motion` 是持久化的用户任务身份；`CreationIntent=apply|motion` 只保留静态/生成执行分支，前三项映射为本地 `apply`，动态映射为 `motion`。旧 `apply` 草稿迁移为 `style`，不得按新的入口猜测或改变用户既有结果。

四个入口是相互独立的任务路径：每个后续页面只承接当前任务及其主操作；切换任务必须返回首页。图片和结果始终是视觉主体，默认界面保持简单、安静、低决策负担；风格候选用于快速切换，更多解释和高级能力按需渐进展开。不得把传统工具分类、控件矩阵或内部参数暴露为主路径。

用户可见移动端交互以当前 Apple Human Interface Guidelines 为 iOS 设计基线：使用系统字体与语义色、系统导航与选图、至少 44 pt 触控目标、Dynamic Type，以及 Reduce Motion/Transparency；照片和任务入口属于内容层，Liquid Glass 只用于导航、连续控制层和临时 Sheet。不得用满屏海报、无名称小圆点、自绘 Web footer、全屏渐变确认页或自动播放动画替代原生媒体创作交互。共享 Flutter 页面也必须保持这一层级，平台返回、选择器和分享行为仍使用对应系统惯例。详细界面合同见 [DESIGN.md](DESIGN.md)。

参数只是风格应用的内部执行语言，不是用户的创作语言。AI 必须先形成可理解的风格定义，再由受约束的本地或云端能力执行；不得产生不可解释、不可撤销或无法追溯的隐式效果。浏览和切换风格不得自动上传、生成或扣费。

“让图片动起来”属于一等生成能力。动态作品是可保留、可导出的正式结果，不是界面动画或静态效果。当前产品北极星、领域语言、风格系统与首阶段合同分别见 [README.md](README.md)、[CONTEXT.md](CONTEXT.md)、[风格系统](docs/product/style-system.md) 和 [MVP Spec](docs/product/mvp-spec.md)。

## Agent skills

### Issue tracker

需求、Spec 和 tickets 使用 `.scratch/<feature-slug>/` 下的本地 Markdown；不创建远程 issue。详见 `docs/agents/issue-tracker.md`。

### Triage labels

使用默认角色：`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。详见 `docs/agents/triage-labels.md`。

### Domain docs

使用单一上下文：根目录 `CONTEXT.md` 只维护领域词汇，难以逆转的重要决策记录在 `docs/adr/`。详见 `docs/agents/domain.md`。

### Development cadence

后续开发统一遵循“完整实现功能切片 → 自动化与 iOS Simulator 集中验证 → 冻结候选 → 最终真机验收”的时序；不得把每次小改动都变成一次真机流程。详见 `docs/agents/development-validation-workflow.md`。

## 仓库与工具链

- `lib/`：Flutter UI、交互、创作状态、风格定义和任务编排。
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
- `DESIGN.md`：当前四个任务入口、图片主体、任务专属操作与分支内单主操作界面合同。
- `docs/README.md`：按任务类型选择最少必要文档的总路由。
- `docs/product/product-context.md`：稳定产品北极星。
- `docs/product/mvp-spec.md`：唯一可执行的首阶段合同。
- `docs/product/style-system.md`：风格定义、输入方式以及四个任务与两个执行分支的边界。
- `docs/architecture/flutter-foundation.md`：Flutter 分层、依赖方向和 Module seam 的基准说明。
- `docs/architecture/style-execution.md`：风格到确定性应用结果的执行边界。
- `docs/architecture/generation-pipeline.md`：静态与动态生成任务的生命周期边界。
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

- Flutter 负责 UI、交互、创作状态、风格定义和任务编排。
- 高频像素处理、预览纹理和高清导出位于 iOS/Android 原生能力边界之后。
- Flutter 与原生层只传递文件路径、版本化执行计划、区域、进度和结果状态；实时预览交互中不得往返传输完整图片字节。
- 原图只读；风格应用必须非破坏、可撤销、可恢复，并从原图进行高清导出。
- 商业人像 SDK、云端模型和本地算法都封装在供应商无关接口之后，业务层不得直接依赖供应商对象。
- 生成能力是独立分支；失败、超时或质量门拒绝不能破坏源图、当前风格或本地应用结果。
- 优先沿用邻近代码和已有架构，未经批准不引入新的生产依赖或大型框架。

## Runtime 安全

- debug-only、test-only、assert-only 或非 Debug 构建不可用的 API，不得无保护进入生产路径。
- Flutter 的 `debugNeedsPaint`、`debugNeedsLayout` 等 debug-only framework member 必须用短路的 `kDebugMode && ...` 保护，或在求值前返回；`kReleaseMode` 不能替代该保护，因为 Profile 既不是 Debug 也不是 Release。
- 设备敏感生产路径变更后，先运行窄回归测试；相关功能切片完整后再进行 Simulator 与 Profile/Release 构建验证，物理设备执行证据集中到冻结候选阶段。
- iOS 渲染、分享、插件、签名和生命周期差异仍需要物理设备证据才能完成最终验收。若任务明确针对仅在真机出现的问题，则必须在宣称该问题修复前做针对性真机验证。
- Review 时搜索变更的生产源码是否新增 debug-only API；`debugPrint` 等安全工具不自动构成违规，应依据 API 契约判断。

## 图像、隐私与 AI 成本

- 默认本地处理，未经用户明确选择不上传原图。
- 云端语义编辑只上传用户确认的照片和必要区域，并明确展示会消耗云端权益。
- 不把图片、人脸特征、签名 URL、密钥、完整个人提示或其他个人数据写入普通日志。
- Analytics、Crashlytics 和 Performance 默认关闭；仅在用户明确开启匿名诊断后启用，关闭后必须立即停止。
- 新增遥测前先更新 `docs/operations/telemetry-event-catalog.md` 和事件白名单测试；禁止自由文本事件与任意参数 Map。
- 风格候选、预览和确定性应用默认走本地能力；不得因用户浏览或切换候选自动创建多个云端生成任务。
- 云端任务必须可取消、可重试、可去重并具备超时和成本上限；失败、取消或质量门拒绝不得错误扣权益。
- AI 服务端密钥不得进入 Flutter 客户端、提交历史、文档、日志、截图或命令参数。

## 测试与完成标准

- 测试公开行为接缝，不耦合内部 Widget、Shader 或供应商实现对象。
- 图像处理使用固定样片、固定参数和明确数值容差；主观人像质量另以盲评补充。
- UI 行为用 Widget 测试；算法和配方使用单元/黄金样片测试；功能切片完整后在 iOS Simulator 运行正式导航与集成路径，冻结候选后再做最终真机验证。
- 每个新增的用户可见 Flutter 页面、Screen 或 Route，都必须在同一变更中新增或扩展 `integration_test`；Widget 测试不能替代此门禁。
- 集成测试必须通过正式导航或路由入口进入页面，验证稳定的页面标识，执行至少一个主要交互，并断言可见状态或导航结果；纯展示页面至少验证内容契约以及返回或关闭行为。
- 必要时为测试增加稳定的 `ValueKey` 或 `Semantics` 标识，不得只依赖本地化文案、屏幕坐标或 Widget 顺序。
- 测试必须接入仓库现有 integration-test runner，并在受支持目标上运行最窄用例。测试缺失、被跳过或失败时，新增页面不得视为完成；技术上确实受阻时，必须记录具体阻塞并取得用户对后续补测的明确批准。
- Debug 或模拟器结果可以证明工程与交互验证通过，但不能代替冻结候选的 Profile/Release 真机性能证据。
- 用户可见 UI 变更必须在切片级 Simulator 验证中检查布局、加载、空态、错误态、取消、无障碍和关键交互；最终真机视觉与交互证据在候选阶段集中采集。
- 完成前运行最窄相关测试、`flutter analyze`、必要的完整测试，并检查 `git diff --check`。

## Git 与变更边界

- 保持改动和提交范围单一，保留用户已有的无关修改。
- 不提交 `.env`、密钥、签名材料、原始用户图片、生成缓存、APK/AAB/IPA/XCArchive 或临时证据。
- 应用密钥和签名路径只存在于被忽略的本地环境文件；示例文件只记录变量名和占位值。
- 除非用户明确要求，不推送远程、不创建 PR、不修改商店状态、不部署服务。
- 需求、缺陷和计划默认记录为仓库内 Markdown，不擅自创建远程 issue。

## 本地发布与候选完整性

- 构建、签名和上传必须在本机执行；每次 TestFlight、商店上传或提交都需要用户明确授权。
- 发布任务开始前必须读取 [`docs/release-contract.md`](docs/release-contract.md)，并通过 schema 2 发布合同、30 分钟内商店基线、全平台连续 build、干净且与 upstream 同步的源码身份和最终产物身份检查。
- `release_ready: false`、缺少签名/环境文件、候选证据不完整或版本/build 不合法时必须停止，不得削弱预检。
- 源码提交、版本/build、Bundle ID、签名、配置、资源和产物 SHA-256 是独立证据；任一缺失都不能称为候选完成。

## 商店与交付状态边界

- 分别报告本地构建、已上传、provider processing、provider valid、测试组分发、真实测试者可达、已提交审核、审核中、已批准和公开可用。
- 上传成功不是测试者可达；轮询同一 build 到终态并验证测试组和实际安装。
- 审核与公开发布是新的授权阶段。提交前按 [`docs/release-contract.md`](docs/release-contract.md) 检查素材、合规、审核信息和批准后的公开方式。

## Apple 订阅与法律元数据保护

- 隐私、Terms、EULA、App Privacy、订阅和地区字段属于受保护元数据；普通文案、截图或版本说明请求不授权修改这些字段。
- 修改前读取 [`docs/legal/store-privacy-checklist.md`](docs/legal/store-privacy-checklist.md)，按 locale 获取最新远程快照，只上传明确白名单并逐字段回读。

## Agent 工作流

1. 先读本文件和任务涉及的产品/架构文档。
2. 检查工作树和相邻实现，确认已有修改和真实行为。
3. 把需求转成可观察验收标准和测试计划。
4. 实施最小且完整的改动，保持层级边界和隐私约束。
5. 先运行窄自动化与静态检查；功能切片完整后，再集中运行 iOS Simulator 集成验证。
6. 本轮功能全部实现且自动工程门通过后冻结候选；只有此时才集中执行 Profile/Release、TestFlight 和真机设备验收。仅真机缺陷任务可提前做针对性设备验证。
7. UI 变更在 Simulator 阶段检查重要状态并保留本地、Git 忽略的视觉证据；冻结候选再采集最终真机证据。
8. 分别报告功能实现、模拟器验证、候选冻结和真机验收状态；不得把其中任一项笼统描述成已构建、已上传或已发布。
