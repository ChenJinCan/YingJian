# Flutter 基础骨架

## 目标

基础骨架服务四个从首页开始的用户任务与两个稳定执行分支：

```text
首页
  ├─ 优化照片 → 选图片 → 本地优化 → 静态结果
  ├─ 换风格 → 选图片 → 定风格 → applyStyleReady → 应用风格
  ├─ 去背景 / 去杂物 → 选图片 → 语义背景或本地擦除 → 静态结果
  └─ 做动态效果 → 选图片 → motionUnavailable（服务接入后才到 motionStyleReady）
```

`CreationTask=optimize|style|cleanup|motion` 是首页四个同级任务的持久化身份，用户在选图前确定它。presentation 从任务派生 `creationIntent=apply|motion`：前三项进入本地静态分支，动态效果进入独立生成分支。每条流程只显示当前任务一致的一个主操作；动态服务未接入时必须进入不可用状态，不能展示可执行生成 CTA。旧 `apply` 草稿迁移为 `style`。

“应用风格”把风格编译为不可见、确定性、可撤销的静态编辑配方；“让图片动起来”从来源图片和已确定风格创建独立派生媒体。静态与生成执行分支共享来源与分支无关的风格定义，但不共享就绪状态、执行器或失败语义。生成不要求先应用，也不要求先创建静态提交。

详细合同见[静态风格执行](style-execution.md)、[派生媒体生成](generation-pipeline.md)和 [ADR 0004](../adr/0004-style-first-creation.md)。

## 依赖方向

```text
app（组装、主题、路由）
  └─ feature/presentation（首页任务入口、CreationTask、creationIntent、分支就绪状态）
       └─ feature/application（会话与用例编排）
            └─ feature/domain（来源身份、风格、编辑状态、生成任务）

静态应用：StyleDefinition → EditingCore → RenderPlan
                                ├─ PhotoPreviewRenderer Adapter
                                └─ PhotoExporter Adapter

派生生成：SourcePhoto + StyleDefinition
             → GenerationSourceSnapshot → GenerationCoordinator
                                          ├─ GenerationProvider Adapter
                                          └─ GeneratedMediaStore Adapter
```

- `domain` 不依赖 Flutter UI、插件或供应商 SDK。
- `application` 可以使用 Flutter 的基础状态原语，但不导入 Widget。
- `presentation` 只表达首页任务选择、图片、当前任务与分支状态，不暴露元操作目录、供应商任务或原生渲染细节；优化和清理可以显示受支持的任务专属本地操作。
- `CreationTask` 持久化用户选择；`creationIntent` 只在 presentation 会话中选择 `apply` 或 `motion` 的导航与 CTA，不是 `StyleDefinition`、`EditRecipe`、`RenderPlan` 或供应商 payload 的字段。
- `applyStyleReady` 只允许进入静态应用；`motionStyleReady` 只允许进入动态生成。二者不是带不同按钮的同一页面状态。
- `app` 只负责组装，不承载修图或生成规则。
- 页面不直接调用图像 SDK、生成供应商或持久化实现。
- Flutter 与原生静态图像边界只传文件引用、版本化计划、区域和状态，不传完整图片字节。
- 上传、轮询、取消和派生媒体下载只属于生成管线，不得进入静态 `EditRecipe` 或 `RenderPlan`。

启动阶段由 `StartupCoordinator` 区分首屏必需准备与可延迟任务；主题和语言由根部 Provider 注入的 `AppSettings` 管理，并通过 SharedPreferences 恢复。生成供应商初始化不是首页或任一静态任务入口的前置条件，供应商不可用也不能阻断本地优化、换风格或清理。

## 核心 Module

### 来源与项目

`PhotoProjectSession` 管理应用自有、只读的来源图片及其当前编辑状态。系统相册临时路径先由 `AppOwnedPhotoImporter` 转为应用自有副本；项目只保存相对媒体引用和内容身份，页面不依赖图片选择插件、文件复制或 JSON 格式。

默认交互一次围绕一张当前图片完成。多个草稿可以独立存在，但批量范围、整组同步和传统工具分类不进入主流程。

### 静态风格执行

静态风格执行是一个深 Module。调用方只需要提交当前来源身份和 `StyleDefinition`，并接收预览、提交结果或结构化拒绝原因。Module 内部隐藏参数、元操作、能力校验、事务、历史和 `RenderPlan` 编译。

同一来源、风格版本、引擎能力和编辑基线必须生成稳定结果。换风格流程中浏览或切换风格只更新临时预览；进入 `applyStyleReady` 并明确选择“应用风格”后，才原子替换既有风格层并形成一个可撤销步骤。优化和清理通过同一静态安全/持久化边界执行，但不借用风格任务身份。具体合同见[静态风格执行](style-execution.md)和 [ADR 0003](../adr/0003-editing-core-and-render-plan.md)。

### 静态预览与导出

版本化 `ImagePipeline` 不重解释已发布语义。`PhotoPreviewRenderer` 从应用自有来源创建原生纹理预览，`PhotoExporter` 从只读原图重放同一 `RenderPlan`；未知版本、越界字段、不完整目标和不支持的非中性能力必须严格拒绝。具体决定见 [ADR 0002](../adr/0002-native-preview-pipeline.md)。

### 派生媒体生成

`GenerationCoordinator` 管理独立异步任务，公开创建、观察、取消、重试和删除派生产物的最小 Interface。供应商协议、轮询、幂等、超时、成本保护、恢复和产物校验都留在 Module 内部。

“做动态效果”流程在首页先确定 `CreationTask.motion` 与 `creationIntent=motion`，再选图和定风格；当前服务未接入时进入 `motionUnavailable`，不创建任务。服务接入后才进入 `motionStyleReady` 并显示“让图片动起来”。生成输入绑定不可变的 `GenerationSourceSnapshot`，由 `SourcePhoto` 与已经确定的 `StyleDefinition` 创建，可包含专供生成的冻结参考渲染，但不依赖 `StyleCommit`。后续换图或改风格不会篡改既有生成结果，只会使其相对当前选择变为过期。生成失败、取消或供应商不可用不得改变静态编辑状态，也不得阻断静态任务与导出。具体合同见[派生媒体生成](generation-pipeline.md)。

## 暂不引入

- 不恢复“分类 → 工具 → 参数”的传统编辑主界面。
- 不把四个任务压回笼统“图片应用”入口；也不在定好风格后同时展示“应用风格”和“让图片动起来”，或使用一个共享 `styleReady` 承担不同任务流。
- 不让页面或 AI 直接拼装任意 shader、脚本、`RenderPlan` 或供应商 payload。
- 不把生成进度、提示词、远程任务 ID、视频 URL 或帧状态加入静态 `EditRecipe`。
- 不因潜在多供应商提前暴露供应商选择；差异只存在于生成 Adapter 内。
- 不把生成供应商初始化加入首屏关键路径。
- 不创建通用 `utils`、`managers` 或 `services` 垃圾目录。

## 新功能落位

- 风格定义、验证与替换规则：`lib/features/editor/domain/`。
- 风格应用、预览和提交编排：`lib/features/editor/application/`。
- 首页任务入口、`CreationTask`、`creationIntent`、分支图片与风格选择界面：对应 Feature 的 `presentation/`。
- 生成请求、任务和派生产物领域模型：`lib/features/generation/domain/`。
- 生成编排和供应商 seam：`lib/features/generation/application/`。
- 供应商、下载与媒体存储 Adapter：`lib/features/generation/infrastructure/` 或平台目录。
- 跨 Feature 组装：`lib/app/`。

测试通过 Module Interface 验证公开结果，不镜像内部目录或供应商协议。新增用户可见页面或路由时，仍必须同步扩展生产导航的 `integration_test`。
