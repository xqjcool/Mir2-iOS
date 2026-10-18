# 资源与神水验证（2026-10-18）

## 神水
真实服务端测试发现两处问题并修复：属性重算末尾覆盖临时加成；计时到期仅清除标志但未重算或发送完整属性。补丁位于 ServerConfig/patches/godwater-recalculation.patch 和 godwater-expiration.patch。Windows Release 构建通过，0 错误、4 个已有警告。

四种神水均服用成功且扣除物品：道术 0→3→0，攻速 0→1→0，HP上限19→69→19，MP上限15→65→15。实际恢复约122/181秒，没有缩短服务端计时。详见 godwater-live-test.json。测试角色已恢复原位置，原木剑保留。服务器已重启加载修复。

## 千年树妖
补入 Crystal 013.Lib 的兼容经典树木：站立10帧、受击2帧、倒下10帧。不是声称恢复了原Mon15缺失本体动作。该树没有独立攻击动作，不复制站立帧伪造攻击资源。

按原PC客户端 ClMain.pas DrawEffectHum 接入 SM_716 类型0/1地刺，使用原Mon14 410–415共6帧，每帧120毫秒、正常透明混合。由服务端目标坐标触发；不改变伤害、目标选择或掉落。需要 iPhone 实机确认视觉效果，Windows侧仅完成语法与资源检查。

素材来源：https://mirfiles.com/resources/mir2/crystal/patch/Data/Monster/013.Lib

## 盟重
补入1335个原编号图片，缺图引用由2542处降至37处（22个不同编号）。同编号已存帧通过像素和几何核对；Objects4存在9个远处差异，补图限定在其附近128编号内没有差异且至少有10个相同参照帧的区段。地形、碰撞、门、出生点和传送均未改变。

来源：https://mirfiles.com/resources/mir2/crystal/patch/Data/Map/ShandaMir2/

补查Wemade Objects13虽有剩余9编号，但参照帧104处不一致、仅1处相同，未导入，避免错误拼图。剩余清单见mengzhong-image-repair.json。不能标记为缺图全部补齐或完整开放验收；此前已开放的测试入口未重复改动。
