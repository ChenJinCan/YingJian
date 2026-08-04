# 自然人像精修技术基础研究

> 日期：2026-08-04
>
> 状态：技术候选研究，不是供应商选择或实施决定
>
> 范围：Apple Vision/Core Image、Android ML Kit/MediaPipe，以及可用于纹理保护型轻度磨皮的经典图像算法
>
> 证据规则：仅引用平台官方文档、官方源码/模型卡和论文原文。没有公开证据的项目明确标为“未证”。

## 1. 结论摘要

1. **两端都有足够的人脸几何信息来构造保守的面部 ROI，但几何关键点不等于皮肤分割。** Vision 提供 2D 五官/轮廓关键点；Android 的 ML Kit Face Detection 提供关键点和轮廓，ML Kit Face Mesh 或 MediaPipe Face Landmarker 提供更稠密的 3D 网格。
2. **人物分割不能直接替代脸部皮肤分割。** Apple iOS 15 的人物分割与 ML Kit Selfie Segmentation 都主要返回“人物/背景”；它们适合限制人物与背景的效果，不足以保护眼、眉、唇、头发和衣物。
3. **Apple 没有公开一个能对任意导入照片生成 skin mask 的 Vision/Core Image API。** AVFoundation 的 skin/hair/teeth semantic matte 来自支持的相机捕获或照片中已经嵌入的辅助 matte，不能假定普通相册照片具备。
4. **MediaPipe Image Segmenter 的 SelfieMulticlass 能输出 `face-skin` 与 `body-skin` 类，是本轮一手资料中最接近通用皮肤 mask 的现成模型。** 但官方模型约 16.37 MB，Pixel 6 官方整管线平均延迟为 CPU 217.76 ms / GPU 71.24 ms；这只是候选，不证明达到映见的质量、包体或预览预算。
5. **边缘保持滤波可以成为可控的算法底座，但论文并不等于“自然磨皮已解决”。** 双边滤波、引导滤波和 Local Laplacian 都能保边平滑或操作细节；是否自然取决于皮肤 mask、尺度分解、五官/发际线保护、颜色空间、强度上限和样片盲评。
6. **当前不能写入供应商 ADR。** 应先做无生产依赖的技术 Spike，在冻结样片上比较至少一条系统 API 路线、一条 MediaPipe 皮肤解析路线和一条纯几何安全回退路线。

## 2. 能力对照

| 候选 | 已证输出 | 本地/离线边界 | 已知体积或性能 | 关键缺口 |
|---|---|---|---|---|
| Apple Vision 人脸关键点 | 脸部轮廓、眼眉、瞳孔、鼻、唇等 2D 区域 | 系统 framework 候选；API 页没有逐项网络行为承诺 | 内置模型体积与统一延迟未公开 | 不是皮肤 mask；额头、脸颊、瑕疵无语义输出 |
| Apple Vision 人物分割 | 单一人物 matte | iOS 15+ 系统 API；强“绝不联网”声明仍需离线/抓包验证 | 官方未给跨设备固定延迟、mask 尺寸或模型体积 | 人与背景，不区分脸部皮肤/头发/衣服 |
| Apple AVSemanticSegmentationMatte | 捕获型 hair/skin/teeth 等 matte | 设备端捕获能力；导入图仅能读取已有嵌入 matte | 支持类型依硬件/session 动态变化 | 不能为任意普通导入照片重新生成 skin matte |
| ML Kit Face Detection | box、角度、少量 landmarks、至多主要脸的 contours | bundled 立即可用；unbundled 首次需 Play Services 下载 | bundled 约 +6.9 MB；unbundled 约 +0.8 MB | contours 仅最显著人脸；不是稠密皮肤 mask |
| ML Kit Face Mesh | 最多 2 张脸，每脸 468 个 3D 点与三角形 | 仅 bundled | 约 +6.4 MB；官方称多数设备实时 | Beta；偏自拍场景、建议约 2 m 内；不输出 skin mask |
| ML Kit Selfie Segmentation | 每像素人物前景置信度 | bundled，静态链接 | 约 +4.5 MB；Pixel 4 约 25–65 ms | Beta；仅人物/背景，不是皮肤类别 |
| MediaPipe Face Landmarker | 每脸 478 个 3D landmarks，可选 52 blendshapes 和变换矩阵 | 模型可放 app assets；输入在设备处理，但官方仓库声明 Tasks 会发送性能/使用指标 | `latest` 官方模型实测 3,758,596 bytes；runtime 体积未证 | Preview；皮肤区域仍需自行构造；隐私与遥测开关需核对 |
| MediaPipe SelfieMulticlass | background、hair、body-skin、face-skin、clothes、accessories | 模型可随包分发并离线推理；Tasks 指标遥测边界同上 | 模型实测 16,371,837 bytes；Pixel 6 CPU 217.76 ms / GPU 71.24 ms | Preview；256×256 mask 的边缘与不同肤色自然度须项目样片验证 |

## 3. Apple 官方能力

### 3.1 Vision 人脸关键点

**来源**

- [`VNDetectFaceLandmarksRequest`](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- [`VNFaceLandmarks2D`](https://developer.apple.com/documentation/vision/vnfacelandmarks2d)
- [Detecting objects in still images](https://developer.apple.com/documentation/vision/detecting-objects-in-still-images)
- [`VNImageRequestHandler`](https://developer.apple.com/documentation/vision/vnimagerequesthandler)

**已证事实**

- `VNDetectFaceLandmarksRequest` 自 iOS 11 可用。未提供输入 face observations 时，请求会先检测人脸。
- 结果由 `VNFaceObservation.landmarks` 提供，区域包括 face contour、左右眼/眉/瞳孔、nose、nose crest、median line、outer/inner lips 等。
- landmark 坐标相对人脸 bounding box 归一化，Vision 图像坐标原点在左下。
- Apple SDK header 对 revision 1/2/3 记载 65 点，revision 3 可支持 76 点。应用不应据此假定跨系统完全相同的逐点数值。
- handler 可接收 URL、Data、CGImage、CIImage、CVPixelBuffer 或 CMSampleBuffer。对于本身不携带方向的表示，必须显式传入 orientation。

**未证/边界**

- 没有皮肤、脸颊、额头、斑点或痘印的语义 mask。
- 没有肤色类别、身份保持或跨 OS 坐标完全稳定的承诺。
- 可以据几何构造保守 face ROI，但这属于映见算法设计推断，不是 Apple 提供的皮肤真值。

### 3.2 Vision 人物与实例分割

**来源**

- [`VNGeneratePersonSegmentationRequest`](https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest)
- [Applying matte effects to people in images and video](https://developer.apple.com/documentation/vision/applying-matte-effects-to-people-in-images-and-video)
- [`VNGeneratePersonInstanceMaskRequest`](https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest)
- [`VNGenerateForegroundInstanceMaskRequest`](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest)
- [`VNInstanceMaskObservation.instanceMask`](https://developer.apple.com/documentation/vision/vninstancemaskobservation/instancemask)

**已证事实**

- `VNGeneratePersonSegmentationRequest` 自 iOS 15 可用，返回一个 `VNPixelBufferObservation` 人物 matte；多人属于同一个 person 类，不区分实例。
- quality level 有 `fast`、`balanced`、`accurate`；`accurate` 在 balanced 基础上做 matting refinement，并且是默认值。stateful 请求可利用前帧 mask 改善时序稳定。
- 可请求 OneComponent32Float、OneComponent16Half 或 OneComponent8 输出；默认 OneComponent8。查询设备支持输出格式的 API 到 iOS 18 才可用。
- `VNGeneratePersonInstanceMaskRequest` 与显著前景实例分割自 iOS 17 可用，能输出实例索引 mask；不适合作为 iOS 15–16 的主路径。
- instance mask 的 0 表示背景，其他值是实例索引；分析分辨率 mask 与原图尺度 mask 是不同输出路径。

**未证/边界**

- 人物 mask 不区分脸部皮肤、身体皮肤、头发、衣服和五官。
- 官方没有公布各 quality level 的固定 mask 尺寸、所有目标机型的 RAM/耗时/能耗或不同肤色质量指标。
- 实例分割也不是皮肤解析，只解决多人实例隔离。

### 3.3 Core Image 与捕获型 semantic matte

**来源**

- [Core Image](https://developer.apple.com/documentation/coreimage)
- [`CIBlendWithMask`](https://developer.apple.com/documentation/coreimage/ciblendwithmask)
- [`CIDetector`](https://developer.apple.com/documentation/coreimage/cidetector)
- [`CIImage.semanticSegmentationMatte`](https://developer.apple.com/documentation/coreimage/ciimage/semanticsegmentationmatte)
- [`CIImage.portraitEffectsMatte`](https://developer.apple.com/documentation/coreimage/ciimage/portraiteffectsmatte)
- [WWDC19: Advances in Camera Capture & Photo Segmentation](https://developer.apple.com/videos/play/wwdc2019/260/)
- [`AVCapturePhotoOutput.availableSemanticSegmentationMatteTypes`](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/availablesemanticsegmentationmattetypes)
- [`AVSemanticSegmentationMatte.MatteType`](https://developer.apple.com/documentation/avfoundation/avsemanticsegmentationmatte/mattetype-swift.struct)

**已证事实**

- Core Image 提供惰性滤镜和 mask 合成能力，`CIBlendWithMask` 可以把效果限制在外部提供的灰度 mask 内。
- 旧 `CIDetector`/`CIFaceFeature` 只提供 face bounds、眼/嘴中心等有限信息；Apple 指引在 iOS 11+ 使用 Vision。
- 支持的相机捕获管线可生成 hair、skin、teeth 等 semantic mattes；skin 值表示属于 skin 的比例。支持类型必须在运行时读取，并会随相机/format/session 改变。
- `CIImage` 能读取照片中已经存在的 portrait effects matte 或 semantic segmentation matte。

**未证/边界**

- Core Image 没有公开一个从任意普通 RGB 导入图重新推理生成人物/皮肤 mask 的现代 API。
- 捕获型 semantic matte 不能视为普通相册照片的通用能力；只有捕获时生成或文件已嵌入时才能消费。
- Apple API 文档没有给 Vision 内置模型的可提取权重、独立再分发许可或体积。使用受 Apple Developer/SDK 协议约束，不能据技术页写成“模型可自由商用再分发”。

## 4. Android 官方能力

### 4.1 ML Kit Face Detection

**来源**

- [Detect faces with ML Kit on Android](https://developers.google.com/ml-kit/vision/face-detection/android)
- [Face detection concepts](https://developers.google.com/ml-kit/vision/face-detection/concepts)
- [ML Kit model installation paths](https://developers.google.com/ml-kit/tips/installation-paths)

**已证事实**

- 可返回 bounding box、Euler Y/Z、可选 landmarks、contours、笑容/睁眼概率和 tracking ID。
- landmark 覆盖眼、耳、鼻、脸颊和嘴等稀疏位置；contour 输出 133 个 2D 点，但 contour 只对图中最显著的一张脸提供。
- bundled 依赖 `com.google.mlkit:face-detection`，模型随 app 静态链接，官方估算增加约 6.9 MB，首次即可用。
- unbundled 依赖 Play Services，app 增量约 0.8 MB；模型下载完成前请求不产生可用结果，并可能返回 `UNAVAILABLE`。
- 当前 Android 指南要求 API 23+。建议输入至少 480×360；一般检测脸约 100×100 像素，contour 建议脸约 200×200 像素。

**未证/边界**

- 稀疏 landmark 与单脸 contour 不足以直接生成人脸皮肤 mask。
- unbundled 路线不满足“首次、未下载过、完全离线也可立即使用”；可以用安装时下载改善，但仍不是随包离线保证。
- 官方没有给所有目标设备的固定延迟、RAM 峰值和对映见样片的检测率。

### 4.2 ML Kit Face Mesh

**来源**

- [Face mesh detection](https://developers.google.com/ml-kit/vision/face-mesh-detection)
- [Detect face mesh info on Android](https://developers.google.com/ml-kit/vision/face-mesh-detection/android)
- [Face mesh concepts](https://developers.google.com/ml-kit/vision/face-mesh-detection/concepts)

**已证事实**

- bundled-only SDK 约增加 6.4 MB，输出每脸 468 个 3D 点与三角形信息，mesh 模式最多两张脸。
- x/y 是图像像素坐标，z 是按图像大小缩放的相对深度；点 ID 0–467 对应固定网格位置。
- 官方定位为 selfie-like 输入，建议脸距设备约 2 m 内；最小图像建议 480×360。
- API 仍是 Beta，不受 SLA 或弃用政策保护，可能发生破坏性变更。

**未证/边界**

- mesh 是几何表面，不输出皮肤置信度、瑕疵或颜色类别。
- “多数设备实时”不能替代映见 API 24 低档机、2,048 px 预览和六图任务的 Profile/Release 实测。

### 4.3 ML Kit Selfie Segmentation

**来源**

- [Selfie segmentation with ML Kit on Android](https://developers.google.com/ml-kit/vision/selfie-segmentation/android)
- [Selfie segmentation model card](https://developers.google.com/static/ml-kit/images/vision/selfie-segmentation/selfie-model-card.pdf)

**已证事实**

- bundled-only，官方估算 app 下载增加约 4.5 MB；API 仍是 Beta。
- `SINGLE_IMAGE_MODE` 独立处理图片；`STREAM_MODE` 利用前帧使视频结果更平滑。
- 返回每像素人物前景置信度；默认缩放到输入尺寸，也可请求原始模型 mask（通常 256×256）。
- 官方报告 Pixel 4 上随输入大小约 25–65 ms；模型卡记载轻量模型约 249 KB、256×256 RGB 输入、人物/背景两类。
- 模型卡明确它可能不是 pixel-perfect；弱光、噪声、快速运动和大型遮挡会降低质量，多个不同尺度人物是 out of scope。
- 模型卡将该模型标为 Apache License 2.0，并给出按地域、感知肤色和性别分组的评估；这些数据针对人物分割 IoU，不证明脸部皮肤精修质量。

**未证/边界**

- 输出只有人物与背景，不识别 face-skin、body-skin、头发、衣服或五官。
- SDK 4.5 MB 增量与 249 KB 模型是不同口径，不得互换。

### 4.4 MediaPipe Face Landmarker

**来源**

- [Face landmark detection guide](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker)
- [Android implementation guide](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/android)
- [官方模型 bundle](https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task)
- [MediaPipe 官方仓库与 Privacy Notice](https://github.com/google-ai-edge/mediapipe)

**已证事实**

- 接受单图、视频和 live stream，输出每张脸 478 个 3D landmarks；可选输出 52 个 blendshapes 与 facial transformation matrix。
- Android 使用 `com.google.mediapipe:tasks-vision`，文档示例把模型放在 app `assets`，因此可将模型随包提供并在无模型下载时运行。
- IMAGE/VIDEO 调用会阻塞当前线程，官方要求在后台线程执行；LIVE_STREAM 异步并可能通过丢帧降低总体延迟。
- 2026-08-04 对官方 `latest` URL 实际读取为 3,758,596 bytes。`latest` 是可变 URL，此数值不是长期版本合同。
- MediaPipe 官方仓库为 Apache-2.0；仓库 Privacy Notice 表示 Tasks 输入在设备处理、不发送输入到 Google，但会发送 API 性能与使用指标。

**未证/边界**

- 文档处于 MediaPipe Solutions Preview；runtime AAR 的最终 app 增量、目标设备延迟、内存和遥测关闭/配置路径仍需单独核对。
- “输入不上传”不等于“完全无网络通信”。若映见要承诺网络静默，必须核对版本、配置、同意流程并离线/抓包验证。
- landmarks 仍不是 skin parsing。

### 4.5 MediaPipe Image Segmenter

**来源**

- [Image segmentation guide](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter)
- [Android implementation guide](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter/android)
- [SelfieMulticlass 官方模型](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite)
- [SelfieSegmenter 官方模型](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite)

**已证事实**

- 可输出 uint8 category mask 和/或每类 float32 confidence masks。
- SelfieMulticlass 的六类为 background、hair、body-skin、face-skin、clothes、others/accessories，输入为 256×256 float32。
- 官方 Pixel 6 整管线平均延迟：SelfieMulticlass CPU 217.76 ms、GPU 71.24 ms；二类 SelfieSegmenter CPU 33.46 ms、GPU 35.15 ms。
- 2026-08-04 从官方 `latest` URL 读取：SelfieMulticlass 16,371,837 bytes；方形二类 SelfieSegmenter 249,537 bytes；横版二类模型 250,177 bytes。这些是当前 artifact 字节数，不含 runtime 库且不是稳定版本承诺。
- Android 示例把模型放入 app assets，支持随包离线推理；任务仍受前述 Tasks 指标遥测边界影响。

**未证/边界**

- 256×256 face-skin mask 能否在发际线、眉眼、鼻翼、唇线、眼镜和遮挡处满足自然精修门，官方文档没有证明。
- 官方 benchmark 是 Pixel 6 平均值，不是映见低/中/高档矩阵的 p95，也没有包含 2,048 px 合成、mask refinement 和最终滤镜开销。
- 模型卡/页面没有为映见目标样片给出不同肤色、混合光、多人和侧脸的精修适用指标。

## 5. 经典边缘保持算法

### 5.1 双边滤波

**来源**

- C. Tomasi, R. Manduchi, [Bilateral Filtering for Gray and Color Images](https://users.cs.duke.edu/~tomasi/papers/tomasi/tomasiIccv98.pdf), ICCV 1998, DOI `10.1109/ICCV.1998.710815`。
- [OpenCV `bilateralFilter` 官方文档](https://docs.opencv.org/4.x/d4/d86/group__imgproc__filter.html)

**论文已证事实**

- 双边滤波按空间距离和光度/颜色相似度共同加权，是非迭代、局部、非线性的保边平滑方法。
- 原论文讨论在 CIE-Lab 感知距离下平滑颜色并保护边缘。

**对映见的含义（推断，未验证）**

- 可以作为皮肤区域低频平滑候选，但必须限定在可靠 mask 内，并保护眼眉、睫毛、鼻孔、唇、发际线等区域。
- 直接对 RGB 全脸做强双边滤波很可能产生塑料感、色块或 halo；论文没有声称能自动完成自然磨皮。
- 移动 GPU 实现、48 MP 导出复杂度、精度和参数范围必须另做 Spike。

### 5.2 引导滤波

**来源**

- K. He, J. Sun, X. Tang, [Guided Image Filtering](https://people.csail.mit.edu/kaiming/publications/pami12guidedfilter.pdf), IEEE TPAMI 2013, DOI `10.1109/TPAMI.2012.213`。
- [OpenCV `guidedFilter` 官方文档](https://docs.opencv.org/4.x/da/d17/group__ximgproc__filters.html)

**论文已证事实**

- 引导滤波基于局部线性模型，可将输入自身或另一张图作为 guidance。
- 它可作为保边平滑算子；论文给出与 kernel size、强度范围无关的精确线性时间算法，并讨论比双边滤波更好的边缘行为。

**对映见的含义（推断，未验证）**

- 可用于建立低频 base layer 或细化粗糙 skin confidence mask；高频 residual 可以按受控比例回加以保留纹理。
- 它仍不知道“什么是皮肤”和“什么是瑕疵”，不能独立解决肤色保护、多人和五官保护。

### 5.3 Local Laplacian Filters

**来源**

- S. Paris, S. W. Hasinoff, J. Kautz, [Local Laplacian Filters: Edge-aware Image Processing with a Laplacian Pyramid](https://jankautz.com/publications/LocalLaplacianFiltersSIG11_lowres.pdf), ACM SIGGRAPH 2011, DOI `10.1145/1964921.1964963`。
- M. Aubry et al., [Fast Local Laplacian Filters: Theory and Applications](https://imagine.enpc.fr/~aubrym/projects/llf/index.html), ACM TOG 2014。

**论文已证事实**

- Local Laplacian 使用 Laplacian pyramid 做局部、保边的色调与细节操作；后续论文分析了与各向异性扩散/双边滤波的关系并提出加速。

**对映见的含义（推断，未验证）**

- 它适合作为“控制皮肤细节幅度而不抹掉大边缘”的候选，但实现与参数化复杂度高于单一 blur。
- 论文没有提供人像自然度、移动端包体或本项目性能证明。

### 5.4 实现与许可边界

- OpenCV 与 `opencv_contrib` 官方仓库使用 Apache License 2.0；官方已有 bilateral/guided filter 实现可作算法对照。
- 这不构成引入 OpenCV 生产依赖的决定。最终 AAR/原生库体积、ABI、启动时间、iOS/Android 打包和许可 notice 成本均未评估。
- 论文可用于理解算法，但论文链接本身不是可复制实现的许可证，也不替代专利/商用法律审查。
- 自研 shader/Metal 实现若参考公式，也必须保留来源记录并做独立许可审查；本文件不提供法律结论。

## 6. 可验证的候选组合（不是选型）

### 路线 A：系统 API + 几何安全回退

- iOS：Vision landmarks + person matte（可用时）+ Core Image/Metal mask 合成。
- Android：bundled ML Kit Face Detection 或 Face Mesh + 人脸几何 ROI。
- 特点：不依赖第三方模型下载，包体相对可控；但 skin mask 需要启发式构造，额头/脸颊与遮挡边界风险最高。

### 路线 B：MediaPipe 皮肤解析

- Android 先以 SelfieMulticlass 产生 face-skin/body-skin confidence mask，再结合 face landmarks 排除眼眉唇与发际线。
- 特点：语义最接近需求；代价是约 16.37 MB 模型、Preview 生命周期、runtime/遥测边界和 256×256 边缘质量风险。
- iOS 是否共享同一模型与 runtime 不在本轮证据范围内，不能由 Android 文档外推。

### 路线 C：双层/多尺度滤波 Spike

- 仅对 skin confidence mask 内的低频层做克制平滑与色度均匀化。
- 高频 residual 受控回加；关键五官、头发、轮廓边缘使用 exclusion/protection mask。
- 候选算子分别测试 bilateral、guided filter 和 local Laplacian；不把某篇论文直接等同于产品算法。

以上组合都必须保留失败降级：无脸、多人不稳定、mask 置信度低、极端侧脸、遮挡或设备能力不足时，退回基础光色，不阻塞导出。

## 7. 技术 Spike 必须回答的问题

1. 在冻结人像样片上，脸、额头、脸颊、鼻翼、唇线、眉眼、发际线、眼镜和遮挡的 mask 边缘是否可接受？
2. 不同肤色、混合光、逆光、夜景和低清输入中，是否出现漂白、灰肤、色块、halo 或纹理消失？
3. 多人时是否能逐脸限制强度；无法可靠分脸时是否安全降级？
4. Preview 2,048 px 与原图 12–48 MP 导出的坐标、mask 和强度是否一致？
5. iOS 15–16、iOS 17+、Android API 24–28 与当前高端设备分别走什么 capability gate？
6. p50/p95 延迟、峰值附加内存、功耗/发热、包体增量是否满足现有质量基线？
7. MediaPipe Tasks 的指标遥测能否与映见“匿名诊断默认关闭、关闭后立即停止”的合同兼容？需要版本级源码/网络验证。
8. bundled 模型、framework、模型文件和 notices 的最终许可清单是什么？由谁完成法律确认？

## 8. 研究后仍未证的事项

- 没有任何候选已通过映见 48 张授权样片、盲评或目标物理设备矩阵。
- 没有证据证明任一平台系统 API 能直接提供通用、可靠的 face-skin mask。
- 没有确认 iOS/Android 最终使用同一算法、同一模型或同一参数能产生跨端一致结果。
- 没有确认任何候选在 2,048 px 实时预览、48 MP 导出和六图会话下满足性能/内存门。
- 没有确认 MediaPipe/ML Kit 的最终 app 增量、版本锁定、遥测配置与商店许可 notice。
- 没有完成商业人像 SDK 对照；本文件也不排除其作为独立候选。
- 没有供应商采用决定；任何引入生产依赖、模型或大型 framework 的动作仍需单独批准和 ADR。
