# 传奇 iPhone 项目旧会话交接

整理日期：2026-10-20。依据当前可见历史和实际工作区整理，供新会话续接；不是完整逐字聊天导出。

## 2026-10-20 后续进展（优先于下方旧交接记录）

最新一轮：再接入 D613—D617 共 5 张地图，当前覆盖数 48、单向传送配置 228。新增 55 组刷怪、555 个配置数量，11 个怪物定义/掉落；143 个动画物件、840 个图集帧与原素材比对一致。详见 CENTIPEDE-DEPTHS.md、centipede-depths-validation.json 和 tools/check_centipede_depths.py。D618 在 75,77 引用 objects4 零起始索引 2478，当前为 empty_frame，暂不开放；D606 死亡棺材还受 D618 入口和“邪恶蜈蚣2”定义/掉落缺口阻塞。仍未提交、推送、打包、部署或真机测试。下面较早的 43/35 张地图记录仅作历史。

最新进展：在下面首段基础上再接入 D603、D604、D605、D608、D609、D610、D611、D612 共 8 张地图。当前覆盖数 43，新增 24 条传送配置、41 组刷怪，并恢复 D601 四组原先不可达的刷怪。新增地图 364 个动画物件、1,054 个图集帧与原资源比对一致。新增邪恶钳虫原掉落表。详见 CENTIPEDE-EXTENSION.md 和 centipede-extension-validation.json；验证脚本为 tools/check_centipede_extension.py，整条链可达性工具为 tools/centipede_reachability.py。仍未提交、推送、打包、部署或真机测试。下一段可盘点黑暗地带相邻 D613、D614、D616，先核对资源证据。

已收尾 F007 并接入蜈蚣洞 D601 ↔ D607 ↔ D602，连接盟重。当前地图覆盖数 35，新增 18 组刷怪、10 个怪物定义与对应掉落；两组弓箭护卫缺依赖、四组定点刷怪不可达，暂未接入。普通场景动画已支持，474 处物件、574 个图集帧完成原资源比对。详情与验证边界见 CENTIPEDE-CHAIN.md 和 centipede-chain-validation.json。上述更改仍未提交、推送、打包或部署。下文 32 张地图与待验证状态是此前交接快照，不再代表最新状态。

## 接续任务

继续补齐地图、怪物和掉落。从已开放地图之后继续，先盘点哪些原始地图、怪物动作或掉落表已有完整素材与配置，再优先补齐能可靠验证的一段地图链。先收尾沃玛圣地 F007 现有改动，再选择下一段。石墓四层先跳过。

## 路径和方向

- 仓库：D:\Mir2EquipmentWork\ios-equipment-demo
- 辅助脚本及审计：D:\Mir2EquipmentWork；这里还包含 OpenMir2。
- 旧会话资源与解码模块目录：C:\Users\xqjco\AppData\Roaming\CindyGlobal\owners\47bc27652391fef96ed9\dialogues\2026-10-05\02c3d2ab-35aa-4318-9e64-7f767a7bfd4d
- 目标：经典 1.76 联网玩法、服务端权威、iPhone 触控。地图缺图按坐标和原资源证据修复，保留原格式与来源审计。不以无依据替代素材冒充原图。
- 区分静态检查、本地协议/回放、模拟器和真机实测，不可混称。

## 已有提交与四层阻塞

最近提交：
- 28e3400b Add Stone Tomb third floor and verified drops
- 54c211f3 Add level test and Woma source audit
- 11a78106 Repair Menting map imagery and add verified monster frames

旧会话完成石墓三层 D713 原图、与二层双向连接，以及 63 组、12 种资源和掉落核对过的怪物。角蝇因可靠动作和掉落不足未加入。千年树妖动作和掉落已补齐，细节查仓库报告。

石墓四层 D714 有 4 个格子引用 Objects3 编号 9799。旧会话报告检查了本机 3 套资源及公开镜像旧/新版 Objects3.Lib，索引均只有 9,229 项，9799 越界；新版 D714 仍保留相同引用。用户要求先跳过四层。

用户曾要求推送当时改动，旧会话已核对远端为 28e3400b。本次本地 main 与 origin/main 跟踪状态一致，未再次联网检查。下面的 F007 改动尚未提交、推送。

## F007 当前落盘改动

- 沃玛圣地 F007：200×200，导出缺图 0，地面分块 169。
- 原地图 SHA-256：2cc39e7e51c84aa699d0c300bcb152773bcb9b6f61643306905fd5b153474679
- 原入口：D022 90,294 -> F007 98,138
- 新增返回：F007 99,138 -> D022 90,294
- 移除了当前实现不支持的 CHECKQUEST(Q010) 门槛，保留 NORECONNECT(D021) NORECALL DAY。这是已发生的玩法调整，应在交付中说明。
- 原 MonGen 的 11 组刷怪，配置总数量 230。包含暗黑战士、沃玛勇士、沃玛卫士、沃玛战士、沃玛战将、沃玛教主、火焰沃玛及部分后缀 0 变体。复用已有动作与掉落，哈希见报告。
- 覆盖统计 32/322，通用检查传送端点统计改为 188。
- 说明文件：WOMA-SACRED-LAND.md
- 证据文件：woma-sacred-land-validation.json、GameData/maps/F007/export-report.json、world-resource-coverage.json
- MapInfo.txt 与 MonGen.txt 按 gb18030 读取；Markdown/JSON 按 UTF-8，避免误改中文编码。

交接文件创建前 git status：
```text
## main...origin/main
 M ServerConfig/ClassicBichon/MapInfo.txt
 M ServerConfig/ClassicBichon/MonGen.txt
 M Sources/App/SceneData.swift
 M tools/check_stone_tomb_expansion.py
 M tools/check_world_assets.py
 M world-resource-coverage.json
?? GameData/maps/F007/
?? ServerConfig/ClassicBichon/Map/F007.map
?? WOMA-SACRED-LAND.md
?? tools/check_woma_sacred_land.py
?? woma-sacred-land-validation.json
```

## 下一步与验证边界

旧会话调用过下面检查，但可见历史没有全部退出结果；之后还把石墓检查的 installed 31 修正成 32。因此不能宣称最终全通过。本轮仅核对状态并写交接文件，没有重新测试、打包、提交、推送或真机测试。

新会话先读适用 AGENTS.md 与 git diff，保留已有未提交改动，然后执行：
```powershell
Set-Location D:\Mir2EquipmentWork\ios-equipment-demo
python tools/check_woma_sacred_land.py
python tools/check_world_assets.py
python tools/check_cave_expansion.py
python tools/check_woma_expansion.py
python tools/check_stone_tomb_expansion.py
python tools/check_veteran_maps.py
python tools/check_mengzhong_expansion.py
git diff --check
```

收尾 F007 后盘点下一段地图。目前没有可靠证据确认下一张应是哪张。选择原图、动作、掉落完整且与已开放区域连通的地图链；核对出入口可行走、刷怪点、客户端场景注册、地图哈希及掉落来源。

辅助脚本（先读源码确认路径与写入行为）：
- D:\Mir2EquipmentWork\audit-next-world.py
- D:\Mir2EquipmentWork\world-candidates.py
- D:\Mir2EquipmentWork\world-admission-check.py
- D:\Mir2EquipmentWork\inspect-next-monsters.py
- D:\Mir2EquipmentWork\export-next-world.py

导出用法为 python D:\Mir2EquipmentWork\export-next-world.py F007；F007 已导出，无需重复。脚本依赖旧会话目录下 decode_wzl_samples、safe_scene_render、validate_scene_resources、build_ios_demo，写入仓库 GameData。源图记录为旧目录下 Shanda Mir 2/Legend of mir/Map/F007.map。

## 最近指令顺序

1. 补 Objects3 9799、开放四层并推送。
2. 因缺图先跳过四层，推送当前改动；当时没有待推送改动。
3. 继续补齐地图、怪物和掉落，开展 F007。
4. 再次要求从已开放地图后盘点，优先补齐可靠验证的地图链。
5. 当前要求旧会话落成文件，新会话续做；本轮没有继续扩图。
