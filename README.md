# 映见

智能修图与照片编辑应用。

> 一张精修，整组好看。

## 当前状态

- 已建立 `app → presentation → application → domain` 的轻量 Flutter 骨架。
- 已按 NextNote、NatureID、animalplant 的共同实践接入启动协调、Provider 状态、本地设置和官方中英文资源。
- 已实现可测试的非破坏编辑配方、手势预览、撤销和重置状态。
- 已建立隐私优先的 Firebase Analytics、Crashlytics、Performance 适配层；原生远端配置完成前保持不可用而不阻塞启动。
- 设置页提供匿名诊断开关、中英文隐私政策/条款、开源许可和永久评分入口。
- 系统评分请求由价值时刻、冷却期、版本与失败状态策略控制，待真实导出链路完成后接入。
- Flutter UI 负责交互和编排，原生图像处理能力将在真实 Adapter 出现后接入。
- 仅初始化 iOS 与 Android。
- iOS 最低系统版本为 15.0（Firebase Apple SDK 当前依赖基线）。
- 应用标识：`com.babycompany.yingjian`。
- 暂定品牌“映见”仍需完成商标、域名和应用商店全渠道查重。

## 本地验证

```sh
flutter analyze
flutter test
flutter gen-l10n
bash scripts/test_release_contract.sh
bash scripts/check_firebase_setup.sh
ruby scripts/check_legal_setup.rb # 上线信息未配置时应明确失败
```

架构与依赖方向见
[`docs/architecture/flutter-foundation.md`](docs/architecture/flutter-foundation.md)，
三款现有应用的采用/拒绝依据见
[`docs/architecture/cross-app-foundation-audit.md`](docs/architecture/cross-app-foundation-audit.md)。
Firebase 配置与验收见
[`docs/operations/firebase-observability.md`](docs/operations/firebase-observability.md)，
隐私与商店阻断项见
[`docs/legal/store-privacy-checklist.md`](docs/legal/store-privacy-checklist.md)。

构建、签名、测试分发、审核和公开发布是相互独立的阶段；当前仓库仅为本地开发基线。
