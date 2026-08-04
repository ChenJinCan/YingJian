# Firebase 可观测性接入

## 当前边界

应用已经提供供应商隔离层、事件白名单、Crashlytics 错误入口、Performance 自定义 Trace 和用户开关。Android 与 iOS 的原生默认值均为不采集；只有用户在设置页明确开启匿名诊断后，SDK 才会启用采集。

仓库已绑定独立 Firebase 项目 `yingjian-ce1d1`，Android 与 iOS 应用标识均为 `com.babycompany.yingjian`。原生配置和 `firebase_options.dart` 只能来自该项目，不得复制 NextNote、NatureID 或 animalplant 的 Firebase 配置。

## 首次配置

新增平台或 Firebase 产品时，由已认证的维护者重新执行：

```sh
firebase login
dart pub global activate flutterfire_cli
flutterfire configure \
  --project yingjian-ce1d1 \
  --platforms android,ios \
  --android-package-name com.babycompany.yingjian \
  --ios-bundle-id com.babycompany.yingjian
```

提交并审查 FlutterFire 生成的配置、Android Google Services/Crashlytics/Performance Gradle 插件，以及 iOS Crashlytics 符号上传 Build Phase。不要在日志中打印配置文件内容。随后执行：

```sh
bash scripts/check_firebase_setup.sh --require-configured
flutter test
flutter analyze
```

## 数据约束

- 只允许 `lib/observability/analytics_event.dart` 中列出的事件和参数。
- 不发送照片、文件路径、面部特征、提示词、自由文本、账号、精确位置、签名 URL 或原始异常消息。
- Crashlytics 只记录异常类型指纹、白名单原因和堆栈；产品流程不能依赖日志成功。
- Flutter 页面性能使用自定义 Trace；图片导入、预览生成和高清导出应分别计时，不记录文件名。
- 关闭诊断后立即关闭 Analytics、Crashlytics 和 Performance，并清除进程内最近轨迹。

## 验收证据

1. 新安装默认关闭诊断，Firebase 控制台无该安装的自定义事件。
2. 用户开启后，在 DebugView 验证白名单事件；确认参数中没有自由文本或路径。
3. 发送一个受控非致命错误和一个测试崩溃，分别验证 provider 接收与应用下次启动行为。
4. 在 iOS、Android 物理设备的 Profile 或 Release 构建中验证导入、预览和导出 Trace。
5. 再次关闭诊断，验证后续事件、错误和 Trace 均停止采集。
