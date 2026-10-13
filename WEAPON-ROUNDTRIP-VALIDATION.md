# 编译修复与武器测试

## 编译修复

MirOfflineApp.swift 的左右、底部边距中，AppStorage 的 Double 与 GeometryReader 的 CGFloat 混用，造成除法重载歧义。现在统一转为 Double 计算，再将结果显式转回 CGFloat 传给 padding。三处一起修复。

本机为 Windows；语法解析、布局计算和 git diff --check 已通过，但没有执行 Xcode 类型检查。Mac 请 git pull --ff-only 后运行 bash validate-on-mac.sh。

## 实际联网测试（2026-10-12 21:26，America/Vancouver）

使用独立测试角色 WeaponCheck13，测试木剑 MakeIndex=2100010213。只为该测试角色的空背包格准备了一把木剑，没有修改玩家已有角色。没有重复发放或重跑已完成的操作。

| 操作 | 服务端结果 |
| --- | --- |
| 武器穿戴到槽位1 | SM_TAKEON_OK 615 |
| 穿戴中直接尝试丢弃 | SM_DROPITEM_FAIL 601，武器保留 |
| 卸下武器 | SM_TAKEOFF_OK 619，物品回包 |
| 从背包丢弃 | SM_DROPITEM_SUCCESS 600，同一物品编号 |
| 地面出现 | 坐标649,630 |
| 移动到物品坐标并拾取 | SM_ADDITEM 200，物品正文中的MakeIndex仍为2100010213 |
| 返回起点并重新登录 | 背包物品编号集合与测试前一致，装备栏为空 |

测试通过。最终测试木剑保留在专用角色背包中，角色返回648,629。注意 SM_ADDITEM 的包头 actor 是角色编号，验证物品身份使用的是物品正文中的 MakeIndex。

本次验证覆盖真实服务端协议与持久化，不等同于手机按钮、纸娃娃外观或触屏操作已通过真机验收。

手机操作：背包选中武器 → 穿戴；人物界面选中武器 → 卸下；背包再次选中武器 → 丢弃 → 确认。穿戴中的武器应先卸下。
