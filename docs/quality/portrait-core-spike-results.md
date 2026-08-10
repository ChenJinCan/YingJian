# iOS 人像核心候选 Spike 结果

> 日期：2026-08-06
> 范围：历史端侧候选 Spike，仅用于解释候选边界。这里的工程结论不是六项能力已经通过同图竞品盲评，也不是真机性能结论。

## 多脸非几何保护

同一 1200px 最终 JPEG 接缝比较了三条路线：Vision 区域加 Core Image
`CINoiseReduction`、旧自建综合滤镜，以及隔离安装的 OpenCV 5.0.0 双边滤波。
正式应用没有链接 OpenCV。

- 四组固定双脸图均识别并保留两张适用脸。
- 三脸夹具保留三张脸；侧脸、眼镜、胡须、妆容和硬光夹具也保留三张脸。
- 大小脸混合夹具只拒绝小于 48px 安全门的对象，另外两张脸继续处理。
- 无人脸返回 `no_face`；四张脸返回 `too_many_faces`。Apple、自建和开源参照的关闭输出均与基线字节一致。
- 旧自建综合滤镜出现脸/头发边界发黑，已淘汰。生产质感磨皮采用受保护 mask 内的纹理处理，并在进入惰性 Core Image 链前物化输入以避免多人图空间错位。OpenCV 双边滤波仍只作为边缘保持参照，未成为生产依赖；实际强度由当前冻结候选的固定样片门决定。

本地证据由以下命令生成，输出保留在被忽略的 `.quality/`：

```sh
ruby scripts/run_ios_multiface_nongeometric_spike.rb \
  .quality/portrait-corpus-manifest.local.yaml \
  .quality/ios-multiface-nongeometric-spike-v1
```

## 保守瑕疵减弱

Apple 平台没有提供能自动区分痘印与身份细节的安全语义候选，因此系统路线按
no-op 记录。自建 Metal/Core Image 候选只检测局部相对红斑；OpenCV 5.0.0
参照使用相同红斑证据和局部 Telea 修复。两条处理路线都在脸内运行，开源参照仍未进入应用依赖。

- 固定集合包含一张同时具有明显炎性痘印、雀斑和妆容的书面同意样片，以及眼镜、皱纹、胡须、痣、妆容、不同肤色和硬光保护样片，共 14 张。
- 自建 `ios-local-red-blemish-candidate-v2` 能通过合成红斑减弱、棕色身份细节保护和脸外像素不变测试，但真实样片效果过弱，暂不选作产品路线。
- OpenCV 参照在明显痘印样片上具有可见的局部减弱，同时保留棕色雀斑、眉眼、唇妆、胡须和皱纹趋势。生产采用不依赖 OpenCV 的 `ios-local-red-blemish-candidate-v3`，其固定回归证明炎症红点减弱、棕色细节保持和 mask 外精确不变；正式人工局部质量门仍未关闭。
- 任一路线无法取得安全证据时，瑕疵减弱必须单项 no-op，不能退化为全脸磨皮，也不能阻断其他编辑或导出。

复现完整三候选报告：

```sh
YINGJIAN_OPENCV_PYTHONPATH=.quality/tools/opencv5 \
ruby scripts/run_ios_blemish_reduction_spike.rb \
  .quality/portrait-corpus-manifest.local.yaml \
  .quality/ios-blemish-reduction-spike-v3
```

正式质量结论仍必须把最终产品实现送入
`scripts/check_portrait_core_quality_scores.rb`，逐能力完成匿名同图盲评；本文件不能代替该门禁。
