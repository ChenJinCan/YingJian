# ADR 0002：版本化图像管线与原生预览基座

- 状态：Accepted
- 日期：2026-08-04
- 影响范围：编辑配方、Flutter/原生 seam、Android 预览、双端导出

## 背景

Flutter `ColorFilter.matrix` 可以验证页面和滑杆交互，但无法承载 LUT、曲线、局部遮罩、颗粒、辉光、人像保护和组图补偿。竞品 Android 包的静态证据也显示其图像能力位于原生 EGL/GLES、shader、LUT 和模型组合中；出现 Vulkan 或 OpenCL 字符串不代表某个运行时主路径。

## 决策

### 外部 seam

Flutter 业务层只认识版本化 `ImagePipelineV1`/`ImagePipelineV2` 和两个 Adapter Interface：

- `PhotoPreviewRenderer`：从应用自有原图路径创建纹理预览、更新配方、释放会话；
- `PhotoExporter`：从原图路径按同一配方语义执行高清导出。

后续生产版本按追加语义演进：历史版本依次加入人像、多人目标、画质、滤镜/HSL、完整几何和局部能力，旧版本始终按原语义读取，缺失字段迁移为中性值。当前写入版本由生产源码和迁移测试维护，本 ADR 不缓存易过期的“当前版本号”。

通道只传文件路径、最大预览边长、版本化参数、纹理 ID 和状态，不传图片字节。`ImagePipelineV1` 固定 sRGB 工作空间、曝光 EV、对比和色温语义；`ImagePipelineV2` 在不重解释 V1 的前提下增加高光、阴影、色调、饱和度、清晰度、规范化裁剪、90° 旋转与水平校正。双端对裁剪起点和宽高使用相同的 half-up 像素对齐，保证仅平移同尺寸裁剪时 Texture 尺寸不漂移。后端未知版本、越界参数或尚未冻结的非零人像强度必须拒绝。

### Android Adapter

- 使用 Flutter `SurfaceProducer` 暴露 Texture；调用方不接触 Android Surface。
- 在独立线程创建 EGL context，使用 GLES3、纹理、FBO/窗口 surface 和 shader 绘制最长边不超过 2048 px 的代理图。
- 滑杆更新在 Dart 侧合并，同一时刻最多一个通道更新在途。
- 预览不可用时退回既有 Flutter 矩阵，只作为兼容路径，不作为正式图像引擎。
- 高清导出解析同一版本化管线。V1 和无几何 V2 继续在单个可变 sRGB Bitmap 上分块处理；V2 几何先把已调色像素按行写入应用私有临时映射，成功 unlink 后才回收源 Bitmap并分行采样到唯一完整输出 Bitmap，因此不保留源图与目标图双 Bitmap 峰值。若 unlink 失败则中止导出并立即截断临时内容；该文件路径与像素不进入日志，成功和失败回归均检查无完整 RGBA 残留。48 MP Profile/Release 物理设备仍必须验证映射页、输出 Bitmap、磁盘余量、耗时和温控的实际峰值。
- GLES3 shader 执行与 CPU 导出相同的光色顺序和几何坐标语义；配方更新保持单一在途。GL 资源在专用渲染线程释放，Flutter `SurfaceProducer` 只在主线程注销。

### iOS Adapter

- 高清导出解析同一版本化管线并使用 Core Image。
- 原生预览通过 Core Image 与 `FlutterTexture` 提供，和导出共享参数语义；MethodChannel 或能力不可用时走兼容预览。
- V6 画质改善依次执行受控 Core Image 去噪、暗部定向曲线、低幅度对比/饱和恢复和亮度锐化；每项零值直接绕过，未知字段、非整数或越界值 fail closed。

## 取舍

- V1 首个纵切只迁移三项调节；V2 补齐 MVP 基础光色和构图，但仍不把功能存在当作自然人像或竞品画质证据。
- Android 选择 GLES3 作为基线，同时把后端藏在 Adapter 后；只有 Profile/Release 真机证据表明 GLES3 不满足目标时才引入 Vulkan。
- Android 高清导出仍需持有一个完整输出 Bitmap；分块方向解码和文件映射几何消除了双完整 Bitmap 峰值，但没有物理设备 Profile/Release 证据前仍不能宣称 48 MP 导出基座完成。

## 验证要求

- 单元测试锁定 V1/V2 序列化、严格拒绝规则、MethodChannel 无字节合同和纹理元数据校验。
- Android 编译必须验证 GLES 源码与当前 Flutter Texture Registry 接口兼容。
- Android Profile 或 Release 真机验证：方向、首帧、连续滑杆、前后台、快速切图、内存与释放。
- 固定样片比较 Android GLES 预览、Android 导出和 iOS Core Image 导出的数值/视觉差异。
