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
- 高清导出继续使用既有 Bitmap Adapter，但改为解析同一 `ImagePipelineV1`；分块/GPU 导出仍是后续门禁。

### iOS Adapter

- 高清导出改为解析同一 `ImagePipelineV1` 并继续使用 Core Image。
- 本轮没有实现 iOS 原生 Texture 预览，MethodChannel 不可用时走兼容预览；Metal/Core Image Texture Adapter 是下一阶段工作。

## 取舍

- 首个纵切只迁移当前三项调节，优先验证 seam、纹理生命周期和跨端参数一致性，不假装已经具备竞品画质。
- Android 选择 GLES3 作为基线，同时把后端藏在 Adapter 后；只有 Profile/Release 真机证据表明 GLES3 不满足目标时才引入 Vulkan。
- 现有 Android 高清导出仍会整图解码，不满足 48 MP 内存合同；它被明确保留为开发演示，不能因原生预览完成而宣称导出基座完成。

## 验证要求

- 单元测试锁定 `ImagePipelineV1` 序列化、MethodChannel 无字节合同和纹理元数据校验。
- Android 编译必须验证 GLES 源码与当前 Flutter Texture Registry 接口兼容。
- Android Profile 或 Release 真机验证：方向、首帧、连续滑杆、前后台、快速切图、内存与释放。
- 固定样片比较 Android GLES 预览、Android 导出和 iOS Core Image 导出的数值/视觉差异。
