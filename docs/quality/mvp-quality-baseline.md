# 映见 MVP 图像质量与工程基线

> 状态：iOS 首发合同已冻结，样片与 iOS 物理设备证据仍阻断；日期：2026-08-05。

## 1. 目的

本基线决定映见何时可以从“编辑演示”进入生产 MVP 实现。任何图像引擎、商业人像 SDK、推荐配方和导出实现都必须在同一输入、同一设备级别和同一评分规则下比较。

本文件不宣称当前代码已经达到目标。自动检查、真实样片盲评和 Profile/Release 物理设备证据缺一不可。

## 2. 当前事实

| 项目 | 当前事实 | 判定 |
|---|---|---|
| Flutter | 3.44.8 / Dart 3.12.2 | 已确认 |
| iOS 最低系统 | 15.0 | 已确认 |
| Android | min API 24，compile/target API 36 | 已有工程基线；本轮 MVP 验证延期且不阻断 iOS |
| 当前预览 | iOS Core Image Texture、Android GLES3 Texture；Flutter 矩阵仅兼容降级 | 目标接缝已实现，真机质量未验证 |
| iOS 导出 | Core Image 从原图输出 sRGB JPEG 95 并应用安全元数据策略 | 模拟器测试通过，真机未验证 |
| Android 导出 | API 28+ 单 Bitmap 原位分块变换；API 24–27 分块方向解码到单输出 Bitmap；JPEG 95 | 模拟器真实文件/48 MP 通过，真机内存门未验证 |
| 当前物理设备 | iPhone 14 Plus 已配对但当前锁屏阻止测试启动 | iOS 三档物理验证阻断 |
| 授权质量样片 | 本机忽略目录已有 48 资产工程语料，完整机器门通过；其中 10 张真实授权单人图用于人像候选观察，4 张多人图为授权人像技术合成，24 张组图为格式/曝光/白平衡/裁剪工程变体 | 图像合同工程输入已齐；竞品、真人盲评和真实拍摄组图仍阻断主观质量冻结 |

## 3. 冻结图像合同

规范性决策见 ADR 0001。摘要如下：

- 项目支持 1–6 张照片。
- iOS 首发必须支持 JPEG、无动画 PNG 和 HEIC/HEIF；Android 的既有格式合同保留到后续里程碑。
- 上限为 48 MP、最长边 12,000 px、100 MB。
- 预览标准最长边 2,048 px，低档设备可降至 1,280 px。
- MVP 输出为 sRGB JPEG，质量 95。
- 导出从只读原始输入重新渲染，不能连续重编码。
- 默认移除 GPS、MakerNote、人脸区域和应用内部信息，保留可用拍摄时间。
- iOS 的 Display P3 输入必须通过固定样片到 sRGB JPEG 的生产文件渲染回归；已有 Android 与跨端报告仅作历史工程证据，不属于本轮完成门，因此仍不得宣传跨平台广色域保真。

“原画质导出”在产品文案中的可验证含义是“原像素尺寸高质量导出”，不是有损 JPEG 与源文件逐字节相同。

## 4. 样片基准集

### 4.1 最低规模

完整门禁至少包含 48 个独立资产：

- 24 张单图样片。
- 6 组 × 4 张组图样片，共 24 张。
- 格式、方向和色彩变体可与上述内容复用，但必须在清单中作为独立资产固定哈希。

### 4.2 内容配额

| 标签 | 最低数量 | 主要验证 |
|---|---:|---|
| `portrait_single` | 8 | 单人自然度、肤色、纹理、侧脸和遮挡 |
| `portrait_multi` | 4 | 多人脸选择、强度一致和局部失败 |
| `no_face` | 8 | 风景、食物、宠物、建筑和通用配方回退 |
| `low_light` | 4 | 噪点、阴影、肤色和过度提亮 |
| `backlit` | 4 | 高光保护、面部补偿和动态范围 |
| `mixed_light` | 4 | 白平衡、局部偏色和组图补偿 |
| `group_member` | 24 | 六组不同曝光、白平衡、构图和人物位置 |
| `exif_rotated` | 4 | 八种 EXIF 方向中的高风险方向 |
| `jpeg` | 12 | 主输入和导出闭环 |
| `png` | 4 | 截图、透明合成和方向 |
| `heic` | 4 | iOS 与 Android API 28+ 解码 |
| `srgb` | 12 | 保证色彩闭环 |
| `display_p3` | 4 | P3 识别与 sRGB 转换 |
| `high_resolution` | 4 | 24–48 MP 内存和导出时间 |

单张可以拥有多个标签，但不得用复制同一文件的方式满足数量。

### 4.3 来源与隐私

- 允许：团队自摄并取得书面同意、明确允许测试和内部再分发的图库许可、明确允许此用途的生成样片。
- 禁止：真实用户照片、社交媒体下载图、来源不明的人脸、带客户标识的图像、无法证明授权的竞品截图。
- 每个资产必须记录来源类型、权利依据、是否允许仓库分发、同意/许可证引用和 SHA-256。
- 本地原始样片保存在被 Git 忽略的 `.quality/corpus/`；仓库只提交清单、哈希、匿名标签和评分结果。
- 入库前移除 GPS 和非必要身份元数据；人像盲评使用匿名样片 ID。

### 4.4 当前状态

`quality/corpus-manifest.yaml` 保留可提交的空清单合同，干净 checkout 的完整检查仍应失败。本机忽略的 `.quality/corpus-manifest.local.yaml` 已于 2026-08-05 固定 48 个有许可证据和 SHA-256 的资产，并通过完整检查：24 个单图、6 组各 4 个组图，覆盖 JPEG/PNG/HEIC、sRGB/Display P3、EXIF 非 1 方向和 24–32 MP。工程语料包含格式与光色变体以及明确标注的多人技术合成，只用于图像合同、回退和候选工程筛查；不能代替竞品同路径输出、至少 5 人盲评、真实拍摄组图或物理设备性能证据。

`scripts/run_ios_file_render_corpus.rb` 会直接编译应用生产使用的
`IOSPhotoFileRenderer.swift`、`IOSImagePipeline` 和人像依赖，而不是复制一套测试算法。
它把清单内全部 48 个只读源文件以中性 V2 配方重新渲染为最终 JPEG，并逐张检查：
源 SHA-256 前后不变、EXIF 方向归一后的原像素尺寸、JPEG、sRGB、Orientation=1、无 GPS/设备身份元数据。
报告同时绑定清单、生产渲染源码、人像源码和探针源码哈希，并标记
`engineering_only=true`。本机首轮 48/48 通过，覆盖 38 JPEG、6 PNG、4 HEIC、
37 sRGB、11 Display P3、4 个真实 EXIF 旋转和 20 个高分辨率资产；canonical 空清单仍 fail closed。
`scripts/run_android_file_render_corpus.rb` 会构建本地 Debug app/test APK，把同一批只读源图挂载到应用私有缓存，并由专用 instrumentation 逐张调用生产 `AndroidPhotoExporter`。最终 MediaStore JPEG 会先回拷到应用私有证据目录、回查后删除，再由宿主拉取到 `.quality`；报告绑定语料、生产 Kotlin 源码、instrumentation、宿主运行器、源码提交和模拟器 build fingerprint。本机 API 35 arm64 模拟器首轮同为 48/48 通过，且 canonical 空清单 fail closed。

已有双端结果证明当前生产文件渲染的格式、尺寸、源只读和隐私合同，但不证明预览帧率、峰值内存、物理设备耗时或主观质量。本轮只继续采集 iOS 证据；Android 模拟器与跨端结果保留但不计入 iOS MVP 完成门。

本机完整门命令为：

```sh
ruby scripts/check_image_quality_corpus.rb .quality/corpus-manifest.local.yaml
ruby scripts/run_ios_file_render_corpus.rb \
  .quality/corpus-manifest.local.yaml \
  .quality/ios-file-render-<source-id>
```

Android runner 仍可用于后续里程碑，但本轮不得自动启动 ADB、模拟器或 Android 语料任务。

清单条目使用以下结构；`evidence_ref` 指向本机被忽略的许可或同意证据，不提交个人资料：

```yaml
- id: portrait-001
  file: portraits/portrait-001.jpg
  sha256: 64位小写十六进制
  tags: [portrait_single, jpeg, srgb]
  media:
    format: jpeg
    width: 4032
    height: 3024
    color_space: srgb
    orientation: 1
  license:
    source_type: team_capture
    rights_basis: written_consent_for_internal_testing
    redistributable: false
    evidence_ref: .quality/evidence/portrait-001-consent.pdf
```

清单 schema 2 会用系统 ImageIO 工具实际回查格式、像素尺寸、嵌入色彩配置和方向，不接受只修改扩展名或标签来满足配额。完整门精确要求 48 张：24 张独立单图，以及 6 组各 4 张组图；不能用额外组图挤占单图，也不能用超额成员掩盖缺组。对应根字段为 `required_assets`、`required_single_assets`、`required_group_sets` 与 `required_members_per_group`。`high_resolution` 必须至少 24 MP，`exif_rotated` 必须具有非 1 的真实方向；所有资产同时受 48 MP、12,000 px 和 100 MB 输入硬门约束。许可证据必须位于被忽略的 `.quality/evidence/` 内，语料和许可证据的符号链接均不得逃逸仓库边界。

## 5. 自动质量门

本地授权语料补齐后，以下命令直接编译生产 `IOSPortraitRetoucher` 源码，重新生成关闭、默认和高安全档，并验证单人输入确实应用候选、无人脸/多人负例严格安全保持、三档不存在半生效状态、所有输出保持方向规范化后的原像素尺寸且为 sRGB JPEG。报告绑定语料 manifest、候选身份和 retoucher 源码 SHA-256，只是工程安全回归，不替代竞品同路径结果、五人盲评或物理设备证据：

```sh
ruby scripts/run_portrait_engineering_corpus.rb \
  .quality/corpus-manifest.local.yaml \
  .quality/portrait-engineering-<candidate-id>
```

下列项目任一失败即阻断对应图像链路：

1. **中性恒等性**：中性配方不得产生可见色偏、尺寸变化或重复压缩。
2. **方向**：所有支持的 EXIF 方向预览和导出一致，输出像素方向正确。
3. **尺寸**：除裁剪外，导出保持原始像素宽高；不得导出预览尺寸。
4. **裁剪坐标**：预览代理图和原图导出使用相同规范化坐标。
5. **确定性**：同一输入、配方和引擎版本得到稳定结果。
6. **原图只读**：源文件内容哈希在完整会话后不变。
7. **项目恢复**：保存、退出、恢复和导出不累积额外处理或重复压缩。
8. **元数据**：GPS、MakerNote 和内部编辑数据不出现在结果；拍摄时间按合同保留。
9. **部分失败**：一张损坏图不影响其他照片编辑和已完成导出。
10. **iOS 同义性**：同一配方的 iOS Texture 预览与原图导出保持相同方向、色彩趋势、构图和安全降级。

确定性光色操作使用数值或感知容差；人像自然度和审美推荐不能只用像素 Golden 判定。

### 5.1 已保留的双端中性导出证据（非本轮阻断门）

`neutral-export-v1` 只验证同一原图经 iOS 与 Android 生产文件渲染器执行中性配方后，解码、方向归一、sRGB 转换和 JPEG 95 导出的差异受控。它不验证非中性参数强度、人像自然度、推荐审美、预览帧率或设备性能，也不得用于替代盲评。

比较器将两端最终 JPEG 按方向归一并在显式 sRGB 中缩至最长边 512 px。48 张资产逐张满足以下硬门：

| 指标 | `neutral-export-v1` 上限/下限 |
|---|---:|
| RGB 平均绝对误差 | ≤ 1/255 |
| RGB 均方根误差 | ≤ 2/255 |
| 单通道最大绝对误差 | ≤ 32/255 |
| 亮度平均绝对误差 | ≤ 1/255 |
| 任一通道平均偏差绝对值 | ≤ 1/255 |
| 每像素最大通道误差 p95 / p99 | ≤ 3/255 / 4/255 |
| 最大通道误差超过 4 / 8 码值的像素比例 | ≤ 1% / 0.5% |
| PSNR | ≥ 42 dB；完全相同时允许为空 |

阈值以 8-bit 码值和稀疏异常比例冻结，不以一次观测的精确最大值回填；完全相同像素比例只记录，不作为 JPEG 跨实现门禁。执行：

```sh
ruby scripts/run_cross_platform_render_comparison.rb \
  .quality/ios-file-render-<source-commit> \
  .quality/android-file-render-<source-commit> \
  .quality/cross-platform-neutral-<source-commit>

ruby scripts/check_cross_platform_render_tolerance.rb \
  .quality/cross-platform-neutral-<source-commit>/observation-report.json
```

非中性 V2 配方另行验证：曝光、对比度和色温等可比较数值强度；高光、阴影、饱和度、色调、清晰度因平台算法不同，至少锁定方向、单调性、安全范围和视觉盲评，不能套用中性逐像素容差后宣称画质等价。

### 5.2 已保留的双端曝光语义证据（非本轮阻断门）

`exposure-semantic-v1` 使用同一 48 张语料分别执行 `-0.5 EV / 0 EV / +0.5 EV`，对两端生产最终 JPEG 在 sRGB、最长边 512 px 上测量平均亮度和黑白 clipping。每张照片必须满足：

- 两个相邻档位的平均亮度增量均不小于 `4/255`；
- iOS 与 Android 对应亮度增量的绝对差不超过 `1/255`；
- 三个档位的黑、白 clipping 比例跨端绝对差均不超过 `1%`。

该门锁定“曝光方向可见且双端强度一致”，不评价某张照片应自动选择多少曝光，也不允许用 `+0.5 EV` 工程探针替代推荐配方盲评。Android CPU 导出与 GLES 预览的曝光/对比度/色温基础矩阵必须在显式线性光域计算；CPU 可使用按配方预计算的通道查找表，但查找表结果必须与同一线性公式一致。

```sh
ruby scripts/check_exposure_semantic_alignment.rb \
  .quality/ios-render-semantic-<source>/observation-report.json \
  .quality/android-render-semantic-<source>/observation-report.json
```

### 5.3 iOS 对比度语义门

`ios-contrast-semantic-v1` 使用 iOS 生产文件渲染器对同一 48 张语料执行
`-0.35 / 0 / +0.35`。实现必须使用端点固定、中灰锚定的软曲线，不允许用线性光域
`0.5` 作为硬矩阵轴心而大面积压黑。自动合同由两类互补证据组成：

- 原生灰阶 ramp 经公开 `IOSImagePipeline` 验证：正对比度使暗部下降、亮部上升，负对比度方向相反，中灰保持在 2 个码值内，正档纯黑不得超过 10%；
- 48 张最终 sRGB JPEG 的负/正档相对中性档，逐张 RGB 平均绝对差均不得低于 `3/255`；
- 任一负/正档相对中性档的新增纯黑比例不得超过 `1.5%`，新增纯白比例不得超过 `5%`。白色上限覆盖明确的高键白背景工程样片，不代表主体高光自然度已经通过；主体观感仍由盲评阻断。

全局亮度标准差、边缘能量或“各通道距 0.5 的均值”受照片内容分布影响，不能作为每张
彩色照片都必须严格单调的对比度真值。报告仍保留这些观测量，但冻结门只使用灰阶响应、
可见差异和新增 clipping。执行：

```sh
ruby scripts/run_render_semantic_trend.rb ios contrast \
  .quality/ios-file-render-contrast-negative \
  .quality/ios-file-render-neutral \
  .quality/ios-file-render-contrast-positive \
  .quality/ios-render-semantic-contrast

ruby scripts/check_ios_contrast_semantics.rb \
  .quality/ios-render-semantic-contrast/observation-report.json
```

### 5.4 iOS 色温语义门

`ios-warmth-semantic-v1` 使用 iOS 生产文件渲染器对同一 48 张语料执行
`-0.4 / 0 / +0.4`。每张最终 sRGB JPEG 必须满足：

- 以 `mean(red) - mean(blue)` 定义的有限色温方向，冷→中性和中性→暖两个步长均不小于 `3/255`；
- 两个相邻档位的 RGB 平均绝对差均不小于 `1/255`；
- 负/正档相对中性档的平均亮度漂移均不超过 `2/255`；
- 新增纯黑和新增纯白比例均不超过 `0.5%`。

该门只锁定色温方向、可见强度和基础安全，不证明肤色偏好、混合光修复或自动白平衡推荐正确；
这些仍需要自然人像与混合光盲评。执行：

```sh
ruby scripts/check_ios_warmth_semantics.rb \
  .quality/ios-render-semantic-warmth/observation-report.json
```

### 5.5 iOS 高光与阴影语义门

`ios-selective-tone-semantic-v1` 使用 iOS 生产文件渲染器分别执行高光和阴影的
`-0.4 / 0 / +0.4`。两项都使用 sRGB 32³ color-cube 的亮度选择性软曲线：高光在亮部权重更高，
阴影在暗部权重更高，纯黑与纯白端点固定。原生灰阶回归必须证明双向变化以及目标亮度区域的
选择性；48 张最终 JPEG 每项还必须满足：

- 负档→中性和中性→正档的平均亮度步长均不小于 `1/255`；
- 两个相邻档位的 RGB 平均绝对差均不小于 `1/255`；
- 高光新增纯黑 ≤ `0.5%`、新增纯白 ≤ `1%`；
- 阴影新增纯黑 ≤ `1.5%`、新增纯白 ≤ `0.5%`。

旧实现把正高光传入系统滤镜的无效区间，48/48 正档均与中性完全相同；旧阴影滤镜还会让
高键样片新增纯白约 `5%`。这两种行为都被当前合同拒绝。执行：

```sh
ruby scripts/check_ios_selective_tone_semantics.rb \
  .quality/ios-render-semantic-highlights/observation-report.json \
  .quality/ios-render-semantic-shadows/observation-report.json
```

### 5.6 iOS 饱和度、色调与清晰度语义门

`ios-color-detail-semantic-v1` 按参数使用不同指标：

- 饱和度 `-0.35 / 0 / +0.35`：有色样片的平均色度相邻步长 ≥ `3/255`、RGB 平均绝对差 ≥ `1/255`；中性色度低于 `1/255` 的样片允许安全不变，但不得凭空染色；平均亮度漂移 ≤ `5/255`，新增黑白 clipping 均 ≤ `0.5%`。
- 色调 `-0.4 / 0 / +0.4`：以 `(mean(red)+mean(blue))/2-mean(green)` 定义洋红–绿色对手轴，相邻步长 ≥ `4/255`、RGB 平均绝对差 ≥ `2/255`；平均亮度漂移 ≤ `5/255`，新增黑白 clipping 均 ≤ `1%`。
- 清晰度 `-0.25 / 0 / +0.25`：平均边缘能量必须严格递增，两个相邻档位的逐像素最大通道差 p95 均 ≥ `1/255`；平均亮度漂移 ≤ `1/255`，新增黑白 clipping 均 ≤ `0.5%`。

这些机器门锁定方向、最低可见强度和安全范围；辉光、过锐、噪声放大、肤质损害仍由盲评判断。

```sh
ruby scripts/check_ios_color_detail_semantics.rb \
  .quality/ios-render-semantic-saturation/observation-report.json \
  .quality/ios-render-semantic-tint/observation-report.json \
  .quality/ios-render-semantic-clarity/observation-report.json
```

## 6. 人工盲评量表

每张候选结果由至少 3 名评审在校准显示环境下匿名评分。使用 1–5 分：

- 1：不可接受，存在明显伤害或任务失败。
- 2：较差，需要重新处理。
- 3：最低可用，存在可见但不阻断的问题。
- 4：自然可靠，可以直接发布。
- 5：明显优秀，优于常用替代方案。

### 6.1 单张基础质量

| 维度 | 观察内容 | 通过门 |
|---|---|---|
| 曝光与动态范围 | 主体清晰，高光不过曝，阴影不过度抬升 | 中位数 ≥ 4，任何样片不得为 1 |
| 白平衡与色彩 | 无不必要偏色，色彩符合配方意图 | 中位数 ≥ 4 |
| 细节与噪点 | 不出现光晕、断层、过锐或噪点放大 | 中位数 ≥ 4 |
| 构图与方向 | 裁剪和水平线正确，无坐标漂移 | 必须全部通过 |
| 预览/导出一致 | 结果趋势、裁剪和强度一致 | 必须全部通过 |

### 6.2 自然人像

| 维度 | 观察内容 | 通过门 |
|---|---|---|
| 身份保持 | 五官、脸型和人物特征未被意外改变 | 必须全部通过 |
| 肤色自然 | 不灰、不黄、不泛红，不跨区域突变 | 中位数 ≥ 4 |
| 纹理保护 | 毛孔和真实细节存在，无塑料皮肤 | 中位数 ≥ 4 |
| 边缘质量 | 头发、眼镜、遮挡和多人边缘无明显破坏 | 中位数 ≥ 3.5 |
| 克制程度 | 默认强度自然，不需要用户先撤销伤害 | 中位数 ≥ 4 |

### 6.3 整组一致性

| 维度 | 观察内容 | 通过门 |
|---|---|---|
| 共同风格 | 色彩倾向、对比和质感属于同一方向 | 每组中位数 ≥ 4 |
| 逐张正确性 | 单张没有因复制参数出现欠曝或偏色 | 每组不得出现 1 |
| 肤色连续性 | 同一人物跨照片肤色自然且稳定 | 每组中位数 ≥ 4 |
| 差异保留 | 夜景、逆光等场景特征没有被强行抹平 | 每组中位数 ≥ 3.5 |

## 7. 竞品对照规则

第一轮只固定醒图和 Berry：醒图代表单张精修基线，Berry 代表低决策审美基线。

- 使用同一原始样片和同一台设备显示结果。
- 记录竞品应用版本、设备、系统、操作路径、所用预设/参数、是否会员、导出尺寸和文件大小。
- 醒图选择最接近“自然可发布”的一键结果，并允许不超过 60 秒的基础微调。
- Berry 选择最接近目标方向的现有滤镜和强度，不额外补充其没有的深度工具。
- 映见分别记录三套推荐的首选结果和允许不超过 60 秒的微调结果。
- 评审看不到产品名称和处理方式。
- 竞品结果只建立比较基线，不进入映见训练、生产资源或商店素材。

当前竞品实机结果为 `数据缺失`，不得宣称映见已达到或超过竞品。

## 8. 物理设备矩阵

设备档位是采购/借测目标，具体型号可以替换，但芯片、内存和系统级别不得只覆盖旗舰机。

| 平台 | 档位 | 目标级别 | 必测输入 |
|---|---|---|---|
| iOS | 低 | iPhone 11 / A13 / 4 GB / iOS 15 | 12 MP、人像、六张组图 |
| iOS | 中 | iPhone 13 或 14 / 4–6 GB / 当前支持系统 | 12/24 MP、P3、HEIC、组图 |
| iOS | 高 | iPhone 15 Pro 或更新 Pro / 8 GB 级 | 48 MP、多人、批量导出 |

模拟器、Debug 和桌面运行只用于开发，不计入矩阵证据。当前 iOS 三个物理档位均为 `未验证`。Android 低/中/高档位延期到后续里程碑，不影响本轮 iOS MVP 与 TestFlight 判定。

## 9. 性能预算

以下为 Phase 0 继续投入门，均使用冻结样片、Profile 或 Release 和物理设备；记录 p50/p95，不用单次最好值。

| 指标 | 低档门 | 中档门 | 高档门 |
|---|---:|---:|---:|
| 单张首次可用预览 | ≤ 4.0 s | ≤ 2.5 s | ≤ 1.8 s |
| 六张三方案全部可检查 | ≤ 12 s | ≤ 8 s | ≤ 6 s |
| 滑块到画面响应 p95 | ≤ 120 ms | ≤ 100 ms | ≤ 80 ms |
| 连续调整最低帧率 | ≥ 24 fps | ≥ 30 fps | ≥ 45 fps |
| 12 MP 单张导出 | ≤ 8 s | ≤ 5 s | ≤ 3.5 s |
| 48 MP 单张导出 | ≤ 20 s | ≤ 12 s | ≤ 8 s |
| 六张 12 MP 批量导出 | ≤ 60 s | ≤ 40 s | ≤ 30 s |

附加硬门：

- Flutter UI 不得出现超过 100 ms 的主线程阻塞。
- 峰值附加内存不得超过设备物理内存的 25%，且不得超过 512 MB。
- 连续完成三轮六张导出不得崩溃、被系统杀死或产生不可恢复项目。
- 设备过热或内存压力时可以降低预览分辨率和并发，但不得降低最终输出尺寸。

预算可以在技术 Spike 后调整一次，但必须保存原始测量、解释变更，并同步更新 Spec；不能因为当前实现未达到而静默放宽。

## 10. Phase 0 退出条件

- [x] 产品闭环和竞品角色已冻结。
- [x] 图像输入、预览、输出、色彩和元数据合同已冻结。
- [x] 样片配额、权利要求和机器清单格式已冻结。
- [x] 自动门和人工盲评量表已冻结。
- [x] 设备档位和性能预算已冻结。
- [ ] 48 个合法样片及哈希已补齐。
- [ ] 醒图与 Berry 同样片结果已采集。
- [ ] iOS 低/中/高三档物理设备或获批替代矩阵已落实。
- [ ] Flutter → 原生预览 → 原图导出 Spike 已达到预算。
- [ ] 人像候选已通过盲评并形成采用/降级 ADR。

未勾选项完成前，Phase 0 状态为 `blocked-by-evidence`，可以制作交互原型和技术 Spike，但不能进入大规模生产功能实现或宣称 MVP 图像质量成立。

## 11. 验证命令

```sh
ruby scripts/check_image_quality_corpus.rb --allow-incomplete
ruby scripts/check_image_quality_corpus.rb
ruby scripts/test_image_quality_corpus.rb
ruby scripts/test_ios_file_render_corpus.rb
ruby scripts/test_portrait_engineering_corpus.rb
ruby scripts/test_portrait_review_plan_tools.rb
ruby scripts/test_blind_review_tools.rb
ruby scripts/check_device_evidence.rb --allow-incomplete
ruby scripts/test_device_evidence.rb
```

第一条只检查当前清单结构，第二条是完整门禁；在样片缺失时第二条必须失败。
匿名包构建、评分表字段和人像冻结门见[本地匿名图片评审工作流](blind-review-workflow.md)。
iOS 三档 Profile/Release 原始测量、产物回查和生命周期门见[物理设备性能与生命周期证据工作流](device-evidence-workflow.md)。
