# 映见

智能修图与照片编辑应用。

> 一张精修，整组好看。

## 当前状态

- 已建立 `app → presentation → application → domain` 的轻量 Flutter 骨架。
- 已按 NextNote、NatureID、animalplant 的共同实践接入启动协调、Provider 状态、本地设置和官方中英文资源。
- 已实现曝光、对比度、色温三项本地配方，支持实时预览、手势级撤销、重置和项目恢复。
- 已实现 1–9 张系统相册导入、应用自有文件副本、真实照片预览和项目 JSON 恢复；原始选择文件保持只读。
- 已绑定独立 Firebase 项目 `yingjian-ce1d1`，并接入隐私优先的 Analytics、Crashlytics、Performance 适配层；供应商初始化失败仍不阻塞启动。
- 设置页提供匿名诊断开关、中英文隐私政策/条款、开源许可和永久评分入口。
- 系统评分请求由价值时刻、冷却期、版本与失败状态策略控制，待真实导出链路完成后接入。
- Flutter UI 负责交互和编排；照片选择、可迁移项目恢复和原生高清导出 Adapter 已接入。iOS 使用 Core Image/PhotoKit，Android 使用 Bitmap/MediaStore，从应用自有原图副本按原始像素尺寸导出 JPEG；批量一致性与更完整的图像质量门仍待实现。
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
ruby scripts/check_legal_setup.rb
```

架构与依赖方向见
[`docs/architecture/flutter-foundation.md`](docs/architecture/flutter-foundation.md)，
三款现有应用的采用/拒绝依据见
[`docs/architecture/cross-app-foundation-audit.md`](docs/architecture/cross-app-foundation-audit.md)。
产品定位、竞品基线和当前 MVP 交付合同见
[`docs/product/product-context.md`](docs/product/product-context.md)、
[`docs/product/competitor-baseline.md`](docs/product/competitor-baseline.md) 和
[`docs/product/mvp-spec.md`](docs/product/mvp-spec.md)。
MVP 图像输入输出、样片、盲评、设备与性能门见
[`docs/quality/mvp-quality-baseline.md`](docs/quality/mvp-quality-baseline.md) 和
[`docs/adr/0001-mvp-image-io-contract.md`](docs/adr/0001-mvp-image-io-contract.md)。
Firebase 配置与验收见
[`docs/operations/firebase-observability.md`](docs/operations/firebase-observability.md)，
隐私与商店阻断项见
[`docs/legal/store-privacy-checklist.md`](docs/legal/store-privacy-checklist.md)。

构建、签名、测试分发、审核和公开发布是相互独立的阶段；当前仓库仍是本地开发基线，两个平台的正式签名、商店素材和最终产物验证尚未完成。
