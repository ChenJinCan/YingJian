# ADR 0002：版本化图像管线与原生预览基座

- 状态：Accepted
- 日期：2026-08-04
- 影响范围：编辑配方、Flutter/原生 seam、Android 预览、双端导出

## 背景

Flutter `ColorFilter.matrix` 可以验证页面和滑杆交互，但无法承载 LUT、曲线、局部遮罩、颗粒、辉光、人像保护和组图补偿。竞品 Android 包的静态证据也显示其图像能力位于原生 EGL/GLES、shader、LUT 和模型组合中；出现 Vulkan 或 OpenCL 字符串不代表某个运行时主路径。

## 决策

### 外部 seam

Flutter 业务层只认识版本化 `ImagePipelineV1` 和两个 Adapter Interface：

- `PhotoPreviewRenderer`：从应用自有原图路径创建纹理预览、更新配方、释放会话；
- `PhotoExporter`：从原图路径按同一配方语义执行高清导出。

通道只传文件路径、最大预览边长、版本化参数、纹理 ID 和状态，不传图片字节。`ImagePipelineV1` v1 固定 sRGB 工作空间、曝光 EV、对比和色温语义；后端未知版本或越界参数必须拒绝。

### Android Adapter

- 使用 Flutter `SurfaceProducer` 暴露 Texture；调用方不接触 Android Surface。
- 在独立线程创建 EGL context，使用 GLES3、纹理、FBO/窗口 surface 和 shader 绘制最长边不超过 2048 px 的代理图。
- 滑杆更新在 Dart 侧合并，同一时刻最多一个通道更新在途。
- 预览不可用时退回既有 Flutter 矩阵，只作为兼容路径，不作为正式图像引擎。
- 高清导出解析同一 `ImagePipelineV1`。API 28+ 使用单个可变 sRGB Bitmap 原位分块变换；API 24–27 使用 `BitmapRegionDecoder` 分块规范化 EXIF 方向到单个输出 Bitmap，避免源图与输出图同时完整驻留。最终仍须以 48 MP Profile/Release 物理设备数据关闭内存门。

### iOS Adapter

- 高清导出解析同一 `ImagePipelineV1` 并使用 Core Image。
- 原生预览通过 Core Image 与 `FlutterTexture` 提供，和导出共享参数语义；MethodChannel 或能力不可用时走兼容预览。

## 取舍

- 首个纵切只迁移当前三项调节，优先验证 seam、纹理生命周期和跨端参数一致性，不假装已经具备竞品画质。
- Android 选择 GLES3 作为基线，同时把后端藏在 Adapter 后；只有 Profile/Release 真机证据表明 GLES3 不满足目标时才引入 Vulkan。
- Android 高清导出仍需持有一个完整输出 Bitmap；分块方向解码消除了旧系统的双整图峰值，但没有物理设备 Profile/Release 证据前仍不能宣称 48 MP 导出基座完成。

## 验证要求

- 单元测试锁定 `ImagePipelineV1` 序列化、MethodChannel 无字节合同和纹理元数据校验。
- Android 编译必须验证 GLES 源码与当前 Flutter Texture Registry 接口兼容。
- Android Profile 或 Release 真机验证：方向、首帧、连续滑杆、前后台、快速切图、内存与释放。
- 固定样片比较 Android GLES 预览、Android 导出和 iOS Core Image 导出的数值/视觉差异。
