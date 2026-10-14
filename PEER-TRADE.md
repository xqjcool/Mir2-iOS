# 查看玩家装备与面对面交易

## 手机操作

1. 点击视野中的另一名玩家，打开玩家操作面板。
2. 点“查看装备”，读取服务端返回的装备、属性和持久。只查看，不修改自己的背包。
3. 交易时先走到相邻一格；双方分别点击对方，再点“面向对方”。其中一人点“发起交易”。
4. 在交易面板点背包物品放入，输入金币后点“放入”。双方核对物品属性及金币，再分别点“核对并确认”。内容刚变化时需等待 3 秒。
5. 可点“取消交易”整体退回。当前服务端禁止从交易栏单独取回物品；修改报价时取消后重开。

仅未穿戴的背包物品可以放入交易。交易期间停止移动、攻击和装备操作。超时的物品操作会断开连接，重登以服务端状态为准。对方离开或目标失效会提示重新选择。

## 更新

Mac 在仓库目录执行 `git pull --ff-only`，然后用 Xcode 编译运行。本次无需更换 GameData。

服务端附带 `ServerConfig/peer-target-validation.patch`：检查查询对象类型，并校验指定交易对象和实际面向对象是否一致。协议仍使用原有 82/751 与 1025—1030 消息。

Windows 已编译补丁位于 `D:\OpenMir2Test\updates\peer\M2Server.dll`。现有服务以管理员权限运行，普通权限会话无法替换已加载的 DLL，因此尚未部署此加固补丁。在管理员 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\OpenMir2Test\install-peer-update.ps1"
```

脚本备份 DLL、停止该目录的游戏服务、安装补丁并重新启动；不停止 MySQL。

## 验证边界

Windows 环境没有 Xcode。Swift 语法解析通过并不代表 iOS 编译和真机触控验收完成。`Tests/PeerInspectionTests.swift` 使用真实 1688 字节装备回包，覆盖装备槽位及损坏长度；需在 Mac 运行 Swift 测试。

?????????????????????????????? 100 ?????????????????????????????????? `peer-network-validation.json`???????????????????????????
