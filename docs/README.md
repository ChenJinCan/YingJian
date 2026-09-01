# 映见文档路由

按任务读取最少必要文档。当前合同、实现证据与历史材料不得互相替代。所有活跃文档必须把“优化照片”“换风格”“去背景 / 去杂物”“做动态效果”作为选图前的四个首页任务，并让每条下游路径只保留当前任务主操作；偏离该结构时，先修正文档边界再据此实施。

## 所有开发任务

1. [AGENTS.md](../AGENTS.md)：产品北极星、工作规则、架构边界和强制门禁。
2. [CONTEXT.md](../CONTEXT.md)：唯一领域语言源。
3. [README.md](../README.md)：面向用户的核心体验与产品原则。
4. [开发验证工作流](agents/development-validation-workflow.md)：实现、Simulator、候选冻结与真机验收的统一时序。

## 产品与体验

- [产品上下文](product/product-context.md)：稳定北极星、目标用户、价值和长期边界。
- [MVP Spec](product/mvp-spec.md)：唯一可执行的首阶段范围、主旅程和可观察验收。
- [风格系统](product/style-system.md)：风格定义、风格来源、AI 协作，以及四个用户任务与两个执行分支的边界。
- [界面设计合同](../DESIGN.md)：四个首页任务入口、图片主体、极简层级和任务专属单主操作的呈现规则。
- [竞品基线](product/competitor-baseline.md)：当前比较对象与需要验证的差异，不构成产品主路径。

产品范围冲突时，以产品上下文确定方向，以 MVP Spec 确定当前交付范围，以 CONTEXT.md 统一命名；三者必须同步修正，不得用历史文档补齐冲突。

## 架构与质量

- [Flutter 工程基座](architecture/flutter-foundation.md)：分层、依赖方向、平台边界与应用组装。
- [静态风格执行](architecture/style-execution.md)：风格定义如何形成确定性应用结果。
- [派生媒体生成管线](architecture/generation-pipeline.md)：静态与动态生成任务、隐私、幂等和结果生命周期。
- [四任务首页 ADR](adr/0005-four-task-home.md)：用户任务身份与静态/生成执行分支分离的决定。
- [Style-first creation ADR](adr/0004-style-first-creation.md)：从工具编辑转向风格优先的架构决定；首页入口部分已由 ADR 0005 取代。
- [现有编辑核心 ADR](adr/0003-editing-core-and-render-plan.md)：仅保留仍有效的内部执行约束；其产品入口部分已被新 ADR 取代。
- [MVP 质量基线](quality/mvp-quality-baseline.md)：主旅程、静态应用、动态作品、设备与人工验收门。
- [样片清单](../quality/corpus-manifest.yaml)：被忽略本地样片的结构化校验入口。

代码、测试、fixture、最终产物和结构化质量报告是执行证据；文档不复制每轮日志，也不能替代当前构建验证。

## 发布与运营

- [发布合同](release-contract.md)：候选身份、本地构建、签名、上传与商店状态边界。
- [商店隐私与法律检查表](legal/store-privacy-checklist.md)：隐私、Terms、EULA、订阅与受保护元数据。
- [遥测与供应商边界](operations/)：事件白名单、诊断同意和供应商隔离。

发布、上传、测试组分发、审核和公开发布是不同状态，并分别需要对应授权。

## 历史材料

[docs/archive/](archive/) 保存已经被当前方向取代但仍有追溯价值的旧交互方案、日期状态、能力纵切、竞品研究和质量流程。其范围、版本、测试数量、待办和相对链接均不是当前事实；旧交互 PRD 与日期化状态快照不得作为活跃入口或验收合同。

需要历史依据时先读 [历史文档索引](archive/README.md) 的替代关系，再回到当前产品、架构和质量合同重新核验。
