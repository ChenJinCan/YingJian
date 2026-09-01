# 映见

**让变美更容易。**

映见是一款按结果任务组织的极简 AI 视觉创作应用。用户在首页先选择清晰的任务，再进入只服务该任务的选图、操作和结果流程，无需学习传统修图工具。

## 核心体验

1. **优化照片**：自然优化、AI 修复、高清放大、老照片修复。
2. **换风格**：官方风格、文字定风格、语音定风格、参考图风格、AI 风格重绘。
3. **去背景 / 去杂物**：人物白底、透明抠图、替换背景、去路人、涂抹去物。
4. **做动态效果**：轻微动态、镜头推进、光影流动；用户选定方向后再主动“生成动态照片”。

四张卡片只确定 `CreationTask`，不授权任务内的具体能力。选图后按固定顺序完整展示能力且不默认选中；只有用户点击的 `CreationCapability` 才能进入对应执行链。任何图片分析、AI、历史或设备能力都不得替用户推荐、排序、组合、切换、降级或执行能力。

四个任务共享只读原图与可恢复草稿原则，但拥有独立页面、状态、结果和失败恢复。`CreationIntent` 只区分静态与动态页面分支，不能代替具体能力选择或上传、生成、费用授权；旧静态 `apply` 草稿恢复为“换风格”。当前 iOS 已包含本地 2×/4× 高质量放大和三项本地 MP4 动态；六项云端能力通过部署在 Cloudflare 的第一方网关接百度、阿里与火山，其中“AI 自然动效”是独立选择，不覆盖或回退到三项本地动态。只有安装认证、权益、配额和对应供应商配置完整的能力才启用。真实边界见 [MVP Spec](docs/product/mvp-spec.md)。

## 产品原则

- 图片与结果是视觉主体；首页突出四个任务入口，进入任一任务后每个页面只突出一个主操作。
- 任务路径不会在下游页面互相竞争；切换任务返回首页。
- 初始体验简单、安静、低决策；更多解释和高级能力按需展开。
- 风格是用户语言，AI 帮助定义风格；内部执行参数不构成用户旅程。
- 源照片只读，创作过程可预览、可撤销、可恢复，结果可独立导出。
- 本地与云端执行只服务用户已明确选择的能力；生成失败不得破坏已有结果，也不得自动改走其他能力。
- 动态作品在服务接入后是正式创作结果，不是静态效果或界面动画。

本文描述产品目标，不代表每项能力已经在当前构建中交付。当前实现范围和完成度以仓库代码、自动化测试及验证证据为准。

## 文档入口

- [Agent 工作规则](AGENTS.md)
- [领域语言](CONTEXT.md)
- [界面设计合同](DESIGN.md)
- [文档路由](docs/README.md)
- [产品上下文](docs/product/product-context.md)
- [MVP Spec](docs/product/mvp-spec.md)
- [风格系统](docs/product/style-system.md)
- [Flutter 工程基座](docs/architecture/flutter-foundation.md)
- [静态风格执行](docs/architecture/style-execution.md)
- [派生媒体生成管线](docs/architecture/generation-pipeline.md)
- [MVP 质量基线](docs/quality/mvp-quality-baseline.md)
- [开发验证工作流](docs/agents/development-validation-workflow.md)
- [发布合同](docs/release-contract.md)

## 本地开发

```sh
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

Flutter 与 Dart 基线、平台要求、隐私边界、集成测试门禁和发布授权以 [AGENTS.md](AGENTS.md) 及相应专题文档为准。
