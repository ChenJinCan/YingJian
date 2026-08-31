# GitHub 开源修图、美颜与形变项目调研

> 调研日期：2026-08-11。只采用项目官方仓库、源码、README、LICENSE 和模型说明。
> 本文按“源码是否值得映见直接阅读、抽取算法或模仿交互”分级；许可证不作为淘汰条件，但会明确标注。

## 结论

有可以直接读、直接做样片对照的源码，但没有发现一个同时把“高质量磨皮、五官美化、瘦脸、瘦身、
人体保护、Flutter/iOS 成品编辑器”全部做好且源码与模型都完整的项目。

最值得优先看的组合是：

1. **GPUPixel**：现成磨皮、美白、瘦脸、大眼、口红和腮红，瘦脸 shader 最接近映见可直接吸收的实现；
2. **CainCamera**：完整 Android 美颜相机范本，脸型 shader 的参数和点位比 GPUPixel 更丰富；
3. **FlowBasedBodyReshaping**：研究级人体瘦身完整源码，展示“姿态条件 → 稠密 flow → 可控 warp”的整条路径；
4. **Harbeth**：Metal 版双边/表面模糊与 bulge/pinch 局部形变，适合作为 iOS 对照实现；
5. **MediaPipe 或映见现有 Vision**：给形变提供人脸/人体关键点；
6. **MODNet / face-parsing**：给身体轮廓、皮肤、眼唇等区域提供保护蒙版；
7. **ImageToolbox、RapidRAW**：只读完整编辑器的任务编排、蒙版、历史与批处理组织。

映见当前已经有 `Vision + Core Image/Metal + IOSPortraitRetoucher`，因此最合理的用法不是先换整套引擎，
而是把下面的具体算法逐项做固定样片 A/B；胜出的局部实现再放进现有供应商无关边界。

## A 级：最值得直接读源码、做 A/B

### 1. GPUPixel：磨皮与瘦脸最完整

- 仓库：[pixpark/gpupixel](https://github.com/pixpark/gpupixel)，Apache-2.0；调研快照
  `fd596da4d50bc8035c32f0b400af70536dc59e4f`。
- 技术形态：C++11 + OpenGL/OpenGL ES，官方列出 iOS、Android、macOS、Windows、Linux；没有 Flutter 包，
  iOS 需要 framework/C++ 桥接。官方入口：[集成文档](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/docs/docs/en/guide/integrated.md)。
- 明确具备：磨皮、美白、瘦脸、大眼、口红、腮红；能力和参数见
  [beauty effects](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/docs/docs/en/call/beauty_effects.md)。

最值得读的文件：

- [磨皮主滤镜 `beauty_face_unit_filter.cc`](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/beauty_face_unit_filter.cc)：
  shader、磨皮强度、美白和锐化如何合成；这是第一优先样片对照对象。
- [磨皮组合 `beauty_face_filter.cc`](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/beauty_face_filter.cc)：
  高反差、模糊、锐化和美白各 pass 的组织方式。
- [瘦脸/大眼 `face_reshape_filter.cc`](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/face_reshape_filter.cc)：
  直接包含 GLSL。它接收 106 点人脸坐标，以 9 组“脸轮廓点 → 内部目标点”执行局部 `curveWarp`，
  并用双眼中心和半径做径向放大。映见不应照抄点号，而应把 Vision/MediaPipe 点映射到同一几何语义。
- [彩妆基类 `face_makeup_filter.cc`](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/src/filter/face_makeup_filter.cc)：
  面部关键点与彩妆纹理组合方式，可用于口红/腮红的区域合同参考。

需要注意：仓库整体声明 Apache-2.0，但 `third_party/mars-face-kit` 内是预编译 `.a/.so` 和
`face_det.mars_model`、`face_align.mars_model`，该目录在所审快照中没有单独 LICENSE、NOTICE 或模型卡。
这不妨碍阅读开源滤镜和 shader，但说明“源码完整”只适用于滤镜/形变层，**不适用于内置检测模型**。
[目录证据](https://github.com/pixpark/gpupixel/tree/fd596da4d50bc8035c32f0b400af70536dc59e4f/third_party/mars-face-kit)、
[根许可证](https://github.com/pixpark/gpupixel/blob/fd596da4d50bc8035c32f0b400af70536dc59e4f/LICENSE)。

### 2. CainCamera：完整美颜相机源码范本

- 仓库：[CainKernel/CainCamera](https://github.com/CainKernel/CainCamera)，根 README 声明 Apache-2.0；
  调研快照 `8d1270e2a4d1e0e69940cf806c5c4ae39615eb66`，最后提交为 2021-10-01，已经明显老旧。
- 技术形态：Android/Java + OpenGL ES，包含相机预览、实时美颜、动态滤镜/贴纸、拍照与短视频、瘦脸大眼、
  亮眼美牙和彩妆流程，是本轮最完整的“美颜相机怎么串起来”源码范本。
- 最值得读的 [脸型 shader](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/face/fragment_face_reshape.glsl)
  不只提供单一瘦脸：包含 face lift、face shave、face narrow、下巴、额头、大眼、眼距、眼角、鼻翼、鼻长、
  嘴形和微笑等点位形变函数。它比 GPUPixel 更适合建立映见“语义参数 → 控制点与 warp”的完整映射表。
- 磨皮链从 [blur](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/beauty/fragment_beauty_blur.glsl)、
  [high-pass](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/beauty/fragment_beauty_highpass.glsl)、
  [beauty face 合成](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/beauty/fragment_beauty_face.glsl)
  到 [肤色/美白](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/assets/shader/beauty/fragment_beauty_complexion.glsl)，
  很适合逐 pass 对照映见现有纹理保留和肤色处理。
- 参数总表见 [BeautyParam.java](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/java/com/cgfay/filter/glfilter/beauty/bean/BeautyParam.java)，
  单滤镜包装见 [`GLImageFaceReshapeFilter.java`](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/filterlibrary/src/main/java/com/cgfay/filter/glfilter/face/GLImageFaceReshapeFilter.java)，
  实时预览编排见 [`RenderManager.java`](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/cameralibrary/src/main/java/com/cgfay/camera/render/RenderManager.java)。

边界：这是学习项目，不是现代 iOS/Flutter 依赖；官方 README 明说人脸关键点使用 Face++ 试用 SDK，短视频部分仍有 bug，
图片编辑也未完整实现。因此最适合读 shader、参数合同和实时链路，不适合整包移植。
[官方说明](https://github.com/CainKernel/CainCamera/blob/8d1270e2a4d1e0e69940cf806c5c4ae39615eb66/README.md)。

### 3. Harbeth：Metal 滤镜与局部形变对照

- 仓库：[yangKJ/Harbeth](https://github.com/yangKJ/Harbeth)，MIT；调研快照
  `88270fca0d98132d24282341eff2e129e7abb8a0`。
- 技术形态：Swift + Metal/Core Image/MPS，支持 SPM/CocoaPods 和 iOS；无检测器、无模型权重。
- 适合读取：Metal 管线、双边/表面模糊、局部 bulge/pinch、滤镜链和纹理池。

具体源码入口：

- [美颜组合 Metal shader](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Combination/C7CombinationBeautiful.metal)
  与 [Swift 组合器](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Combination/C7CombinationBeautiful.swift)：
  实际实现是双边模糊 + Sobel 边缘 + 简单肤色阈值 + tone curve，并非人脸语义级精修。
- [双边模糊](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Blur%20Effects/C7BilateralBlur.metal)
  和 [表面模糊](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Blur%20Effects/C7SurfaceBlur.metal)：
  可直接作为映见现有纹理平滑实现的 GPU 对照。
- [Pinch](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Distortion%20%26%20Warp/C7Pinch.metal)
  和 [Bulge](https://github.com/yangKJ/Harbeth/blob/88270fca0d98132d24282341eff2e129e7abb8a0/Sources/Compute/Distortion%20%26%20Warp/C7Bulge.metal)：
  是可读性很高的局部径向形变，可用于腰、肩、腿、眼睛的原理验证。

质量警告：所审 shader 用整数坐标 `texture.read` 取样，局部形变没有双线性采样、语义边界、背景直线保护或人体网格，
不能直接等同于高质量瘦身。README 提到的 `C7HighPassSkinSmoothing` 和
`C7CombinationSkinSmoothing` 在所审源码树中没有找到对应实现；因此以源码为准，不把 README 的“频率分离磨皮”视为已交付能力。

### 4. FlowBasedBodyReshaping：真正针对人体瘦身的完整研究源码

- 仓库：[JianqiangRen/FlowBasedBodyReshaping](https://github.com/JianqiangRen/FlowBasedBodyReshaping)，
  CVPR 2022 `Structure-Aware Flow Generation for Human Body Reshaping` 官方实现。
- 它不是单点 `pinch`：网络以照片和人体骨架为条件预测整幅二维稠密 flow，再按 `degree` 缩放形变强度并重采样原图；
  仓库提供推理代码、网络结构、姿态估计器、warp、样例和预训练模型下载。
- 关键入口：
  [`network/flow_generator.py`](https://github.com/JianqiangRen/FlowBasedBodyReshaping/blob/main/network/flow_generator.py)
  展示 flow 生成和 `grid_sample`；
  [`reshape_base_algos/body_retoucher.py`](https://github.com/JianqiangRen/FlowBasedBodyReshaping/blob/main/reshape_base_algos/body_retoucher.py)
  展示姿态、flow、强度与最终 warp 的编排；
  [`reshape_base_algos/image_warp.py`](https://github.com/JianqiangRen/FlowBasedBodyReshaping/blob/main/reshape_base_algos/image_warp.py)
  是最终图像重映射。

它是最值得参考的“自动瘦身”算法上限，但不是手机端即插即用实现：Python/PyTorch、示例只处理单人且模型需另下。
即使不采用网络，也值得吸收两个设计：形变输出统一为可缩放的稠密 flow；姿态结构进入形变预测，而不是仅靠一个腰部圆形 pinch。

## B 级：作为形变定位和保护层

### 5. MediaPipe：密集人脸与人体锚点

- 仓库：[google-ai-edge/mediapipe](https://github.com/google-ai-edge/mediapipe)，Apache-2.0，持续维护。
  它不会磨皮、瘦脸或瘦身；价值是为映见自己的 Metal/Core Image 形变提供更密集、跨 iOS/Android 一致的定位合同。
- [Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker) 每张脸输出
  478 个归一化 3D landmark，并可选输出 52 个表情 blendshape 和人脸变换矩阵。`numFaces` 可大于 1，
  但官方明确只有 `numFaces == 1` 时才应用 landmark smoothing。因此它对下颌线、脸颊、眼唇和额头的控制点
  比 Vision 的区域式 landmark 更有研究价值，多脸视频稳定性则不能按单脸效果推断。
- [Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker) 每个人输出
  33 个 3D 人体点，同时给出图像归一化坐标和 world coordinates，可选输出人体分割 mask；`numPoses` 支持多人。
  肩、髋、膝、踝等语义锚点很适合建立瘦腰、窄肩、长腿的区域合同，但它本身不产生安全形变，也不保护背景直线。
- [Image Segmenter](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter) 可输出 `uint8`
  category mask 或逐类 `float32` confidence mask。官方模型既有 person/background，也有 hair、body-skin、face-skin、
  clothes、accessories 六类的 SelfieMulticlass；后者比 Vision 的单一 person matte 更适合做磨皮和形变保护层，
  但它是类别分割，不是多人物实例身份合同。
- iOS 通过 [CocoaPods `MediaPipeTasksVision`](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios)
  接入，模型文件由 App 自行打包，可直接接受 `UIImage`、`CVPixelBuffer` 或 `CMSampleBuffer`，支持 image、video、
  live-stream 三种模式；没有官方 Flutter 美颜组件，仍需映见自己的原生桥和序列化结果 DTO。视频/直播会用 tracking
  避免每帧重跑检测，直播结果异步回调；静态图和视频调用会阻塞调用线程，必须放到后台队列。
- 官方下载包当前约为：Face Landmarker 3.6 MB；Pose Lite/Full/Heavy 约 5.5/9.0/29.2 MB；
  Selfie Segmenter 约 0.24 MB，SelfieMulticlass 约 15.6 MB。这里只是模型文件，不含 `MediaPipeTasksVision`
  运行时和符号开销。官方公开的 Image Segmenter 延迟仅是 Pixel 6：Selfie square CPU/GPU 约 33/35 ms，
  SelfieMulticlass 约 218/71 ms；没有可直接套用到映见 iOS 真机的官方数字，因此包体、峰值内存和延迟必须实测。
- 隐私不是自动满足：MediaPipe [官方仓库当前隐私说明](https://github.com/google-ai-edge/mediapipe#privacy-notice)
  称输入图片留在设备上，但 MediaPipe Tasks 会向 Google 发送 API 性能和使用指标，并要求开发者按适用法律取得用户知情同意。
  这与映见“匿名诊断默认关闭，关闭后立即停止”的合同存在直接冲突；在确认可审计的关闭机制和网络行为前，不能进入生产依赖。

**对映见的结论：参考价值高，当前不替换 Vision。** 映见现有 `IOSPortraitRetoucher` 已经使用
`VNDetectFaceLandmarksRequest`、`VNDetectHumanBodyPoseRequest` 和 `VNGeneratePersonSegmentationRequest`，并已贯通
逐目标选择、背景保护、局部形变和预览/导出链路。MediaPipe 只有在同一固定样片上证明以下至少一项明显胜出时才值得引入：

1. 478 点 mesh 明显改善侧脸、下颌、额头、眼唇和遮挡场景的几何稳定性；
2. iOS/Android 共用点位语义显著降低双端配方漂移；
3. SelfieMulticlass 的 face-skin/body-skin/clothes mask 明显减少磨皮误伤和背景形变；
4. 多脸、多人体固定样片的漏检、错绑和抖动，在可接受包体、内存、Profile/Release 真机延迟内优于 Vision。

建议只做隔离 spike：MediaPipe 仅输出标准化 landmark/mask DTO，与现有 Vision DTO 一起喂给同一个形变渲染器，
不同时替换检测、渲染和编辑状态。若 A/B 没有质量级提升，继续使用系统 Vision 可避免新增运行时、模型包体、
CocoaPods/Flutter 桥接和指标同意负担。

### 6. MODNet：身体轮廓和背景保护

- 仓库：[ZHKKKe/MODNet](https://github.com/ZHKKKe/MODNet)，Apache-2.0；仓库明确说明代码、模型和 demo
  （除展示 GIF）均按 Apache-2.0 发布。
- 最值得读：[网络结构 `src/models/modnet.py`](https://github.com/ZHKKKe/MODNet/blob/28165a451e4610c9d77cfdf925a94610bb2810fb/src/models/modnet.py)、
  [图像推理 demo](https://github.com/ZHKKKe/MODNet/tree/28165a451e4610c9d77cfdf925a94610bb2810fb/demo/image_matting)。
- 能力是 RGB 输入的人像 alpha matte，不是皮肤分区，也不会瘦身。它适合在身体形变时识别人像/背景边界，
  对背景直线和其他人实施保护。
- 研究模型、ONNX/TorchScript 转换代码和下载入口都存在，但官方 README 同时说明线上使用的 7 MB 更好模型并未发布；
  因此开源仓库并不包含其最佳效果版本。

### 7. face-parsing：皮肤、眼唇和头发保护

- 仓库：[yakhyo/face-parsing](https://github.com/yakhyo/face-parsing)，MIT；提供 BiSeNet、训练、PyTorch 推理、
  ONNX 导出和预训练权重下载。
- 具体入口：[BiSeNet](https://github.com/yakhyo/face-parsing/blob/8a4729d95118d0e97c44185f9bdef3d6bfeaaf99/models/bisenet.py)、
  [ONNX 导出](https://github.com/yakhyo/face-parsing/blob/8a4729d95118d0e97c44185f9bdef3d6bfeaaf99/onnx_export.py)、
  [ONNX 推理](https://github.com/yakhyo/face-parsing/blob/8a4729d95118d0e97c44185f9bdef3d6bfeaaf99/onnx_inference.py)。
- 它把脸拆成皮肤、头发、眼睛、嘴唇等区域，适合建立“磨皮只作用皮肤、眼唇眉发必须保护”的蒙版合同；
  但 43–82 MB 级研究权重和 Python/ONNX 不是 iOS 即插即用，需要另做 Core ML/LiteRT 体积与延迟验证。

### 8. opencv-mobile：消除、重映射和 CPU 参考

- 仓库：[nihui/opencv-mobile](https://github.com/nihui/opencv-mobile)，Apache-2.0，活跃维护，提供精简移动端预编译 OpenCV。
- 适合拿 `remap`/warp、mask、morphology、inpaint 做祛痘/消除笔、蒙版羽化和 CPU 黄金参考；
  它没有现成人脸美颜、瘦脸或瘦身语义。
- 对映见的意义是小工具层或测试 oracle，不是替换现有渲染管线。

## C 级：完整编辑 App / UI 参考

### ImageToolbox

- [T8RIN/ImageToolbox](https://github.com/T8RIN/ImageToolbox)，Apache-2.0，Android/Kotlin/Compose，持续高频维护。
- 是本轮看到的功能最完整开源移动编辑 App：批处理、滤镜链、裁剪、绘制、背景移除、格式/EXIF、压缩等。
- 值得读其模块化滤镜合同、预览生成、长任务状态、批量保存和大量参数 UI；不适合把 Compose UI 直接搬进 Flutter。
  入口可从 [源码树](https://github.com/T8RIN/ImageToolbox/tree/cfe3733de9f602bf901f2725d15d6f10ad26f61b)
  的 `core/filters`、`core/domain` 和各 feature 模块开始。
- 它不是人像美颜/瘦身 App，价值主要在完整编辑器工程组织。

### RapidRAW、darktable、RawTherapee

- [RapidRAW](https://github.com/CyberTimon/RapidRAW) 是 AGPL-3.0；前一份调研已确认它适合参考预览 backpressure、
  蒙版与几何一致性、组合蒙版和批量导出，不适合照搬桌面架构。
- [darktable](https://github.com/darktable-org/darktable) 与
  [RawTherapee](https://github.com/RawTherapee/RawTherapee) 是 GPL-3.0 桌面 RAW 编辑器。
  它们值得研究颜色管理、局部蒙版、历史栈、导出和非破坏流水线，但不是美颜/瘦身实现，也不适合移动端直接移植。
- 许可证在这里不是阅读障碍；如果复制、改写或分发源码，应单独处理相应开源义务。

## D 级：暂不作为映见主线

- **GPUImage3 / MetalPetal / BBMetalImage**：都有可读的 GPU 滤镜框架，但没有比 GPUPixel 更完整的语义美颜与瘦脸；
  MetalPetal 很适合从零搭 Metal graph，映见已有原生管线时迁移收益不清楚。BBMetalImage 最后源码更新明显偏旧。
- **BeautyGAN、PSGAN、PIRenderer、GFPGAN、Real-ESRGAN 等研究模型**：分别偏彩妆迁移、生成、表情驱动、
  人脸修复或超分，不是可归零、可解释的基础修图参数；常见问题是 CUDA/Python、权重另下、训练数据或权重条款独立、身份漂移。
- **FireRed-Image-Edit、Step1X-Edit 等生成式编辑**：源码和权重可研究，但官方运行配置仍是服务器级 GPU，
  不能替代映见本地、确定性、可撤销的磨皮与形变路径。

## 关于“瘦身”的真实结论

本轮没有找到一个质量和完整度接近 GPUPixel 瘦脸、可在移动端即插即用的成熟瘦身库；但找到了
`FlowBasedBodyReshaping` 这套完整研究实现，可以直接研究自动瘦身的稠密 flow 路线。移动端可落地的拼装方式是：

1. 用 Vision 或 MediaPipe Pose 取得肩、髋、膝等人体锚点；
2. 用 MODNet/人像分割得到人物轮廓与背景保护区；
3. 用 Harbeth 的 pinch/bulge 作为最小原理样例，但在映见中改为多控制点、连续衰减、双线性采样；
4. 对人体轮廓外的直线、其他人和高频背景提高保护权重；
5. 通过“原图线条形变、肢体比例、边缘断裂、多人误伤、预览/导出一致性”固定样片门禁验证。

研究代码给出了自动稠密 flow 的完整范式，移动端代码给出了局部 warp 的基本零件；但高质量移动瘦身的目标选择、
轻量化、多人处理、背景保护和质量门，仍需要映见自己完成。

## 建议的最小实施顺序

1. 冻结现有样片与参数，先把 GPUPixel `beauty_face_unit_filter` 和 `face_reshape_filter` 做成离线或隔离 spike；
2. 将 GPUPixel 的瘦脸点对改成映见的语义点对，而不是引入其 `mars-face-kit`；
3. 用 Harbeth 双边/表面模糊与映见现有平滑做盲评，拒绝只凭 README 选择；
4. 身体形变同时做两条离线对照：`Pose + person mask + 局部 warp`，以及 `FlowBasedBodyReshaping` 的稠密 flow 输出，
   重点观察背景线条和多人误伤；
5. 只有样片、Profile/Release 真机延迟、峰值内存和预览/导出同义性均胜出，才考虑把实现纳入生产边界。

本文不是法律意见。所有源码模仿、复制、二进制分发和模型打包仍应保留上游许可证与来源记录。
