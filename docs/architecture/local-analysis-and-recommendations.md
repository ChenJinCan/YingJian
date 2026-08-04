# 本地分析与三推荐基座

## 当前产品行为

导入 1–6 张照片后，项目进入 `analyzing`。应用逐张执行供应商无关的 `PhotoAnalyzer`，把每张状态稳定落为 `ready` 或 `fallback`，全部结束后才进入 `choosingRecommendation`。单项异常被隔离并转为安全回退，不阻断其他照片。

当前生产实现是 `MetadataSafePhotoAnalyzer`。它只绑定内容 SHA-256、方向、尺寸、色彩空间、分析版本和能力版本，不读取或上传像素，也不从文件名、路径或元数据猜测曝光、人物和场景。由于像素分析候选尚未通过质量门，它明确返回 `safeFallback`，界面也明确说明正在使用克制的安全配方。

这不是像素分析完成的证据。接入原生分析器后，只有固定样片正确性、隐私、失败语义和物理设备性能门通过，才可返回 `ready`。

## 配方目录

`MvpRecipeCatalog` 固定为版本化的 12 套配方，覆盖：

- 自然干净；
- 氛围色彩；
- 质感风格。

目录只包含 `EditRecipe` 已声明的有界参数，没有脚本、动态 Shader、自由提示或云端任务。目录校验要求 12–18 个唯一 ID 和三个产品家族。人像处理强度不在当前目录中；Ticket 03 冻结前不得通过推荐入口开放。

`LocalRecommendationEngine` 对同一照片身份、分析结果和目录版本始终返回同样的三套不同家族方案。安全回退时只选择 `safeForFallback` 配方，把共享强度限制为 `0.72`，每张补偿标记为 `safeFallbackV1`。分析结果可靠后，曝光和白平衡补偿仍保持在显式小范围内。

## 移动端交互

工作台保留当前照片和组内位置，在工具区之前显示横向三卡选择：点击卡片预览，确认后一次性保存 `selectedRecommendationId`、`SharedStyle` 和每张 `AdaptiveCompensation`，然后进入 `editing`。三卡均标注“本地效果”，没有账号、上传或云端生成前置步骤。

应用被终止在 `analyzing` 时，可从每张持久化状态重新执行；终止在 `choosingRecommendation` 时，根据只读照片身份确定性重建三卡。选择结果进入既有项目 JSON，重启后直接恢复编辑。

## 仍未验证

- 像素级清晰度、曝光、白平衡、有限场景和人物适用性；
- 48 张授权样片上的危险强度削弱；
- 三方向固定样片预览质量与真人“更省事”指标；
- iOS/Android Profile/Release 物理设备分析性能。

因此当前状态是：三推荐与安全回退 `implemented`，像素分析和质量证据 `validation incomplete`。
