# 映见

映见是一款以本地图像处理引擎为核心的移动端智能修图应用。

> 让变美更容易。一张精修，整组好看。

当前 MVP 首发平台为 iOS，输入以相册中的 1–6 张已有图片为主。功能范围与验收标准以 [MVP Spec](docs/product/mvp-spec.md) 为准；当前候选和开放门禁见 [MVP 状态快照](docs/product/mvp-session-handoff-2026-08-10.md)。README 不缓存具体功能完成度、版本号或商店状态。

## 开发入口

- 工作规则：[AGENTS.md](AGENTS.md)
- 领域术语：[CONTEXT.md](CONTEXT.md)
- 实现与验证时序：[功能优先工作流](docs/agents/development-validation-workflow.md)
- 架构边界：[Flutter 工程基座](docs/architecture/flutter-foundation.md)
- 图像质量与最终验收：[MVP 质量基线](docs/quality/mvp-quality-baseline.md)
- 构建与交付：[发布合同](docs/release-contract.md)

常用本地检查：

```sh
flutter analyze
flutter test
bash scripts/test_release_contract.sh
```
