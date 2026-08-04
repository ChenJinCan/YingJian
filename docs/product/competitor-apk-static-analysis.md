# 竞品 Android 安装包身份与静态分析基线

> 状态：四个可验证 Android 包已下载并完成第一轮静态分析；未安装、未运行
> 证据快照：2026-08-04（Asia/Shanghai）
> 范围：醒图、Berry 胶片相机、一甜相机、无他相机、黄油相机，以及 App Store ID `6751189827` 的“水印实时相机”

## 1. 研究目的

本文件先解决一个比“下载到一个同名 APK”更重要的问题：确认后续分析对象确实是目标竞品。每个候选包必须同时记录产品名、Android application ID、开发者身份、商店版本、分发格式和文件摘要；不能只凭 APKPure 搜索标题判断。

本轮从 APKPure 公开下载端点取得四个 APK，在 Git 忽略的 `.scratch/competitor-apks/` 中完成哈希、签名、manifest、资源目录和精选原生库的静态检查。没有安装或运行任何竞品，也没有绕过 Berry 的付费下载或以同名应用代替水印实时相机。APKPure 属于第三方分发证据，不能代替 Google Play、开发者官网或手机厂商应用商店的一手身份依据，也不能单独证明文件未被重打包。

## 2. 证据等级与方法

证据优先级如下：

1. Google Play 的应用详情页或开发者自己的官网；
2. 小米等设备厂商应用商店的应用详情页；
3. APKPure 的应用页、版本页和下载页；
4. 其他第三方下载站只用于交叉发现，不作为最终包身份依据。

一个包进入静态分析前，至少要通过以下门禁：

- application ID 与一手商店链接中的 ID 一致；
- 产品名与开发者主体能够对应；
- APKPure 展示的签名摘要、版本、架构和文件格式已记录；
- 下载后本地计算 SHA-256，不把网页显示值当成本地证据；
- 使用 `apksigner verify --print-certs` 读取实际签名证书，并与同包名的历史版本或一手安装来源交叉验证；
- 如果是 XAPK/APKM/APKS，保存容器原件并记录内部 base/split 清单，不能只分析其中一个 split；
- 不运行未知二进制，不向竞品服务发送自动化流量，不尝试绕过登录、付费、加密或访问控制。

## 3. 当前身份与可获取性结论

| 竞品 | 锁定的 Android application ID | 一手身份依据 | APKPure 当前可见候选 | 公开下载形态 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 醒图 | `com.xt.retouch` | [小米应用商店：醒图](https://m.app.mi.com/details?id=com.xt.retouch)，开发者“深圳市脸萌科技有限公司” | [15.1.0 下载页](https://apkpure.net/cn/xingtu-photo-editor/com.xt.retouch/download)，351.6 MB，arm64-v8a | APK | 身份高置信；可以进入下载前校验 |
| Berry 胶片相机 | `com.seesun.berryberryfilm` | [Google Play：BerryFilm](https://play.google.com/store/apps/details?id=com.seesun.berryberryfilm)，开发者 Imagine_Works | [APKPure 应用页](https://apkpure.net/cn/berryfilm/com.seesun.berryberryfilm) 可见 1.3.32/1.3.33 附近版本信息 | **数据缺失**：当前页面未观察到可验证的 APK/XAPK 下载入口 | 身份高置信；APKPure 可下载性尚未证明 |
| 一甜相机 | `com.kwai.m2u` | [小米应用商店：一甜相机](https://m.app.mi.com/details?id=com.kwai.m2u)，开发者“北京快手科技有限公司” | [APKPure 4.55.0 下载页](https://apkpure.net/%E4%B8%80%E7%94%9C%E7%9B%B8%E6%9C%BA-%E8%A7%A3%E9%94%81%E4%BD%A0%E7%9A%84%E5%B0%91%E5%A5%B3%E5%8A%9B/com.kwai.m2u/download/4.55.0.45501)，页面另列 4.70.0 为较新候选 | APK，universal | 身份高置信，但 APKPure 版本明显落后于一手商店，不应称作当前最新版 |
| 无他相机 | `com.benqu.wuta` | [Google Play：Wuta Camera](https://play.google.com/store/apps/details?id=com.benqu.wuta)；[小米应用商店](https://m.app.mi.com/details?id=com.benqu.wuta)，开发者“上海本趣网络科技有限公司” | [APKPure 7.1.2.166 下载页](https://apkpure.net/cn/wuta-camera-nice-shot-always/com.benqu.wuta/download)，99.1 MB | APK，arm64-v8a + armeabi-v7a | 身份高置信；Google Play 与 APKPure 的同包名关系可交叉验证 |
| 黄油相机 | `com.by.butter.camera` | [小米应用商店：黄油相机](https://m.app.mi.com/details?id=com.by.butter.camera)，开发者“北京缪客科技有限公司” | [APKPure 10.27.1.10 下载页](https://apkpure.net/cn/%E9%BB%84%E6%B2%B9%E7%9B%B8%E6%9C%BA/com.by.butter.camera/download)，105.4 MB | APK，universal | 身份高置信，但 APKPure 候选落后一手商店；同名 `com.capcut.foodcam.photo` 是错包 |
| 水印实时相机（iOS `6751189827`） | **数据缺失** | [Apple App Store](https://apps.apple.com/cn/app/id6751189827) 只证明 iOS 产品及开发者“华 范” | 未找到能同时匹配产品全名、开发者主体和稳定 application ID 的 APKPure/Google Play 页面 | 数据缺失 | 不得用任一同名“水印相机”APK替代；暂不进入 Android 静态分析 |

## 4. 分应用证据记录

### 4.1 醒图

- 小米应用商店 URL 的查询参数和 APKPure 下载页均指向 `com.xt.retouch`；一手商店在证据日展示版本 `15.1.0`、开发者“深圳市脸萌科技有限公司”。
- [醒图官方站](https://www.retouchpics.com/)可作为品牌归属的补充入口；Google Play 的中国版包页面当前未得到有效分发证据。
- APKPure 下载页在证据日展示版本 `15.1.0`、APK、arm64-v8a、约 351.6 MB，并展示签名摘要 `388078466f4e856329b809eef44e284a7afe86da`。
- Google Play 上的 `com.xt.retouchoversea` 是国际产品 Hypic，不能替代中国版醒图的 `com.xt.retouch`。
- 下载决策：可优先取 APKPure 的 `15.1.0`，但必须先保存响应最终 URL、HTTP 元数据，再本地核对包名、版本、证书和 SHA-256。

### 4.2 Berry 胶片相机

- Google Play 一手页面直接以 `com.seesun.berryberryfilm` 为 ID，并展示开发者 Imagine_Works；这是六款中最清晰的 Android 一手映射之一。
- Google Play 在证据日展示 2026-07-12 更新、付费下载；APKPure 应用页显示同包名、同开发者，版本信息在抓取时出现 `1.3.32` 与搜索索引 `1.3.33` 的不同快照。
- APKPure 应用页没有提供足以确认当前下载文件格式和直链的公开证据。不能因为页脚写有“XAPK/APK 安装”就推断该应用实际提供 XAPK 或 APK。
- 下载决策：先检查 Google Play 合法购买/设备安装路径；若 APKPure 仍无明确下载入口，则标记“APKPure 不可获取”，不使用来路不明的镜像替代。

### 4.3 一甜相机

- 小米应用商店以 `com.kwai.m2u` 展示一甜相机、北京快手科技有限公司、版本 `4.76.0.47601`（2026-06-25）。
- APKPure 可见的下载页仍是 `4.55.0.45501`，并列出的较新版本为 `4.70.0.47001`；二者均落后一手商店快照。
- 搜索结果还存在 `com.kwai.m2u.gp`、开发者 Rawpic Lab 的 Google Play 条目。当前没有证据证明它与北京快手科技有限公司发布的中国版属于同一签名/同一发行线，因此不纳入目标包。
- 下载决策：可将 APKPure 的旧 APK 用于历史架构观察，但任何“当前实现”结论都必须注明版本差距；优先寻找 `4.76.0.47601` 的可信厂商商店安装包。

### 4.4 无他相机

- Google Play 与小米应用商店均以 `com.benqu.wuta` 对应无他相机，开发者主体/品牌信息能够互相印证。
- APKPure 下载页在证据日展示 `7.1.2.166`、APK、99.1 MB、arm64-v8a 与 armeabi-v7a，并给出 SHA-256 `d7b24730d00c156cccde05bbe3ed03f4a310ffbb02ab11b50743de2968aedfc2`。
- 上述 SHA-256 只是网页声明。下载完成后仍需重新计算，且 APKPure 的“安全”标记不能代替签名身份校验或代码审计。
- 下载决策：这是当前最适合先行建立完整取包与静态分析流程的对象，因为一手 Google Play 身份、第三方包名、版本格式和文件摘要都可交叉检查。

### 4.5 黄油相机

- 小米应用商店以 `com.by.butter.camera` 展示黄油相机、北京缪客科技有限公司、版本 `10.35.0.10`（2026-07-20）。
- [黄油相机官网](https://www.bybutter.com/)可作为品牌归属的补充入口。
- APKPure 下载页仍停留在 `10.27.1.10`（2025-07-16）、APK、universal、105.4 MB，版本约落后一年。
- APKPure 另有同名近似应用 `ButterCam黄油相机-Filter Cutout Co`，包名为 `com.capcut.foodcam.photo`、开发者 yeluiliying LLC；该包与本研究目标无关，必须明确排除。
- 下载决策：APKPure 旧包只适合历史结构参考。要分析当前产品，应优先从一手厂商商店获取 `com.by.butter.camera` 的较新版本，并核对证书连续性。

### 4.6 水印实时相机（App Store ID `6751189827`）

- Apple 一手页面显示完整名称“水印实时相机：水印记录实时时间地点”、开发者“华 范”，并明确是仅适用于 iPhone 的产品。
- Apple 元数据中的 iOS bundle ID 为 `com.nero.watermarkcam`；bundle ID 不能直接推定为 Android application ID。
- 截至证据日，没有找到 Google Play、开发者官网或 APKPure 页面，能够同时匹配该完整名称、开发者身份和一个稳定 Android application ID。
- 搜索到的“水印相机”“水印实时相机”“足迹地图相机”等 Android 应用均不能凭功能或名称相似建立同产品关系。
- 下载决策：Android 包身份记为“数据缺失”，禁止下载同名包凑齐六款。该竞品只能继续做 iOS 商店/真机行为研究，除非后续获得开发者一手 Android 链接。

## 5. 本地样本身份

安装包保存在 Git 忽略目录 `.scratch/competitor-apks/packages/`，不会提交到仓库。以下摘要均由本地文件重新计算，不是抄录网页值。

| 产品 | versionName / code | 文件字节数 | 本地 SHA-256 | ABI | min / target SDK | DEX |
| --- | --- | ---: | --- | --- | --- | ---: |
| 醒图 | `15.1.0` / `151090` | 368,708,861 | `11eb1893be551068a98e68053bb4f0df8e86b10000c351c36a3f3885d66b45bd` | arm64-v8a | 21 / 34 | 35 |
| 一甜 | `4.70.0.47001` / `47001` | 129,487,976 | `3648bf6a12a8a20588aed2e2d326ee6e7cc44127d285d3fd953b7d4cb8ad1d66` | arm64-v8a | 21 / 30 | 30 |
| 无他 | `7.1.2.166` / `712` | 103,875,289 | `d7b24730d00c156cccde05bbe3ed03f4a310ffbb02ab11b50743de2968aedfc2` | arm64-v8a、armeabi-v7a | 23 / 36 | 9 |
| 黄油 | `10.27.1.10` / `17625` | 110,564,581 | `f244b12da5a69e9e77d58427476045cdd38684b74777e94605a8020e94ca0909` | arm64-v8a、armeabi-v7a | 24 / 34 | 9 |

`apksigner verify --print-certs` 对四包均验证通过并读取到以下签名证书 SHA-256：

- 醒图：`23f1a1e9c49f1dbe64643bac130e29a9b0b369e90bdf6947a954adfbebc9e200`，证书主题包含 `CN=xingtu` 与深圳市脸萌科技英文主体。
- 一甜：`9c54a1feb10c42b7254acb2b6827fd2b51b9aa31eb70183c048fabe73173b38e`，证书主题包含 `OU=kwai, O=m2u`。
- 无他：`df195732442966b578d581fe346792974cc6c220964c9e61cd47366e3b5332a1`，证书主题为上海本趣网络科技有限公司；其 SHA-1 与 APKPure/APKMirror 公示的历史签名一致。
- 黄油：`6600949e0f7a4deea371d8e4da134d117c8dc4c50b7f9ccd747de64c3a5e10a5`，证书主题为 `by.butter`。

前三项身份链分别有一手商店包名、第三方文件包名和签名主体/历史指纹交叉支持。黄油的本地签名可被读取且包名正确，但本轮没有取得厂商商店 APK 做证书直接对照，所以仍保留“第三方历史样本”限定。

## 6. 图像引擎静态证据

### 6.1 跨产品结论

四个 APK 均没有 `libflutter.so` 或 `flutter_assets/`，因此其 Android 图像主链不是 Flutter runtime + `ColorFilter.matrix` 这一类实现。四包都包含数量可观的原生库；选定与图像相关的 arm64 ELF 后，`llvm-readobj` 和 `llvm-nm` 确认四款均存在 EGL/OpenGL ES 依赖或导入。这里的“存在”是文件级事实；某条路径是否在某功能和设备上实际启用，仍需运行时追踪。

| 产品 | arm64 原生库 | 直接可验证的图形/计算线索 | 内置资源线索 | 证据强度 |
| --- | ---: | --- | --- | --- |
| 醒图 | 156 个，约 269 MiB 未压缩 | `libcccreator.so` 直接链接 EGL/GLES2，同时含 Vulkan 动态加载符号；`libpainter.so` 链接 GLES2/3；`libretouch_sdk.so` 链接 GLES2/3；`liblens.so` 链接 GLES2 并含 OpenCL 加载字符串 | 27 个 `.model`、39 个 LUT 命名项；包括 HDRNet、皮肤分割、抠图、场景识别、人脸关键点/拟合 | 强：确认存在多后端原生图像代码；具体主路径未验证 |
| 一甜 | 139 个，约 131 MiB 未压缩 | `libCGE.so` 直接链接 EGL/GLES2并动态加载 Vulkan；`libFaceMagic.so` 直接导入 GLES，并出现 `RendererType_Vulkan`；`libgorgeous.so` 直接导入 GLES；另有 OpenCV、TFLite、SNPE、HiAI、MTK TFLite | 15 个模型文件、前景/背景 LUT、关键点模型、照片 RGB shader | 强：确认是 GLES + 可选 Vulkan + 多推理后端的异构结构；运行时选择未验证 |
| 无他 | 33 个 arm64 + 33 个 armv7 | `libwtcore.so` 直接链接 EGL/GLES2/GLES3；`libgp.so` 链接 GLES2；`libst_mobile.so` 链接 GLES3 | 36 个 shader 命名项、6 个 SenseME 模型、30 个 LUT 命名项；可见高斯模糊、motion blur、LUT、脸/虹膜/人体分割资源 | 强：确认存在原生 GLES shader 人像/滤镜管线；功能映射未动态验证 |
| 黄油 | 47 个 arm64 + 45 个 armv7 | `libst_mobile.so` 直接链接 EGL/GLES3；存在 TensorFlow Lite/Flex、RenderScript Toolkit；`libmml_framework.so` 含 OpenCL 动态加载符号 | SenseME Face Video 模型、少量 LUT 命名项 | 中强：确认至少人脸/效果组件具有 GLES3 路径；模板/静态编辑主链未定位 |

### 6.2 醒图

- `libcccreator.so`、`libpainter.so` 和 `libretouch_sdk.so` 都真实导入了 framebuffer、texture、shader、uniform、draw、read-pixels 及 EGL context/surface 相关函数；这不是普通 UI 包里偶然出现一个 `libGLES` 字符串。
- `libcccreator.so` 在直接使用 GLES 的同时包含 `libvulkan.so`、`vkGetInstanceProcAddr` 和 Vulkan 版本字符串，说明包内存在可动态选择或回退的 Vulkan 代码路径。静态分析不能证明醒图照片编辑在当前设备上默认使用 Vulkan。
- 内置模型命名覆盖 HDRNet tone/effect、皮肤分割、头部/人体抠图、场景识别、骨骼、人脸属性、关键点与拟合。这支持“图像分析/人像理解 + GPU 合成”组合架构的判断，但模型名称不能证明宣传效果质量。
- `liblens.so` 出现 OpenCL 动态加载与 `clCreateContext`，说明部分计算可能走 OpenCL；不能据此定位到某个用户功能。

### 6.3 一甜

- `libCGE.so` 的 EGL/GLES2 导入覆盖 shader 编译、FBO、纹理、uniform、draw 和 read-pixels；同时包含 Vulkan instance 创建和动态加载符号。
- `libFaceMagic.so` 既直接导入大量 GLES API，又出现 `CGE::Core::RendererType_Vulkan`；更合理的静态结论是“存在 GLES 实现，并编入可选 Vulkan renderer”，而不是“一甜全部使用 Vulkan”。
- 包内同时存在 `libopencv_world.so`、TensorFlow Lite、Qualcomm SNPE、Huawei HiAI 和 MTK TFLite 相关库。这表明其模型推理针对不同芯片/设备准备了多种后端，图像渲染与 AI 推理不是同一个简单矩阵步骤。
- 一甜样本比厂商商店当前版本落后，因此这些结论只能描述 `4.70.0.47001`，不能自动代表 `4.76.0.47601`。

### 6.4 无他

- `libwtcore.so` 同时链接 GLES2/GLES3，并导入 2D/3D texture、FBO、sync、shader、uniform、draw 和 `ANativeWindow` 相关能力；`libgp.so` 和 `libst_mobile.so` 分别提供额外 GLES2/GLES3 路径。
- APK 直接内置多个 `.vert`、`.frag` 和 `.fsh`；文件名明确出现 LUT 组合、高斯横纵向模糊、motion blur，以及食物/风景/肤质风格 shader。
- 内置 SenseME 脸部、额外脸部点、虹膜、猫脸与人体分割模型。可以确认包内具备本地人像理解资源；无法仅凭文件判断它们是否在所有效果下离线运行。

### 6.5 黄油

- `libst_mobile.so` 直接链接 EGL/GLES3 并导入完整 shader/FBO/texture 绘制集合，配合内置 SenseME Face Video 模型，说明至少一部分人脸/效果能力不是 Flutter 或 Java 色彩矩阵。
- `libmml_framework.so` 含 OpenCL 动态加载与 context 创建字符串；包内另有 TensorFlow Lite、Flex 和 RenderScript Toolkit。这些是多种计算能力共存的证据，但尚不能把某个库精确映射到相机、滤镜、模板或 AI 修复。
- APKPure 样本约落后厂商商店一年；当前版可能已经更换或扩展引擎，必须取得新包后复核。

### 6.6 Vulkan 与 OpenCL 的谨慎结论

- 一甜的 `libCGE.so`、`libFaceMagic.so` 和醒图的 `libcccreator.so` 存在较明确的 Vulkan renderer/loader 证据，同时仍直接链接 GLES；更像“多后端或设备回退”，不是“已经放弃 OpenGL”。
- 醒图 `liblens.so`、黄油 `libmml_framework.so` 以及一甜其他计算库可见 OpenCL 加载线索。OpenCL 更可能服务特定计算/推理，但静态证据不能确定。
- 无他只出现弱的 `vulkan` 字符串，没有定位到 Vulkan loader 或关键 API；不能据此声称支持 Vulkan。
- 没有任何证据支持“只要采用 Vulkan 就能得到竞品画质”。画质来自参数语义、shader/模型、颜色管理、预览与导出一致性以及内容资产共同作用。

## 7. 框架、权限与隐私线索

- 四包均无 Flutter runtime 标记。一甜存在 Hermes/React Native 相关库，但只说明部分界面或业务模块可能使用 React Native，不能把图像引擎归为 React Native。
- manifest 声明的权限数量分别为醒图 215、一甜 45、无他 52、黄油 47；四包都有相机、网络和媒体读取相关权限。醒图还声明 `MANAGE_EXTERNAL_STORAGE`，一甜/无他声明位置权限，黄油声明 `READ_PHONE_STATE`，多包含广告 ID、推送和广告 SDK 权限。
- 权限声明只证明应用申请能力，不证明用户已授权、数据已上传或某 SDK 在当前地区实际运行。隐私结论仍以官方政策和受控动态网络观察为准。

## 8. 对映见 MVP 的工程含义

这轮 APK 静态证据足以否定“继续把 Flutter 色彩矩阵扩展成最终引擎”，但不足以支持“立即把 Android 全部押到 Vulkan”。竞品表现出的共同架构更接近：

1. 原生 EGL/GLES 负责纹理、FBO、shader 和即时合成；
2. LUT、曲线、模糊、纹理、人像遮罩等组成效果配方，而不是单一矩阵；
3. 人脸/皮肤/场景分析由模型和不同设备推理后端提供参数或 mask；
4. Vulkan/OpenCL 是部分产品的可选计算或渲染路径，GLES 仍作为明确存在的主干或回退；
5. UI 框架与像素引擎分离。

因此映见 MVP 更合理的第一版是：Android 先建立 GLES3 原生纹理管线与供应商无关的 `ImagePipelineV1`，保留可替换 backend 接口；iOS 使用 Core Image/Metal；Flutter 只传文件路径、参数、区域和 texture handle。只有当 Profile/Release 真机基准证明 GLES3 在目标设备无法达到画质、延迟、内存或 48 MP 导出门槛时，再把 Vulkan 纳入实现，而不是因竞品包里出现 Vulkan 字符串提前承担双后端成本。

## 9. 已完成批次与剩余取包

本轮已经完成原计划前两批：

1. **无他、醒图：** 已完成取包、哈希、签名、manifest、native library 与资源 inventory。
2. **一甜、黄油：** 已完成 APKPure 历史样本分析，所有结论均标注版本滞后。
3. **Berry：** 仍需走合法付费取得或开发者提供的测试包；APKPure 没有可验证公开直包时不继续绕行。
4. **水印实时相机：** 不进入 Android 下载批次，除非后续获得开发者一手 Android 链接。

后续取得新版本时仍应记录来源 URL、重定向后 URL、UTC 下载时间、原始文件名、字节数、SHA-256、容器格式、application ID、versionName、versionCode、min/target SDK、签名证书摘要、ABI/split 清单。APK、XAPK、APKM 等二进制和解包目录不得提交到仓库。

## 10. 后续动态验证问题，而非反编译目标

第一轮静态分析已经回答了安装包内存在哪些图形、模型和资源路径。下一阶段只应补足静态证据不能回答的运行时问题：

- 冷启动和进入编辑后实际加载哪些 `.so`；
- GLES 与 Vulkan renderer 在不同 GPU/系统上的选择、回退和黑名单；
- 滑块期间的帧率、GPU 时间、纹理分辨率、峰值内存和发热；
- 人像模型是否离线执行，哪些 AI 功能发生网络上传；
- 预览与导出是否共享参数顺序、颜色空间和遮罩语义；
- 超大图是否分块处理，导出如何处理失败、恢复、EXIF、ICC 与方向；
- 组图是否存在共享风格、逐张补偿和单张覆盖，而不是简单复制参数。

不得把库名或字符串出现直接写成“竞品采用了某技术完成某功能”。例如 APK 中出现 `libGLESv3.so` 调用只证明存在相关代码路径线索，不证明照片编辑主链路必然使用 OpenGL ES；最终报告必须保留“事实 / 推断 / 数据缺失”三层。

## 11. 当前限制

- 本文件中的版本和下载状态是 2026-08-04 的网页快照，第三方镜像可能随时变化。
- APKPure 不是这些产品的官方发布者；其“Trusted App”“安全”或 VirusTotal 结果不是发行身份的充分证据。
- 四个样本来自 APKPure 第三方镜像；虽然本地签名验证通过并进行了身份交叉核验，但没有全部与当前厂商商店二进制逐字节对照。
- Berry 是付费应用，本轮没有绕过付费取得 APK；水印实时相机没有可信 Android 身份，所以二者没有二进制结论。
- 一甜和黄油样本落后当前一手商店版本，醒图 APKPure 样本也不能代表后续版本。
- 中国区应用在 Google Play 上可能不存在或使用不同国际产品线；不能把国际版包自动视为中国版等价实现。
- 静态分析不能可靠证明运行时具体图像处理路径、GPU 占用、预览延迟、云端调用或导出质量，这些仍需隔离环境下的真机动态验证。
