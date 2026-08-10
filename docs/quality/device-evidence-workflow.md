# 物理设备性能与生命周期证据工作流

本工作流用于关闭冻结候选的物理设备、批量导出、信任与完整主旅程门。它不采信 Simulator、Debug 单次最好值、手写汇总或只有截图的“看起来正常”；所有输入都位于 Git 忽略的 `.quality/device-evidence/`。

## 1. 冻结候选身份

开始一轮设备测试前，冻结同一 `source_commit`。构建前把该 SHA 写入被忽略的 `assets/build/source-commit.txt`，使 Flutter 将其打入 IPA；构建结束后立即删除本地生成文件。iOS 三档设备复用同一个已签名 Profile/Release IPA；manifest 中的产物 SHA-256 必须与本地 `build_artifact` 文件一致。检查器会重新解包 IPA，验证内嵌源码身份、iPhoneOS 平台、Bundle ID、版本/build、Firebase、法律资源、签名、entitlements 与对应的设备 provisioning 模式，纯文本、任意 ZIP 或把旧 IPA 重新声明为新 commit 都不能作为构建产物。设备 run 不能混入其他 commit、版本、build 或构建模式。Android 设备证据延期到后续里程碑，不进入本轮 manifest。

将 `quality/device-evidence.example.yaml` 复制为 `.quality/device-evidence.yaml`。不得保留 `replace_with_*`、`unknown` 或 `not_recorded`。设备只记录机型/硬件档位，不把 UDID、序列号、账号或签名信息写入 manifest、日志或仓库。

## 2. iOS 三档矩阵

完整门要求恰好三个 iOS 物理设备 run：low/mid/high 各一项。每台设备使用本地随机标签的 SHA-256 作为 `device_id`，用于发现重复设备但不提交 UDID/序列号；三项必须互不相同。替代机型必须在 `tier_basis` 写清为什么属于冻结档位；`device.physical` 必须为 `true`。

先把同一 IPA 安装到对应设备。每档测试开始且设备已连接、配对、Developer Mode/DDI 可用时，使用冻结采集器生成设备与安装记录：

```sh
ruby scripts/capture_ios_device_evidence.rb \
  --device <CoreDevice-selector> \
  --output .quality/device-evidence/<run-id>/devicectl-device.json
```

采集器只调用绝对路径 `/usr/bin/xcrun devicectl`，同时保存设备列表和映见已安装应用的 Bundle ID、版本/build，并绑定采集器源码哈希、时间、主机匿名哈希和 devicectl 版本。原始 JSON 只能放在被忽略的 `.quality/device-evidence/`，因为它包含设备标识；manifest 的 `device_id` 必须是该记录中 CoreDevice `identifier` 的 SHA-256，机型、product type 与系统版本也必须与记录一致。Profile 产物的 provisioning device list 必须包含这台设备的 UDID，且安装查询必须与 IPA 的 Bundle ID、版本/build 完全一致。

每档都采集：

- 首次可用预览 5 次、六张三方案 5 次；
- 滑块响应与连续预览帧率各至少 20 个原始样本；
- 12 MP 单张和六张 12 MP 批量各至少 3 次；
- 中档补 24 MP 三次，高档补 48 MP 三次；
- UI 主线程 stall、峰值附加内存和完整 thermal state 序列；
- 三轮六张批量、后台恢复、系统低内存、取消恢复、离线、诊断关闭、零云端任务和无系统杀进程；
- iOS 额外完成系统分享成功、取消和失败，所有档位完成对应无障碍任务。

`methodology` 必须记录实际计时、内存、帧率、温控工具和可重复生命周期步骤。使用 Profile/Release 的 Instruments/xctrace、Flutter frame timing 或等价原始来源；不要用 Debug DevTools 数字替代。

## 3. 被哈希的原始证据

每个 run 至少保留四类文件：

1. `build_artifact`：实际测试产物的 ZIP/IPA/APK 或其他单文件封装；
2. `device_capture`：上述采集器生成的设备列表与安装应用原始 JSON 封装；
3. `metrics_log`：JSON，必须逐字段包含同一 `run_id`、`methodology`、原始 `measurements` 和 `outcomes`；
4. `final_artifact_probe`：JSON，绑定 `run_id` 与 `source_commit`，记录至少六个输出已经回查，并把方向、尺寸、裁剪、sRGB、JPEG 95、拍摄时间、敏感元数据清理和源哈希不变逐项标记为 `true`。

三个文件都必须位于 `.quality/device-evidence/`，填写真实小写 SHA-256，符号链接不得逃逸。指标 JSON 与 manifest 不一致时直接失败。

## 4. 执行门禁

采集中可检查现有 run，但不能得到完整通过结论：

```sh
ruby scripts/check_device_evidence.rb \
  .quality/device-evidence.yaml \
  --allow-incomplete \
  --source-commit "$(git rev-parse HEAD)"
```

iOS 三档完成后把 `status` 改为 `ready`，运行完整门：

```sh
ruby scripts/check_device_evidence.rb \
  .quality/device-evidence.yaml \
  --source-commit "$(git rev-parse HEAD)"
```

检查器按 nearest-rank 从原始序列计算 p50/p95，按低/中/高冻结预算检查首预览、六张推荐、滑块、最低帧率、12/48 MP、六张批量、100 ms UI stall、设备内存 25%/512 MB 双上限和温控。完整生产门还会用绝对路径 `/usr/bin/xcrun` 现场重查三个互不重复 UDID 的 iPhone 均已连接，并逐台确认同一映见版本/build 仍已安装；因此最终集中验收时三档设备必须同时可查询。完整门只接受 3/3 iOS；缺 run、重复档位/UDID、跨 build、证据哈希漂移、现场设备/安装状态不符、严重温控无降级或任一恢复/隐私结果为 false 都会失败。

这个门会独立验证签名 iOS 产物与 `devicectl` 物理设备记录，并证明 manifest、原始日志和被哈希文件内部一致、按冻结预算计算通过；它仍不能替代样片授权、人像/组图盲评、真人任务或测试人员对测量方法真实性的签字确认。
