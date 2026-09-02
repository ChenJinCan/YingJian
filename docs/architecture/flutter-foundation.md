# Flutter 基础骨架

## 目标

基础骨架服务四个从首页开始的用户任务与两个稳定执行分支：

```text
首页
  ├─ 优化照片 → 选图片 → 明确选一项优化能力 → 静态结果
  ├─ 换风格 → 选图片 → 明确选一项风格能力 → 静态结果
  ├─ 去背景 / 去杂物 → 选图片 → 明确选一项清理能力 → 静态结果
  └─ 做动态效果 → 选图片 → 点击一个动态方向 → 动态结果
```

`CreationTask=optimize|style|cleanup|motion` 是首页四个同级任务的持久化身份，用户在选图前确定它。选图后 presentation 以固定顺序展示当前任务的直达结果选项，初始值为空；用户点击一项后才持久化对应 `CreationCapability`，并在同一动作中执行本地能力或打开必要云端确认；不存在第二个通用应用 CTA。presentation 从任务派生 `creationIntent=apply|motion`：前三项进入静态页面，动态效果进入独立动态页面。`creationIntent` 不表示本地/云端，也不构成能力、上传、生成或费用授权。任何运行时未接入能力保持不可用，不能冒充另一能力。旧 `apply` 草稿迁移为 `style`。

本地“应用”能力把用户已选能力编译为不可见、确定性、可撤销的静态编辑配方；静态生成能力与动态生成能力从只读来源创建独立派生媒体。能力选择前不得分析后执行、上传、创建任务或扣费；能力不支持或失败时只允许拒绝并保留当前状态，不得推荐、组合、切换或降级。动态生成不要求先应用风格或先创建静态提交。

详细合同见[静态风格执行](style-execution.md)、[派生媒体生成](generation-pipeline.md)和 [ADR 0004](../adr/0004-style-first-creation.md)。

## 依赖方向

```text
app（组装、主题、路由）
  └─ feature/presentation（首页任务入口、CreationTask、CreationCapability、分支就绪状态）
       └─ feature/application（会话与用例编排）
            └─ feature/domain（来源身份、风格、编辑状态、生成任务）

静态应用：StyleDefinition → EditingCore → RenderPlan
                                ├─ PhotoPreviewRenderer Adapter
                                └─ PhotoExporter Adapter

派生生成：SourcePhoto + CreationCapability + ConfirmedInput
             → GenerationSourceSnapshot → GenerationCoordinator
                                          ├─ GenerationProvider Adapter
                                          └─ GeneratedMediaStore Adapter
```

- `domain` 不依赖 Flutter UI、插件或供应商 SDK。
- `application` 可以使用 Flutter 的基础状态原语，但不导入 Widget。
- `presentation` 只表达首页任务、图片、固定能力列表、用户选择与分支状态，不暴露元操作目录、供应商任务或原生渲染细节。
- `CreationTask` 持久化用户的卡片选择；`CreationCapability` 只在用户点击后持久化具体能力。`creationIntent` 仅决定 `apply` 或 `motion` 页面，不是 `StyleDefinition`、`EditRecipe`、`RenderPlan` 或供应商 payload 的字段，也不能代替能力选择。
- 本地风格和动态方向的点击同时是选择与执行；静态与动态仍是不同结果分支，不是带不同按钮的同一页面状态。
- `app` 只负责组装，不承载修图或生成规则。
- 页面不直接调用图像 SDK、生成供应商或持久化实现。
- Flutter 与原生静态图像边界只传文件引用、版本化计划、区域和状态，不传完整图片字节。
- 上传、轮询、取消和派生媒体下载只属于用户已选择并确认的生成能力，不得进入本地静态 `EditRecipe` 或 `RenderPlan`。

启动阶段由 `StartupCoordinator` 区分首屏必需准备与可延迟任务；主题和语言由根部 Provider 注入的 `AppSettings` 管理，并通过 SharedPreferences 恢复。生成供应商初始化不是首页或能力列表的前置条件，供应商不可用也不能阻断其他独立的本地能力。

## 核心 Module

### 来源与项目

`PhotoProjectSession` 管理应用自有、只读的来源图片及其当前编辑状态。系统相册临时路径先由 `AppOwnedPhotoImporter` 转为应用自有副本；项目只保存相对媒体引用和内容身份，页面不依赖图片选择插件、文件复制或 JSON 格式。

一次交互围绕一张当前图片完成。多个草稿可以独立存在，但批量范围、整组同步和传统工具分类不进入主流程。

### 静态风格执行

静态风格执行是一个深 Module。调用方只需要提交当前来源身份和 `StyleDefinition`，并接收预览、提交结果或结构化拒绝原因。Module 内部隐藏参数、元操作、能力校验、事务、历史和 `RenderPlan` 编译。

同一来源、已选能力、风格版本（如适用）、引擎能力和编辑基线必须生成稳定结果。用户直接点击日系、胶片或电影感后，该次动作绑定确定的 `StyleDefinition`，渲染成功后原子替换既有风格层并形成一个可撤销步骤；不显示“官方风格”前置分类或第二个应用按钮。连续选择时只有最新选择世代可以提交。优化和清理的本地能力通过同一静态安全/持久化边界执行，但不借用风格任务身份。具体合同见[静态风格执行](style-execution.md)和 [ADR 0006](../adr/0006-direct-result-actions.md)。

### 静态预览与导出

版本化 `ImagePipeline` 不重解释已发布语义。`PhotoPreviewRenderer` 从应用自有来源创建原生纹理预览，`PhotoExporter` 从只读原图重放同一 `RenderPlan`；未知版本、越界字段、不完整目标和不支持的非中性能力必须严格拒绝。具体决定见 [ADR 0002](../adr/0002-native-preview-pipeline.md)。

### 派生媒体生成

`GenerationCoordinator` 管理用户明确选择的静态或动态生成任务，公开创建、观察、取消、重试和删除派生产物的最小 Interface。供应商协议、轮询、幂等、超时、成本保护、恢复和产物校验都留在 Module 内部。

“做动态效果”流程在首页先确定 `CreationTask.motion` 与 `creationIntent=motion`，再选图并由用户点击轻微动态、镜头推进、光影流动或 AI 自然动效。三项本地动态点击后直接编码 MP4，不上传或扣费；AI 自然动效点击后先进入必要云端确认。生成输入绑定不可变的 `GenerationSourceSnapshot`，由 `SourcePhoto`、用户已选 `CreationCapability` 与该能力的已确认输入创建，不依赖 `StyleCommit`。后续换图或改选能力不会篡改既有生成结果，只会使其相对当前选择变为过期。生成失败、取消或供应商不可用不得改变静态编辑状态，也不得阻断其他独立能力。具体合同见[派生媒体生成](generation-pipeline.md)。

## 暂不引入

- 不恢复“分类 → 工具 → 参数”的传统编辑主界面。
- 不把四个任务压回笼统“图片应用”入口；也不在定好风格后同时展示“应用风格”和“生成动态照片”，或使用一个共享 `styleReady` 承担不同任务流。
- 不让页面或 AI 直接拼装任意 shader、脚本、`RenderPlan` 或供应商 payload。
- 不把生成进度、提示词、远程任务 ID、视频 URL 或帧状态加入静态 `EditRecipe`。
- 不因潜在多供应商提前暴露供应商选择；差异只存在于生成 Adapter 内。
- 不把生成供应商初始化加入首屏关键路径。
- 不创建通用 `utils`、`managers` 或 `services` 垃圾目录。

## 新功能落位

- 风格定义、验证与替换规则：`lib/features/editor/domain/`。
- 风格应用、预览和提交编排：`lib/features/editor/application/`。
- 首页任务入口、`CreationTask`、`CreationCapability`、`creationIntent`、图片与能力选择界面：对应 Feature 的 `presentation/`。
- 生成请求、任务和派生产物领域模型：`lib/features/generation/domain/`。
- 生成编排和供应商 seam：`lib/features/generation/application/`。
- 供应商、下载与媒体存储 Adapter：`lib/features/generation/infrastructure/` 或平台目录。
- 跨 Feature 组装：`lib/app/`。

测试通过 Module Interface 验证公开结果，不镜像内部目录或供应商协议。新增用户可见页面或路由时，仍必须同步扩展生产导航的 `integration_test`。
