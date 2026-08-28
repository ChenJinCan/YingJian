# RapidRAW 对映见的可用性评估

> 调研日期：2026-08-11；RapidRAW 基线：`main` commit
> `9d0f23c095d3dea1287987d35e3c81eb1323de45`。

## 结论

RapidRAW 值得作为图像编辑工程案例参考，但不适合作为映见的代码库或产品结构直接移植。
最有价值的是预览任务调度、几何与蒙版的一致性、组合蒙版语义，以及资源感知导出的设计输入。
映见已经具备更符合移动端产品合同的版本化配方、整组/单张层级、语义撤销和原图重放，
不应以 RapidRAW 的桌面状态模型替换现有领域模型。

## 建议分级

### P0：直接转化为回归测试，不复制实现

1. 增加“蒙版或消除笔迹经过裁剪、旋转、拉直后仍锚定原目标”的预览/导出同义性矩阵。
   RapidRAW 在渲染蒙版时显式携带 `crop_offset`，并对组合子蒙版统一生成位图；其变更记录也反复出现
   crop、transform 与 patch/mask 偏移修复。这说明该组合是成熟编辑器的高风险接缝。
   映见当前能分别证明几何与蒙版，但没有发现覆盖二者组合的明确测试。
   来源：[蒙版生成](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src-tauri/src/mask_generation.rs#L1320-L1387)、
   [项目变更记录](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/README.md#recent-changes)。

2. 把“快速连续拖动只显示最新有效结果、切图后旧任务不得覆盖新图”保留为明确性能/正确性合同。
   RapidRAW 使用 job id 丢弃过时结果，把交互中的最新请求放入单槽 pending，并限制同时在途任务；
   映见已经有串行 drain 和最后值覆盖，方向一致，不需要替换，只需要在真机性能验收时验证延迟和无陈旧帧。
   来源：[预览任务与 backpressure](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src/hooks/useImageProcessing.ts#L172-L304)。

### P1：先做真机 profiling，再独立实现

1. 交互时按可见区域渲染 ROI，停止拖动后补全高分辨率结果。
   RapidRAW 会从缩放和视口计算标准化 ROI，并在交互路径返回局部 patch；这对人像、局部和高分辨率预览很有价值。
   映见当前固定在最长边 2048 的完整纹理上串行渲染。只有 Profile/TestFlight 真机数据证明滑杆延迟、内存或温控超预算时，
   才值得为 Core Image/Metal 增加 ROI，避免为了桌面方案提前复杂化移动端管线。
   来源：[ROI 计算与交互 patch](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src/hooks/useImageProcessing.ts#L64-L120)、
   [交互返回处理](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src/hooks/useImageProcessing.ts#L204-L257)。

2. 将批量导出的并发度绑定到设备预算，而不是写死并发数。
   RapidRAW 根据 CPU 和可用内存推导并发上限，并在每项任务前后设置取消检查点。
   映见只有 1–6 张且当前串行导出更保守；在真机证明串行时间不可接受前，不应直接改成并行。
   若要优化，应以 low/mid/high iPhone 的峰值内存、温控和 PhotoKit 结果为门禁，通常从并发 1/2 A/B 开始。
   来源：[资源感知导出](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src-tauri/src/export_processing.rs#L885-L969)。

### vNext：借鉴领域语义

1. 组合蒙版可统一建模为容器加子蒙版，每个子蒙版支持 add、subtract、intersect、invert 和 opacity。
   映见当前 paint/erase 足够支撑 MVP；交集、整体透明度和多个语义蒙版组合适合在 MVP 验收后进入独立 Spec，
   不应混入当前候选。
   来源：[组合运算](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src-tauri/src/mask_generation.rs#L1332-L1387)。

2. “只同步选中的参数组”可作为整组编辑的高级能力参考。
   RapidRAW 支持 merge/replace、参数白名单和可选 auto-sync；映见已有更安全的整组/当前照片范围与确认流程，
   因而应保留当前显式语义，只在用户研究证明有需求时增加按参数组同步。
   来源：[同步合同](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src/utils/adjustments.ts#L19-L30)、
   [增量同步](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/src/hooks/useImageProcessing.ts#L444-L466)。

## 不建议采用

- 不迁移 React、Tauri、Rust/WGPU 技术栈。映见的 Flutter 状态层加 iOS Core Image/Metal Texture 边界已经符合产品和平台合同。
- 不复制桌面双侧栏、直方图、波形、RAW 库、镜头校正和 EXIF 管理；映见当前明确不竞争完整专业 RAW 工作流。
- 不复制 RapidRAW 的单个大型 `Adjustments` 对象、字符串键和宽泛 `any` 归一化方式。映见的类型化、版本化值对象与 fail-closed 迁移更适合可恢复配方。
- 不把其 AI 去噪、景深、LaMa/ComfyUI 等能力直接接入。模型许可证、包体、隐私、端侧预算和画质均需独立验证，且多项不在当前 MVP。
- 不把 RapidRAW 当成已验证算法库。项目自述仍在活跃开发且可能有 bug；在所审 commit 的 `package.json` 中有 lint、typecheck 和格式化脚本，未见应用测试脚本，源码树也未发现常规自动测试套件。
  来源：[README 定位与成熟度说明](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/README.md#for-who-is-this)、
  [package scripts](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/package.json#L5-L17)。

## 许可证边界

RapidRAW 使用 AGPL-3.0。默认把源码当作阅读和设计输入，不把其 TypeScript、Rust 或 WGSL 代码复制、改写后并入映见。
若未来确实要复用实现，应先明确映见的分发与源代码义务，并获得专业许可证意见或上游另行授权。
这不是法律意见。

来源：[RapidRAW LICENSE](https://github.com/CyberTimon/RapidRAW/blob/9d0f23c095d3dea1287987d35e3c81eb1323de45/LICENSE)。

## 建议的最小下一步

当前候选仍在最终真机与真人验收前，不建议新增功能。唯一适合并入下一批工程工作的项目是：

1. 先新增 geometry × mask × preview/export 的组合回归矩阵；
2. 在冻结候选上采集滑杆交互延迟、陈旧帧、峰值内存和温控；
3. 只有数据超门时，再开 ROI/分级分辨率预览 spike；
4. 组合蒙版和参数组选同步留到 MVP 接受后的 vNext Spec。
