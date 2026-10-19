# GM 权限修复与使用（2026-10-19）

当前服务端已恢复角色名授权，最终 adminlist.txt 只有：

```text
* C176Alpha *
```

三列依次为权限标记、角色名、允许登录的来源 IP。第一列 `*` 表示权限 10；第三列 `*` 允许该角色从任意 IP 登录，并不授权其他角色。也可以把第三列改为固定 IP 或 `192.168.1.*`。保存后重启服务端并重新登录角色。

当前文件：`D:\OpenMir2Test\GameSrv\Envir\adminlist.txt`。使用角色名而不是账号名。

登录 C176Alpha，在“当前”聊天频道发送：

```text
@Make 木剑 1
@Make 鹤嘴锄 1
```

物品名称必须与服务端数据库一致，背包必须有空位。鹤嘴锄仍要求角色达到 15 级才能装备。不要在行会或私聊频道输入 GM 命令。

## 修复范围

- 恢复登录阶段的 GM 权限赋值，并校验授权角色的来源 IP。
- 修复单字符 `*` IP 匹配越界，支持固定 IP、IPv4 通配符、IPv4-mapped IPv6。
- 删除 DEBUG 构建给所有玩家权限 10 的代码。
- Command.conf 恢复 `Make=Make`；保留 `MakeMin=10`、`MakeMax=10`。
- 不改变普通玩家默认权限。

## 验证

M2Server Release 构建成功（4 个既有警告），CommandSystem Release 构建成功。实际 IP 匹配方法通过 10 个输入测试。
测试角色临时精确授权后 @Make 木剑 1 收到一件物品入包；普通测试角色未收到物品。临时授权已删除并重新登录验证权限已撤销，测试生成的唯一 MakeIndex 物品已从测试背包清理。
最终日志：`D:\OpenMir2Test\logs\iphone-20261019-082721`。原始 DLL、adminlist 与 Command.conf 备份在 `D:\OpenMir2Test\config-backups\gm-20261019`。

重启：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\OpenMir2Test\restart-server.ps1
```

## 盟重资源

仍有 22 个编号、37 处引用缺图，未达到“全部补齐后开放”的条件。此次补查 Mirfiles Data 与 1000YearMir 归档，并下载检查 1000Year 3&4 Maps.rar；里面没有 3.map，也没有图片库，不能用来补这 22 个编号。先前多个 Shanda 图片库为空槽、其他版本邻接图不一致的审计结论保留。没有用透明占位或不匹配图片冒充补齐。

来源：https://mirfiles.com/resources/mir2/clients/1000YearMir/
详见 MENGZHONG-REMAINING-AUDIT.md 和 mengzhong-remaining-indices.csv。
