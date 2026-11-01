# FightParty

公平配兵、波次出兵、残兵推进的原创 2D 自动战斗游戏。**Windows + Android 离线人机原型 v0.1.0**，Godot **4.7.2 标准版 / GDScript**。Windows 使用 Compatibility，Android 使用 Mobile/Vulkan。

玩家不能直接指挥战场单位，只能观察敌军、调整下一波兵种与站位。双方使用相同预算和兵种池：600 起步，每波 +100，上限 1200，无击杀收入。每 30 秒同时出兵，残兵保留，摧毁基地获胜。

## 开始游戏

- Windows：解压交付的 `FightParty-Windows.zip`，双击 `FightParty.exe`。
- Android：安装交付的 `FightParty-android-test.apk`，支持 arm64-v8a / x86_64，最低 Android 7.0，设备还需支持 Godot Mobile 的 Vulkan 渲染要求。它是调试签名的测试包，不是商店发行版。
- 源码：使用 Godot 4.7.2 导入本仓库 `project.godot`，按 F6/F5 运行主场景。无需 Python、数据库、服务器或第三方 Godot 插件。

首次进入先配兵，再点右上角“开始准备”。选择兵种后点击网格放置或替换，右列是前排；使用“移动位置”交换站位，使用“移除单位”删除。空格键暂停，Esc 查看规则。界面变化只影响下一波。

## 已实现

六种原创兵种、护甲与范围伤害、6×4 网格、前后排站位、同步出兵、90 秒残兵寿命、公平 AI、基地结算、8 分钟限时、音量与阵容保存、波次战报、中文触摸界面、Android 后台暂停，以及无界面的规则测试和战报复现。

首版未包含真人联机、账号、匹配、空军、复杂地形、美术成品或应用商店发布。Android 实际兼容性和验证范围见测试报告。

## 文档

- [玩法与兵种初始数值](docs/DESIGN.md)
- [架构、接口、数据流和未来联机边界](docs/ARCHITECTURE.md)
- [运行、测试、打包与许可证](docs/DEVELOPMENT.md)
- [实际测试记录与限制](docs/TEST_REPORT.md)

源码和文档保存在 Git 历史。Windows 压缩包、APK 和预览图作为独立交付文件提供，不提交引擎、SDK、构建产物或签名密钥。

## 测试

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_sim.gd
godot --path . --script res://tests/ui_smoke.gd
godot --headless --path . --script res://tests/replay.gd
godot --path . --script res://tests/render_perf.gd
```

Windows Godot 可执行文件名可能带版本号，请替换上述 `godot`。UI 冒烟测试会写入本应用的用户设置和最近战报，建议在独立测试环境运行。

## 第三方声明

使用 [Godot Engine](https://godotengine.org/license/)（MIT）。中文 UI 使用 Google Noto Sans SC 的 500 字重子集（SIL OFL 1.1），许可证随源码和安装包附带。单位形状、图标和短提示音由项目代码生成。未使用《星际争霸》素材、角色或商标作为游戏内容。
