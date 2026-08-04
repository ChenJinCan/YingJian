# iOS Portrait Mask Spike

> THROWAWAY PROTOTYPE — 验证 Vision 人脸几何、五官保护区、图片方向和一条受区域约束的像素候选，不是生产人像引擎。

运行 iOS 模拟器：

```sh
flutter run -d <ios-device-id> -t lib/main_portrait_mask_spike.dart
```

自动化模拟器烟测可将样片放到应用临时目录的 `portrait-spike-input.png`，并使用：

```sh
flutter run -d <ios-simulator-id> -t lib/main_portrait_mask_spike.dart \
  --dart-define=PORTRAIT_SPIKE_AUTORUN=true
```

运行后选择一张成人静态人像。页面会显示方向规范化后的代理图、几何候选脸部区域、五官保护区域、最终有效区域和覆盖检查图。每次分析还会生成：

- 方向规范化、sRGB JPEG 95 的原像素 baseline；
- `off`、`default`、`high_safe` 三档原像素 JPEG 导出；
- 与默认导出参数一致的最长边 1600 代理预览；
- `capture-manifest.json`，记录原始输入 SHA-256、源尺寸、设备/系统、候选版本、强度和每个产物 SHA-256。

候选包含克制的阴影提亮、低频均匀、噪声减弱和细节回注，只用于生成盲评输入。无人脸时三档原像素导出与 baseline 文件严格相同，证明安全降级而不是静默处理。

限制：

- 原生通道只在 iOS Debug 构建中注册；Release/Profile 不包含这个实验入口。
- 模拟器为绕过 Vision 推理后端限制会强制使用 CPU；它只证明通道、文件和失败降级可运行，不能作为五官坐标质量证据。
- 五官保护区和方向对齐必须使用物理 iPhone 与独立固定样片重新验收，未取得该证据前标记为“未验证”。
- 绿色有效区域由 Vision 关键点和保守几何构造，不是真实皮肤语义分割。
- 默认 `0.35` 与高安全 `0.55` 只是 Spike 参数，不是冻结的产品默认值；所有结果都显式返回 `productionEligible=false`。
- 输出位于应用临时目录，不写入项目、不保存到相册、不上传网络。工具启动和每次新分析都会先删除上一批采集；物理设备采集后必须在再次分析或退出前立即复制到本机被忽略的 `.quality/review-inputs/` 并核对 manifest，容器路径本身不是持久证据。
- 页面同时显示可供 `devicectl` 使用的容器相对路径。物理设备采集后可在本机执行：

```sh
xcrun devicectl device copy from \
  --device <device-id-or-name> \
  --domain-type appDataContainer \
  --domain-identifier com.babycompany.yingjian \
  --source <capture-relative-path> \
  --destination .quality/review-inputs/<asset-id>
```

复制后先逐项核对 `capture-manifest.json`，再把路径写入本地 review plan；不要提交目录中的照片、遮罩或 manifest。
- 验证完成后，只有结论和正式能力边界进入生产代码；原型应删除。
