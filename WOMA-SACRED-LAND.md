# 沃玛圣地地图开放

开放原版 F007 沃玛圣地地图，接通沃玛寺庙二层入口与返回路线，并加入原服务器 MonGen.txt 中的 11 组刷怪和对应 MonItems 掉落表。地图源文件 SHA-256 为 2cc39e7e51c84aa699d0c300bcb152773bcb9b6f61643306905fd5b153474679；导出检查没有缺失图像引用。

F007 原 MapInfo 入口为 D022 90,294 -> F007 98,138，两个端点均可行走。原配置没有返回传送点，因此在相邻的 F007 99,138 增加回到 D022 90,294 的路线。原地图的 CHECKQUEST(Q010) 要求已不随当前离线服务器实现的任务，开放时移除此门槛，保留 NORECONNECT(D021) NORECALL DAY。

运行 python tools/check_woma_sacred_land.py 与 python tools/check_world_assets.py 检查地图文件、入口坐标、场景纹理、刷怪动作和掉落文件哈希。
