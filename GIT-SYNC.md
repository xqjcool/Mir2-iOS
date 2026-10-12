# Windows 与 Mac 同步工程

仓库包含当前 iOS 源码、Xcode 工程、测试和 GameData 资源，无需 Git LFS。
首次克隆需要下载资源；以后 Git 只同步变更。请使用有访问权限的私有仓库保存项目和现有游戏资源。

## Mac 首次使用

将下面的 `REMOTE_URL` 替换为远程仓库地址，在希望存放工程的目录执行：

```bash
git clone REMOTE_URL MirOnline
cd MirOnline
open MirOffline.xcodeproj
```

选择自己的 Development Team 和 iPhone 后运行。旧的解压版可继续保留，后续使用新克隆的工程。

## 后续同步

关闭 Xcode 中正在编辑的文件，在仓库目录运行：

```bash
git status
git pull --ff-only
open MirOffline.xcodeproj
```

如果 Mac 有未提交的代码或 Team 配置修改，先保留这些修改再合并；不要使用强制覆盖命令。可将代码提交到自己的分支，或使用 Git 的 stash 保存后再恢复。

## Mac 验证

```bash
bash validate-on-mac.sh
```

脚本运行 Swift 测试和无签名模拟器构建。仓库中的 Windows 检查记录不代表 Xcode 编译、真机技能或性能测试已经通过。

## Windows 提交与推送

工作目录为 `D:\Mir2EquipmentWork\ios-equipment-demo`：

```powershell
git status
git add Sources Tests README.md
git commit -m "Describe the change"
git push origin main
```

修改资源时也要加入相关 GameData 文件。构建产物、日志、证书和本地凭据不应加入版本控制。
