# 映见

**让变美更容易。**

映见是一款按结果任务组织的极简 AI 视觉创作应用。用户在首页先选择“图片应用”或“动起来”，再进入只服务该任务的选图、定风格和结果流程，无需学习传统修图工具。

## 核心体验

1. **选择任务**：首页用两个大入口直接询问用户要“图片应用”还是“动起来”。
2. **图片应用**：选图片 → 定静态风格 → 应用风格 → 保存或分享静态结果。
3. **动起来**：选图片 → 定动态方向与风格 → 确认生成 → 播放、保存或分享动态结果。

两个任务共享一致的风格语言和只读原图原则，但拥有独立页面、状态、结果和失败恢复。浏览风格不会自动上传、生成或扣费；“动起来”只有在用户确认后才创建云端任务，并清楚说明等待、数据和权益成本。

## 产品原则

- 图片与结果是视觉主体；首页突出两个任务入口，进入任一任务后每个页面只突出一个主操作。
- 两条任务路径不会在定风格页面互相竞争；切换任务返回首页。
- 默认体验简单、安静、低决策；更多解释和高级能力按需展开。
- 风格是用户语言，AI 帮助定义风格；内部执行参数不构成用户旅程。
- 源照片只读，创作过程可预览、可撤销、可恢复，结果可独立导出。
- 确定性应用优先本地完成；生成是可选增强，失败不得破坏已有结果。
- 动态作品是正式创作结果，不是静态效果或界面动画。

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
