# 开发与打包

## 环境

已验证 Godot 4.7.2.stable.official.ed1daf0bf 标准版，使用对应 4.7.2.stable 导出模板。Python 不参与游戏运行；仅重新生成字体子集时需要 fonttools。运行 Godot 导入工程即可重建 `.godot` 缓存。

Android 构建环境：JDK 21.0.10、Android SDK Build Tools 36.0.0。Godot 的编辑器设置中配置 Java SDK、Android SDK 和调试 keystore。APK 原生打包不需要启用 Gradle 自定义构建。导出模板产生 minSdk 24、targetSdk 36；用户安装测试包时按操作系统提示允许对应来源安装。

项目设置开启 ETC2/ASTC 导入以支持 Android 导出。Windows 使用 S3TC/BPTC。无 3D 模型或大纹理依赖，不使用动态灯光。所有项目路径均为 res:// 或 user://；仓库不保存本机 SDK 路径。

渲染器适配：Windows 保持 Compatibility；Android 用 `rendering/renderer/rendering_method.mobile="mobile"` 选择 Mobile/Vulkan。初版模拟器的 GLES 后端在 Godot 4.7.2 上报 `GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)` 着色器链接错误，故调整 Android 渲染器。APK 的 minSdk 不能单独代表 GPU 兼容性，需要支持 Mobile 渲染器的 Vulkan 设备。不要将模拟器图形后端的问题误记为已验证的所有真机问题。

## 构建

先在 Godot 中安装相同版本的导出模板；配置好 SDK 后执行：

```powershell
./tools/build.ps1 -Godot 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
```

脚本导入资源、运行模拟测试，然后生成 Windows EXE、ZIP 和 Android 调试 APK。可使用 `-SkipAndroid` 只构建 Windows，或用 `-OutputDirectory` 指定输出目录。

也可直接运行：

```powershell
godot --headless --path . --export-release 'Windows Desktop' build/windows/FightParty.exe
godot --headless --path . --export-debug Android build/FightParty-android-test.apk
```

提前创建输出目录。Android 安装包包含 arm64-v8a 与 x86_64，后者用于模拟器。密钥只在本机生成和保存，绝不上传仓库。正式发行需要另行准备发布签名；此项目不包含商店发布流程。

Windows 将 PCK 嵌入 EXE，无需引擎安装。发行模板本身约 104 MiB，因此原型 EXE 不等同于源码体积；ZIP 和 APK 的实测体积以交付文件为准。

## 测试与复现

`test_sim.gd` 覆盖矿物与买卖退款、无效输入、波次边界、永久兵营重生、残兵、可选寿命、同时击杀、同时基地摧毁、64 波结束规则与安全时限、操作日志重放、AI 增量购买、镜像对局、确定性及等预算克制。失败时退出码非零。

`ui_smoke.gd` 通过真实主场景验证放置、移动、删除、暂停、后台通知、完整对局、结果和重开，并输出战场与结算截图。它使用程序调用界面动作，并不替代实机手指操作验证。截图路径可指定：

```powershell
godot --path . --script res://tests/ui_smoke.gd -- --capture=C:/Temp/fightparty.png
```

`render_perf.gd` 在真实渲染窗口里生成 200 个高生命单位，采样 10 秒实际帧数，同时运行 20 Hz 模拟。`test_sim.gd` 还分别测量纯模拟耗时，两者不能混为一谈。

`crowd_perf.gd` 是 18×8 满兵营的纯模拟基准：双方由 AI 各买满 144 格、连续出兵，输出每步平均/最慢耗时和峰值单位数。默认 8 波，可用 `-- --waves=12` 调整：

```powershell
godot --headless --path . --script res://tests/crowd_perf.gd -- --waves=12
```

`replay.gd` 默认读取最近完成的对局，也可以显式指定 JSON 路径：

```powershell
godot --headless --path . --script res://tests/replay.gd -- C:/Temp/last_match.json
```

规则版本不一致或未完成的日志会拒绝重放。输入文件属于本地开发工具，不是网络接口。测试保存的位置与实际游戏一致，运行测试前请自行保留需要的个人战报。

## 字体与许可

`assets/NotoSansSC.ttf` 是 Noto Sans SC 变量字体的 wght=500 静态 UI 子集，覆盖 scripts/data/tests 中的文本与基本 ASCII。增加中文提示后，下载 Google Fonts 仓库的原始 NotoSansSC[wght].ttf，在安装 fonttools 的 Python 环境运行：

```powershell
python tools/subset_font.py C:/Temp/NotoSansSC-original.ttf
```

原字体来源：https://github.com/google/fonts/tree/main/ofl/notosanssc 。许可证位于 `assets/OFL.txt`。Godot MIT 声明位于 `assets/GODOT-LICENSE.txt`，同时保留 https://godotengine.org/license/ 的引用以查看引擎第三方组件声明。

## 云端安卓测试包（2026-11-03）

当前云端使用 Godot 4.6.3.stable.official.7d41c59c4 及匹配的 4.6.3.stable Android debug 模板、OpenJDK 21、Android SDK Build Tools 36.0.0、platforms;android-36 和 platform-tools。Android SDK 位于 `/home/agent/android-sdk`，Java SDK 位于 `/usr/lib/jvm/java-21-openjdk-amd64`；路径通过云端 Godot 编辑器设置配置，不写入项目导出预设。

本机生成的开发测试签名保存在项目外的 Godot keystores 目录，不能提交到仓库。后续生成同包名更新包应继续使用同一签名；云端环境重建前需妥善保存签名才能保留升级兼容性。

新增 `Android Cloud Test` 预设，包名 `org.pickher.fightparty.cloudtest`、显示名称 `FightParty Test`、当前预设 versionCode 14 / versionName 0.2.3，可以与原包并存。原 Android 预设仍保留原包名。两者存档独立。

```bash
mkdir -p build
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_sim.gd
godot --headless --path . --export-debug 'Android Cloud Test' build/FightParty-0.2.3-cloud-test.apk
/home/agent/android-sdk/build-tools/36.0.0/apksigner verify --verbose build/FightParty-0.2.3-cloud-test.apk
/home/agent/android-sdk/build-tools/36.0.0/zipalign -c -P 16 4 build/FightParty-0.2.3-cloud-test.apk
```

产物在已忽略的 build 目录，不提交到源码仓库。安装只需要 APK，不需要旁边的 idsig 文件。此包保持 Mobile/Vulkan，最低 Android API 24 不等同于所有 Android 7.0 手机都能运行，仍需要实际设备验证。

以上命令用于重新构建当前源码；本轮未执行 0.2.3 导出，已有下载页仍为 0.1.4。
