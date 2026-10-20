# 盟重地图图像引用修复与来源核验（2026-10-19）

## 当前结论

地图 3 原有 21 个无效图像编号、32 处引用。按同尺寸参考地图逐坐标核验后，已清除 17 处无来源的图层引用，并将 2 处改到像素完全匹配的本地 Objects 5656 与 Tiles 2302；修复地图只改 19 个图像位置、共 39 字节，门、动画、区域、光照和行走字段均未变。剩余 13 个 Objects 0–3 是 1×1 空帧占位，不产生可见图像；5 个 raw 0x8000 仍作为无图像标记。当前可见缺图引用为 0。逐坐标操作、提交版本和 SHA256 见 mengzhong-image-reference-patch.json。

残留项已逐格复核：13 个占位格在参考地图中的前 12 字节保持一致，且每格都有动画字段；5 个中层 0x8000 掩码后没有图像，但参考地图把相同高位编码放在前层，高位在前层有不同的遮罩用途。因此它们可以从绘制资源清单中排除，不应清零原始地图记录。完整字节与字段证据见 mengzhong-residual-noimage-audit.json。

## 字段规则

- 地图头为 52 字节，单元按 x * height + y 排列。经典 12 字节格保存 back/middle/front 三个小端 UInt16，之后为门、动画、区域与光照字段。
- 14 字节格在末尾增加 btBkIndex 和 btSmIndex：back 选择器加 100 选择 Tiles 组，middle 选择器加 110 选择 SmTiles 组，area 加 120 选择 Objects 组。图号以 1 为起点，绘制索引需减 1；middle/front 按 0x7fff 掩码后为 0 时不绘制。
- 36 字节新格式另有 btTiles2、btSmTiles2 等字段，不可套用 14 字节格的选择器规则。
- 字段依据是 MapCode.cs 的公开源码，逐格字节证据见 mengzhong-field-rules-validation.json。

## 新增素材候选核验

- 继续检查本地经典 WIL/WIX 素材组 classic-monsters/Data。其中 Objects.wil 的索引 0–3 与 Tiles.wil 的 3868 都是 1×1 单像素哨兵记录，不是可用地图图块；SmTiles.wil 只有 938 帧，缺失的 3891、3895、3896、3902、3903、3924、7310 均越界。该素材组没有 Objects13.wil，不能补 9 个 Objects13 引用。帧数、SHA256、坐标和索引记录见 mengzhong-wil-donor-audit.json。
- 配套旧版 Crystal/WZL 库中，Objects 0–3、Objects13 的 1172–1174/1192–1194/1212–1214 和 Tiles 3868 是空记录；基础 SmTiles 也没有上述 7 个高编号。
- 同尺寸 12 字节候选地图与当前 14 字节地图在全部 800,000 格的前 12 字节完全相同，证明两份地图保留了相同原始图像引用；旧格式没有选择器，也不包含替代图像库。候选文件 SHA256 为 1f82b44e0971a3e1d752b95da1f18dc9216ba20a104bac13f6d49f9e9c6fd138。
- Shanda/Wemade 公共对象包没有随附与本地图选择器、邻接编号相匹配的 Data 清单；同编号的 SmTiles3/4 图像与地图周边也不完全一致。《The sec of Legend》的 36 字节地图与当前地图的缺图坐标/选择器不同。Crystal 后续同名 3.map 是 15 字节格式且相关图层有清空，只能参考，不能直接替换或拼接。
- 上述 WIL/WZL 候选没有被当作替代资源导入。之后找到同尺寸地图提交 754d5f271e25272d367d984cc49dea93fac2bed4，并只把它作为坐标级引用证据：保持原 14 字节地图格式与本地帧库，修复 19 处图像引用。剩余 13 个透明占位坐标见 mengzhong-remaining-indices.csv。

## 开放状态与树妖

盟重地图已在客户端地图列表中，跨图验证记录见 MENGZHONG-VALIDATION.md。本轮补丁更新了客户端地面分块与场景前景对象，并保留引用来源审计；未调整服务端入口配置。地图 3 的可见缺图已清零，但本结论仅针对这些已核验坐标，不代表其他地图资源或 NPC 已全部补齐。

树妖线上动作资源已恢复到原始帧序列：待机 360–363、攻击 370–375、受击 380–381、死亡 390–409；运行时 actor key 为 34-141，地刺特效为 Mon14 410–415。资源及数据包动作分派检查通过，服务端伤害与掉落未改。iPhone 真机动作速度、偏移和地刺位置仍待设备验收，详见 OCT18-TREE-HUD-ACCEPTANCE.md。

## 验证范围

python tools/check_mengzhong_expansion.py、python tools/check_mengzhong_image_repairs.py、python tools/check_remaining_actors.py 和 git diff --check 均通过。本次未进行 Xcode 编译或 iPhone 真机验收。
