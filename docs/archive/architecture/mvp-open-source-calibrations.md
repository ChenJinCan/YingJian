# MVP 开源算法标定

本文件固定 MVP 已进入生产执行链的开源算法来源、参数语义和安全边界。它不是候选对比报告；后续 AI 生成配方时只需要使用映见的语义参数，不得直接控制 shader 常量。

## 已采用的标定

| 映见参数 | 上游快照 | 采用内容 | 映见执行边界 |
|---|---|---|---|
| 质感磨皮 | GPUPixel `fd596da4d50bc8035c32f0b400af70536dc59e4f` | blur radius `4.0`、difference delta `7.07`、theta `0.1`、默认强度 `0.5` | 只在 Vision 有效人脸蒙版内执行，五官、眉发和嘴唇保护区继续生效 |
| 肤色与面部光线 | CainCamera `8d1270e2a4d1e0e69940cf806c5c4ae39615eb66` | `levelBlack=0.01960784`、`levelRangeInv=1.040816`、默认强度 `0.5` | 在 gamma 编码 sRGB 内执行 level 标定；使用有界中间调提亮代替上游未随代码独立授权的 LUT |
| 瘦脸、下颌、下巴、大眼 | CainCamera 同一快照 | 上脸位移 `0.05`、下颌位移 `0.12`、下巴 `0.08`、大眼 `0.12`，径向平方衰减 | 复用 Vision 人脸与特征点，不引入 Face++；每张脸独立配方并受人脸蒙版限制 |
| 小头、鼻形、嘴形、增高、肩、腰、腿 | Harbeth `88270fca0d98132d24282341eff2e129e7abb8a0` 与 CainCamera | 采用局部 bulge/pinch 的径向平方衰减；保留映见现有克制强度上限 | Core Image 负责插值；身体形变继续受 Pose 区域和 person mask 约束，不形变背景 |
| 整体光色与画质 | 映见现有参数合同与 Core Image | 曝光、高光、阴影、对比度、色温、色调、饱和度、清晰度，以及去噪、暗光、去灰、锐化 | 三套本地推荐只写入这些可序列化参数；不增加隐藏效果或云端任务 |

## 参数合同

- 一键自然美化固定写入：质感磨皮 `50`、肤色与面部光线 `50`、瑕疵减弱 `20`。
- 一键自然美化不得写入任何脸型或身体几何参数。
- 所有几何参数默认 `0`；只有用户显式操作或未来 AI 明确生成几何配方时才改变。
- UI 百分比是稳定的产品语义；原生内部常量可以随引擎版本升级，但必须同步更新回归测试和 `effectVersion`。
- `0` 必须严格无效果；预览和高清导出必须重放同一个版本化配方。
- 上游没有提供成熟移动端语义瘦身实现。身体能力继续采用映见既有的 `Pose + person mask + 多区域局部 flow`，仅吸收公开局部 warp 的连续衰减，不引入 Python 模型或新运行时。

## 上游源码

- [GPUPixel beauty face unit filter](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/beauty_face_unit_filter.cc)（Apache-2.0）
- [GPUPixel box difference filter](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/box_difference_filter.cc)（Apache-2.0）
- [CainCamera face reshape shader](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/face/fragment_face_reshape.glsl)（Apache-2.0）
- [CainCamera complexion shader](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/beauty/fragment_beauty_complexion.glsl)（Apache-2.0）
- [Harbeth bulge shader](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Distortion%20%26%20Warp/C7Bulge.metal)（MIT）
