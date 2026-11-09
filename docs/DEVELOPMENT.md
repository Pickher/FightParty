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

新增 `Android Cloud Test` 预设，包名 `org.pickher.fightparty.cloudtest`、显示名称 `FightParty Test`、当前预设 versionCode 16 / versionName 0.3.1，可以与原包并存。原 Android 预设仍保留原包名。两者存档独立。

```bash
mkdir -p build
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_sim.gd
godot --headless --path . --export-debug 'Android Cloud Test' build/FightParty-0.3.1-cloud-test.apk
/home/agent/android-sdk/build-tools/36.0.0/apksigner verify --verbose build/FightParty-0.3.1-cloud-test.apk
/home/agent/android-sdk/build-tools/36.0.0/zipalign -c -P 16 4 build/FightParty-0.3.1-cloud-test.apk
```

产物在已忽略的 build 目录，不提交到源码仓库。安装只需要 APK，不需要旁边的 idsig 文件。此包保持 Mobile/Vulkan，最低 Android API 24 不等同于所有 Android 7.0 手机都能运行，仍需要实际设备验证。

以上命令用于重新构建当前源码；本轮未执行 0.3.1 导出，已有下载页仍为 0.1.4。

当前源码 0.4.0 / Android versionCode 17。本轮未导出 APK，旧战报与旧测试尺度不兼容；验证前先阅读 docs/WORLD_UNITS.md。

## 0.5.0 预留技能实现

本轮技能模块、兵种行为、状态和召唤时序，以 [ROSTER_SKILLS.md](ROSTER_SKILLS.md) 为准。新增实现未运行验证；旧文中的 stub 清单为历史状态。

当前导出版本 0.5.0 / Android versionCode 18，未生成 APK。

当前源码与导出预设为 0.6.0 / Android versionCode 19。技能组件化未执行运行验证，测试夹具中的状态写入须改用实例 state。见 docs/SKILL_COMPONENTS.md。

当前源码与导出预设更新为 0.7.0 / Android versionCode 20，未打包。新兵种优先配置公共属性与技能组合，参考 [UNIT_MODEL.md](UNIT_MODEL.md)。实例通过 sim.unit_model(unit) 取得，模板构造后只读使用；spawn_unit() 返回实例共享状态的兼容字典。按用户要求没有运行导入或测试。


当前地图改版为 0.7.1 / Android versionCode 21，未打包或运行验证。出生参数与参考距离见 WORLD_UNITS.md，新增地图参数集中在 data/rules.json，不要再改旧像素比例或旧 spawn_dx/spawn_dy。


当前源码为 0.7.2 / Android versionCode 22。坦克与特战队员参数变更见 WORLD_UNITS.md，未运行验证或打包。


当前源码为 0.7.3 / Android versionCode 23，坦克双模式武器参数见 WORLD_UNITS.md，复用接口见 SKILL_COMPONENTS.md；未运行验证或打包。

2026-11-08：新增当前兵种工作簿 data/units/兵种配置.xlsx（48 个单位），分为兵种属性、独立武器模式、技能参数。tools/unit_workbook.py 负责生成，新版 tools/import_units.py 默认导入此表，仍兼容历史格式。导入以隐藏的导出快照识别编辑，保留未编辑字段的远程变更并拒绝同字段冲突。没有更改游戏数值；按用户约定未运行导入校验、测试、模拟、Godot 导入或打包。


2026-11-08 0.7.4：医疗兵95生命；解放者架设65+30重甲；雷神按模式2/2/4段。引入武器 hit_count 并同步Excel，内部伤害类型保留；版本0.7.4，Android versionCode24。


2026-11-09：移除已停用的朋友 Windows 调试包工作流：tools/friend_package 的启动/编辑/导入脚本模板、专用操作说明和交付验证记录，以及 README 对应入口。保留当前 Excel 编辑及导入、兵种分页、游戏与技能框架；没有回退共享历史提交或改动游戏数值。未运行导入校验、Godot 导入、模拟、测试或打包。


## 2026-11-09 当前安卓测试构建

由 cloud/test 源码提交 `317600d` 构建 0.7.4（versionCode 24），使用现有 Godot 4.6.3 Android debug 模板、SDK 36.0.0 和项目外原测试签名。导出预设 Android Cloud Test，包名 `org.pickher.fightparty.cloudtest`，名称 FightParty Test；包含 arm64-v8a 与 x86_64，minSdk 24 / targetSdk 36，保持当前 Mobile/Vulkan 渲染。

产物：`build/FightParty-0.7.4-cloud-test.apk`，58,400,095 字节。
SHA-256：`d8eef78f483fbf000237859609a6e8f265bc7872a1c0df229f2928fbc7af2592`。

已完成资源导入/脚本解析、Android 导出、APK v2/v3 签名校验和 16 KiB 页对齐校验。没有运行对局模拟、战报重放或安卓真机/模拟器安装。导入/导出日志中的 ADB daemon 未连接不影响 APK 产物；aapt 旧版 badging 读取某些 required 属性报错，使用 aapt2 可读取包版本和架构。aapt2 另提示引擎模板引用的 themed_icon.xml 缺失，未将此视为真机通过。

新版私人下载页已发布：https://fightparty-apk-014.wangzeyu2495.chatgpt.site （网址保留旧版本命名，页面内为0.7.4），下载重组代码已校验 APK 的完整大小和 SHA-256。需要使用有权访问此页的 ChatGPT 账号；无需 GitHub 登录。安装包、签名和 SDK 不上传到游戏源码仓库。


2026-11-09：继续清理朋友调试流程遗留：删除根目录导入兵种.cmd及过期的data/兵种配置.xlsx；当前配置表只保留data/units/兵种配置.xlsx。同步README、表内填写说明和生成工具，导入入口改为python tools/import_units.py。旧导入器测试源码迁移到当前表格，避免依赖被删除的旧文件；按用户约定未运行导入校验、测试、模拟或打包。


## 2026-11-09 0.7.5

当前源码0.7.5、Android versionCode25；恶火4.5格开火/5格火焰；人族可建造防御塔1200HP及8+2独立驻军火力；Excel更新至49条。代码、表格和文档更新，未运行Godot导入、模拟、测试或打包；当前已发布APK仍0.7.4。


2026-11-09：源码更新为0.7.6 / Android versionCode26，大和舰行为通过独立mobile_attack组件配置，Excel已同步。按用户要求未增加索敌机制说明。未运行导入校验、Godot导入、模拟、测试或打包；下载页APK仍0.7.4。
