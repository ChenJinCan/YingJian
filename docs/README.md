# 映见文档路由

先根据任务类型读取最少必要文档。规范、状态和历史证据不得互相替代。

## 所有开发任务

1. [`AGENTS.md`](../AGENTS.md)：工作规则、架构边界和强制门禁。
2. [`CONTEXT.md`](../CONTEXT.md)：唯一领域术语源。
3. [功能优先工作流](agents/development-validation-workflow.md)：实现、Simulator 和真机的统一时序。

## 产品与功能

- 稳定产品策略：[产品上下文](product/product-context.md)
- MVP 范围与验收：[MVP Spec](product/mvp-spec.md)
- 当前候选与开放门禁：[状态快照](product/mvp-session-handoff-2026-08-10.md)
- 自然人像独特合同：[自然人像纵切](product/natural-portrait-retouch-vertical-slice-spec.md)
- 几何塑形独特合同：[塑形纵切](product/portrait-reshape-vertical-slice-spec.md)
- 画质改善独特合同：[画质纵切](product/quality-enhancement-vertical-slice-spec.md)

只在对应功能发生变化时读取纵切 Spec；总体范围冲突时以 MVP Spec 为准，并同步修正纵切文档。

## 架构与质量

- Flutter 与原生边界：[Flutter 工程基座](architecture/flutter-foundation.md)
- 已采用的开源图像参数：[MVP 开源算法标定](architecture/mvp-open-source-calibrations.md)
- 不可逆架构决策：[`adr/`](adr/)
- 图像合同、阈值和最终验收：[MVP 质量基线](quality/mvp-quality-baseline.md)
- 设备、盲评、竞品与可用性执行格式：[`quality/`](quality/)

脚本、配置、fixture 和结构化 `.quality/` 报告是当前执行证据；文档不复制每轮日志。

## 竞品与研究

- 当前比较角色与任务：[竞品基线](product/competitor-baseline.md)
- 官方来源证据：[竞品深度研究](product/competitor-deep-research.md)
- Android 包静态线索：[APK 静态分析](product/competitor-apk-static-analysis.md)
- 端侧人像技术依据：[`research/`](research/)

日期化研究是历史证据。涉及版本、价格、商店、隐私政策或可用性时必须重新核验，不能把快照当作当前事实。

## 发布与运营

- 候选构建与交付：[发布合同](release-contract.md)
- 商店隐私与法律：[法律检查表](legal/store-privacy-checklist.md)
- 遥测与供应商边界：[`operations/`](operations/)

发布、上传、审核和公开发布分别需要对应授权。
