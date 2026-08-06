# iOS 人像核心候选技术基线

> 日期：2026-08-06。范围：Tickets 17/18 的离线 Spike；本文件不批准生产依赖，也不宣称画质通过。

## 结论

首轮 Spike 固定三个可比较候选，但共用同一输入、同一 Vision 人脸几何和同一最终成片评分：

1. **Apple 系统候选**：Vision 多脸检测/landmark，加 Core Image `CINoiseReduction` 与蒙版合成。
2. **映见自建候选**：Vision 几何只作输入，自建逐脸资格、五官保护、低频肤色和局部修复逻辑；完整图像始终留在原生边界。
3. **OpenCV 开源候选**：同一逐脸蒙版后比较 `bilateralFilter`；瑕疵候选只在保守检测蒙版存在时比较 `inpaint`。Spike 可在隔离工具中使用，但在二进制体积、iOS 构建和固定样片质量过门前不进入应用依赖。

这三类算法都不能仅凭“检测到了脸”或“能修复蒙版”区分痘印和痣、雀斑、皱纹、胡须等身份细节。检测、保护和最终修复必须分别 fail closed；OpenCV 不替代语义判断。

## 一手来源事实

- Apple 的 `VNDetectFaceLandmarksRequest` 默认先定位输入中的全部人脸，也支持把预先筛选的 `VNFaceObservation` 数组作为输入，因此可以逐脸关闭低置信度对象，而不必关闭其他合格脸。[Apple VNDetectFaceLandmarksRequest](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- `VNFaceObservation` 提供 confidence、bounding box、landmarks 以及 roll/yaw/pitch 等几何信息；这些是逐脸资格和五官保护输入，不是皮肤语义标签。[Apple VNFaceObservation](https://developer.apple.com/documentation/vision/vnfaceobservation)
- Core Image 的 `CINoiseReduction` 只暴露 noise level 与 sharpness，属于降噪/边缘锐化滤镜；它没有“皮肤”“痘印”或“身份细节”合同。[Apple CINoiseReduction](https://developer.apple.com/documentation/coreimage/cinoisereduction)
- OpenCV `bilateralFilter` 是保持边缘的非线性滤波，但上游文档也提示大参数会产生卡通化，并且计算较慢；它只能作为蒙版后的滤波候选。[OpenCV image filtering](https://docs.opencv.org/master/d4/d86/group__imgproc__filter.html)
- OpenCV `inpaint` 根据蒙版边界邻域重建被选区域；输入蒙版本身必须由映见的保守候选判定产生，因此不能把 inpaint 成功当成瑕疵分类成功。[OpenCV inpainting](https://docs.opencv.org/4.11.0/d7/d8b/group__photo__inpaint.html)
- OpenCV 主仓库声明 Apache-2.0；采用时仍需冻结精确版本、NOTICE、实际链接内容和最终 App Store 合规检查。[OpenCV upstream repository](https://github.com/opencv/opencv)

## Spike 决策

| 问题 | 固定决定 |
|---|---|
| 多脸上限 | 检出总数 1–3 时逐脸判定；4+ 全部关闭非几何人像，基础编辑/导出继续 |
| 单脸失败 | 只从有效蒙版剔除该脸；其他合格脸继续，不向 Flutter 返回点或蒙版 |
| 多脸处理 | 每张脸独立候选区与保护区，合并后只做一次原图渲染 |
| 无法保护 | 对应脸或对应瑕疵能力关闭，不能退化为全脸模糊 |
| 开源候选 | 只在 Spike 工具中验证；不得因 Apache-2.0 就自动进入生产 |
| 通过证据 | 固定成片裁剪、保护子集和匿名评分；检测框、蒙版和像素差只作诊断 |

## 尚未证明

- 当前仓库没有 OpenCV 生产依赖，也没有可复用的 iOS OpenCV 构建产物。
- 现有四张 `portrait_multi` 是许可清晰的工程合成图，可用于接缝和负向检查，但不能单独覆盖真实遮挡、妆容、胡须和复杂混合大小脸的正式质量冻结。
- OpenCV、Apple 系统候选或自建候选尚未在相同裁剪上完成最终成片盲评；这正是 Tickets 17/18 的剩余输出，而不是本研究文档的结论。
