# iOS MVP 真人可用性证据工作流

本工作流用于形成集中验收所需的真人任务证据；只有最终报告同时记录保留和拒绝的交互结构后，交互决策才可冻结。它只接受同一冻结源码提交、真实 iPhone、无口头指导的 2–6 张照片完整任务；Simulator、Debug、演示、主持人代操作和自由文本总结都不计入证据。

## 1. 冻结候选

测试前从 `.quality/device-evidence/ios-mvp.yaml` 选择一个已通过设备合同的 iOS run，记录完整 `source_commit`、映见版本/build、已安装 Profile/Release 产物的真实文件 SHA-256 和实际 iPhone 机型/系统。设备合同必须已经验证 IPA 内嵌源码身份、Apple 签名与 provisioning、`devicectl` 物理设备记录及该设备上的已安装版本/build。五名参与者必须使用同一源码与产物身份；任何修复都会产生新的候选，旧会话不能拼接到新提交。

参与者使用自己的非敏感照片或经授权的测试照片。原图、屏幕录制、姓名、联系方式、设备 UDID、自由文本观察和人脸信息不得写入仓库或会话 JSON。若需保留本地观察，只存放在被忽略的 `.quality/`，并与机器可判定证据分开。

## 2. 执行无引导任务

复制 `quality/usability-session.example.json` 到 `.quality/usability/sessions/session-<opaque-id>.json`。每名参与者使用不同的随机 `participant_id` 和 `session_id` SHA-256，不记录真实身份映射。

观察者只读记录以下正式任务是否完成，不提示入口或下一步：

1. 导入 2–6 张照片；
2. 在对应设备档位预算内检查三套本地推荐；
3. 主动选择一套推荐；
4. 调整整组；
5. 调整当前照片；
6. 分别完成撤销、重做和前后对比；
7. 返回整组；
8. 中断并恢复项目；
9. 从应用自有原图导出照片。

目标用户资格固定引用 `docs/product/product-context.md` 的 `first-target-user-v1` 定义及文件 SHA。观察者必须逐项确认参与者经常用手机拍照、会发布多张照片、希望获得质量但不想学习专业流程，并愿意从可靠结果开始做少量微调；只保存这些非个人身份布尔项和观察者确认，不保存职业、账号或联系方式。`uncoached` 必须为 `true`，`observer_interventions` 必须为 `0` 才计入门禁。任务结束后分别询问整组调整与当前照片调整的影响范围、三推荐是否更省事，以及是否理解三推荐是本地处理而非三次云端生成。不得在任务过程中解释答案。会话只记录当前冻结的 `production` 体验；获胜/保留/拒绝结构在集中验收最终报告中另行记录。

## 3. 构建并验证汇总

不要手填通过率。构建器从单次 JSON 派生完成、范围理解和推荐价值布尔值，再调用同一个公开检查器验证五人阈值：

```sh
ruby scripts/build_usability_evidence.rb \
  .quality/usability/sessions \
  .quality/usability/ios-mvp.yaml \
  --source-commit <full-git-sha> \
  --device-matrix .quality/device-evidence/ios-mvp.yaml \
  --device-run <ios-run-id>

ruby scripts/check_usability_evidence.rb \
  .quality/usability/ios-mvp.yaml \
  --source-commit <full-git-sha>
```

构建器要求至少五份结构化会话，并先执行完整三档设备合同，再把会话绑定到其中同一物理 iPhone run、Profile/Release 构建和实际产物文件哈希；同时校验冻结的目标用户资格、完整成功会话、2–6 张项目、推荐时限、零主持人干预、原图导出和零云端图片任务。任何参与者把推荐理解为云端生成都会阻断本轮，而不是被总体比例抵消。

通过阈值仍按 Spec：导入到导出完成率至少 80%，整组/当前照片理解率至少 70%，认为三推荐省事的比例至少 60%。该结果只关闭真人交互门，不替代人像盲评、图像质量或三档物理设备性能证据。

## 4. 冻结最终交互决策

五份会话通过后，以 `quality/mvp-final-report.example.yaml` 为结构创建被忽略的 `.quality/final-report.yaml`。将 `decision` 写为 `implemented_and_validated`，把 `interaction_decision.status` 冻结为 `frozen`、`winning_variant` 冻结为 `production`，并从 Spec 的冻结结构 ID 中列出至少一项保留结构和一项拒绝结构；两组不得重叠。同时绑定可用性 manifest 的文件/SHA、同一 device run ID，以及汇总实际引用的全部 session ID。随后把 `docs/product/mvp-spec.md` 的两条交互决策标记同步冻结，并记录该 Spec 的真实 SHA-256。

`scripts/check_mvp_acceptance.rb` 会解析最终报告而非只校验文件哈希，并验证报告、Spec、源码提交、可用性设备 run 与三档设备矩阵是同一条证据链。当前仓库中的 `pending` 示例不会通过最终验收，这是预期行为。
