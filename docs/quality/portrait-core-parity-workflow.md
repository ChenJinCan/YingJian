# 六项人像核心能力同图质量工作流

本工作流只评价竞品入场能力，不替代既有七槽自然人像盲评、自动图像正确性或物理设备性能门。所有原图、映见结果、醒图结果、计划、评分和摘要保存在 Git 忽略的 `.quality/`；不得把真实图片、人脸数据或评审身份提交到仓库。

## 1. 准备同图计划

将 `quality/portrait-core-quality-plan.example.yaml` 复制为 `.quality/portrait-core-quality-plan.yaml`，为六项能力分别准备可改善样片、保护子集和负向安全输入：

- `one_tap_natural`
- `texture_smoothing`
- `skin_tone_lighting`
- `blemish_reduction`
- `face_slimming`
- `torso_slimming`

每个 item 必须绑定同一原图的 SHA-256、映见最终导出和醒图最终导出。映见记录准确效果版本、参数和从已有图片导入到导出的路径；醒图固定 App Store ID `1500526240`、bundle ID `com.xt.retouch`，并记录采集时实际版本、完整参数和可复现操作路径。计划及所有文件必须位于 `.quality/`，哈希或源图身份不一致时检查器会失败。

计划还必须绑定 `blind_protocol`：候选位置使用固定种子随机化，种子只记录 SHA-256；盲码映射文件及其 SHA-256 留在 `.quality/`，不能交给评审者。检查摘要只记录随机化方法和映射哈希，不输出映射路径或内容。

正式轮次应把可改善输入和负向/保护输入分开，不应用一张占位图同时冒充所有标签。工具只冻结结构与门槛；样片授权、版本、参数和结果真实性仍由采集证据负责。

## 2. 收集匿名评分

至少五名评审者完成全部 item。参与者界面应随机左右位置并隐藏映见/醒图身份；结束后再把盲码映射为以下 CSV：

```csv
reviewer_id,item_id,naturalness,identity_preservation,protection,catastrophic_error,preferred_over_original,comparison_to_xingtu,notes
reviewer-01,one-tap-001,4,5,4,false,true,tie,
```

三个评分维度取 1–5 整数；`comparison_to_xingtu` 只接受 `yingjian_win`、`tie`、`xingtu_win`。备注不得包含姓名、图片路径或其他个人数据。每位评审者必须覆盖所有 item，缺行和重复行都会失败。

## 3. 执行门禁

```sh
ruby scripts/check_portrait_core_quality_scores.rb \
  .quality/portrait-core-quality-plan.yaml \
  .quality/portrait-core-quality-scores.csv \
  --output .quality/portrait-core-quality-summary.json
```

门禁按能力分别要求：

- 可改善子集相对原图偏好率不低于 65%；
- 对醒图胜出或持平不低于 50%；
- 自然度、身份保持和对应保护中位数均不低于 4/5，且不得出现 1 分；
- 灾难性错误为零。

摘要始终分别报告六项能力的 item 数、评分行数、中位数、原图偏好率、醒图胜出或持平、覆盖标签和灾难错误。任一能力失败会返回非零状态，其他能力高分不能抵消。

## 4. 工具自测

```sh
ruby scripts/test_portrait_core_quality_scores.rb
```

自测覆盖完整通过、缺失盲评协议、缺失能力、缺失负向输入、原图偏好不足、醒图对齐不足、灾难错误、评审缺行和竞品未绑定同一源图。
