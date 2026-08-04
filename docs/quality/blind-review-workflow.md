# 本地匿名图片评审工作流

本工作流用于自然人像、基础光色和整组一致性的匿名评审。所有原图、候选结果、许可证明、映射键和评审者原始表均位于被 Git 忽略的 `.quality/`，不上传照片或面部数据。

## 1. 准备输入

先让 `quality/corpus-manifest.yaml` 中的资产通过完整清单门禁。每张候选结果从相同的只读原图、冻结配方和已记录的能力版本产生，并在 `.quality/review-inputs/<asset-id>/` 保存浏览器可查看的 JPEG 或 PNG。

复制 `quality/blind-review-plan.example.yaml` 到 `.quality/review-plan.yaml`，为每项填写：

- 不可逆样片 ID 与标签；可改善样片必须包含 `improvable`；
- 原图、映见关闭/默认/高安全强度原图导出、映见默认预览和竞品固定路径导出；每项必须恰有六个结果且每个槽位唯一，原图为 `baseline_original`，映见为 `subject`，竞品为 `reference`；
- 每个文件的真实小写 SHA-256；
- 所有渲染结果必须来自同一设备和系统；映见四个结果使用同一能力版本，默认预览与默认导出的参数必须完全相同。

每个候选的 `provenance` 必须记录 producer、能力或应用版本、设备、系统、variant、source/export/preview 身份和完整参数；非原图候选的 `source_sha256` 必须等于该项原图哈希；竞品还必须记录可复现的 `operation_path`。评分冻结只接受映见 `default + export` 身份，不能拿 Preview 或高强度结果替代。

iOS Debug-only 人像采集工具会为单个输入生成 baseline、off/default/high-safe 原像素导出、默认代理预览和 `capture-manifest.json`。工具启动和每次新分析都会删除上一批临时采集，因此必须先将整组目录从设备复制到 `.quality/review-inputs/<asset-id>/`，再继续下一张。复制后先运行严格采集检查；它会核对物理设备身份、原始输入哈希、源尺寸、候选版本、强度、sRGB/方向/尺寸、五个产物哈希、关闭档字节等价和无人脸降级：

```sh
ruby scripts/check_portrait_capture_manifest.rb \
  .quality/review-inputs/<asset-id>/capture-manifest.json
```

随后把 `quality/portrait-review-intake.example.yaml` 复制到被忽略的 `.quality/portrait-review-intake.yaml`，逐项记录不可逆 asset ID、标签、原图来源记录，以及同一设备和系统上的竞品版本、固定操作路径、完整参数和独立文件哈希。生成器会再次验证所有采集目录和竞品文件，并冻结整轮映见/竞品版本、设备、系统、强度与操作路径；它拒绝 Simulator、重复原图或竞品、跨设备、跨配置、非 sRGB/方向 1/原像素竞品、哈希漂移、符号链接逃逸和已有输出覆盖，再确定性生成六槽计划：

```sh
ruby scripts/build_portrait_review_plan.rb \
  .quality/portrait-review-intake.yaml \
  .quality/review-plan.yaml
```

`capture-manifest.json` 只证明产物身份，不证明人像质量，也不能把 `productionEligible=false` 改成生产资格。`--allow-simulator` 只允许单独诊断采集合同，生成正式 review plan 仍只接受 `physical-device`。

候选 `id` 只进入独立映射键，不进入评审页面或评分表。

## 2. 构建盲评包

```sh
ruby scripts/build_blind_review_package.rb \
  .quality/review-plan.yaml \
  .quality/reviews/portrait-round-1 \
  --seed portrait-round-1-frozen-seed
```

产物：

- `participant-package/index.html`：只显示随机化的 item/candidate code；
- `participant-package/images/`：按盲码复制的候选图片；
- `participant-package/score-sheet.csv`：评审者填写的 1–5 分模板；
- `review-key.json`：位于参与者包之外，保存盲码到资产和候选身份的映射，评审结束前不得交给评审者。

同一计划和 seed 必须产生相同映射。构建器拒绝缺图、哈希不符、重复 ID、六槽矩阵不完整、跨槽身份不一致、非 JPEG/PNG 结果和少于五名评审的计划。输入与输出必须位于被忽略的 `.quality/`；候选图会解码并重新栅格化为 PNG，参与者包不携带源文件元数据或身份映射键。

评分完成前必须保留原始 plan、六槽源文件和参与者图片，且不得改写。评分门会重新校验 plan 哈希、由冻结 seed 重算 item/candidate 盲码、key 与 plan 的标签/身份映射、每个源文件的真实 SHA-256、`.quality/` 路径边界、来源链和六槽一致性，并从源候选重新执行同一净化流程，逐项比对参与者 PNG 与方向归一、sRGB RGBA 像素摘要。六个槽位分别要求至少 48 个不同的归一像素摘要；仅在 key 中填写不同哈希、修改盲码、替换参与者图片或给同一图追加不同元数据，不能满足 48 张独立输入门禁。

## 3. 收集评分

每名评审者独立复制评分表，为待验收候选的每个 item 填写一行。合并后的 CSV 必须保留以下字段：

- `reviewer_id`、`item_code`、`baseline_code`、`candidate_code`；参与者页面会把随机化后的原图盲码明确标记为“原图锚点”，但不会标记映见或竞品身份；
- 整体改善、自然度、身份保持、纹理、肤色光线、局部边界和非皮肤保护的 1–5 分；
- `catastrophic_error` 与 `preferred_over_baseline` 的 `true/false`；后者只表示当前 `subject` 相对该 item 的 `baseline_original` 是否更优；
- 可选备注不得写入真实姓名、原图路径或其他个人数据。

## 4. 执行冻结门

```sh
ruby scripts/check_blind_review_scores.rb \
  .quality/reviews/portrait-round-1/review-key.json \
  .quality/reviews/portrait-round-1/combined-scores.csv \
  --candidate yingjian-default \
  --output .quality/reviews/portrait-round-1/summary.json
```

门禁要求 48 个独立 item，其中至少 36 个 `portrait_single`、12 个 `negative_safety`，并覆盖 `deep_skin`、`beard`、`freckles_moles`、`glasses`、`makeup` 和 `improvable`；至少五名完整评审者；身份保持中位数不低于 4.5，其余安全维度不低于 4.0；自然度、身份和局部边界不得出现 1 分；灾难性错误为零；`improvable` 子集相对明确原图基准的偏好率至少 65%。危险子集分别输出并执行相同安全中位数门，不能由总体平均掩盖。任何缺失行、重复评分或非法值均失败。

通过只证明该候选在本轮人工门中达标。仍需自动图像正确性、危险子集、公平性、双端语义、许可、离线和 Profile/Release 物理设备门，才能形成采用 ADR。
