# 开发、测试与打包

各版本的构建与“未运行验证”记录见 [历史归档](archive/DEVELOPMENT_HISTORY.md)。

## 环境

- **Godot**：用户本机为 4.7.2 标准版；云端验证使用 4.6.3（`Godot_v4.6.3-stable_linux.x86_64`）。导出需要对应版本的导出模板。首次打开或命令行导入会重建 `.godot` 缓存。
- **Python 3.8+**：只用于工具与测试（Excel 导入、兵种总表、导入器测试），游戏运行不需要。导入器只用标准库；重新生成 Excel 需要 `openpyxl`，重新裁剪字体需要 `fonttools`。
- **Android**：JDK 21、Android SDK Build Tools 36.0.0；在 Godot 编辑器设置中配置 Java SDK、Android SDK 和调试 keystore，无需 Gradle 自定义构建。导出产生 minSdk 24、targetSdk 36，含 arm64-v8a 与 x86_64。
- **渲染器**：Windows 使用 Compatibility；Android 使用 Mobile/Vulkan（`rendering_method.mobile="mobile"`）。最低 API 24 不代表所有 Android 7 设备都能运行，需要支持 Vulkan 的真机验证。

## 一条命令运行全部检查

Windows（PowerShell）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot 'C:\路径\Godot_v4.7.2-stable_win64_console.exe'
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot 'C:\路径\Godot_v4.7.2-stable_win64_console.exe' -Perf
```

Linux / macOS：

```bash
GODOT=/path/to/godot tools/check.sh
GODOT=/path/to/godot tools/check.sh --perf
```

Godot 请用**控制台版** exe，否则看不到输出。也可以先设置环境变量 `GODOT`（以及可选的 `PYTHON`）。脚本依次运行下表各项，每项有超时，日志写到 `build/check-logs/<名称>.log`，最后打印汇总；任一项失败时退出码为 1，并列出失败项。退出码非零、日志出现 `SCRIPT ERROR`，或出现以 `FAIL`/`UI FAIL` 开头的行，都算失败。

| 名称 | 内容 | 通过标志 |
| --- | --- | --- |
| `import` | `--editor --import --quit` 导入资源、解析全部脚本 | 无脚本错误 |
| `test_sim` | `tests/test_sim.gd` 规则模拟测试 | `RESULT N checks, 0 failures` |
| `unit_editor` | `tests/test_unit_editor.gd` 兵种卡片、翻页与简介 | `Unit editor failures: 0` |
| `ui_smoke` | `tests/ui_smoke.gd` 真实主场景程序化操作与完整对局 | `UI SMOKE: PASS` |
| `replay` | `tests/replay.gd` 重放 ui_smoke 刚写出的战报 | `REPLAY: PASS` |
| `importer` | `python -m unittest discover -s tests -p 'test_*.py'` Excel 导入器测试 | `OK` |
| `unit_table` | `python tools/unit_table.py --check` 兵种总表与数据同步 | 一致 |
| `crowd_perf`（`-Perf`） | 满兵营纯模拟基准，默认 3 波 | 只输出数据 |
| `render_perf`（`-Perf`） | 打开渲染窗口采样 10 秒帧率 | 只输出数据 |

注意：`ui_smoke` 会覆盖本机 `user://` 下的最近阵容（`settings.cfg`）与战报（`last_match.json`）；需要保留时先备份。Windows 的 `user://` 通常在 `%APPDATA%\Godot\app_userdata\FightParty`。`check.ps1` 尚未在 Windows 上实际运行过，首次使用若有问题请反馈。

## 单项运行

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_sim.gd
godot --headless --path . --script res://tests/test_unit_editor.gd
godot --headless --path . --script res://tests/ui_smoke.gd -- --capture=/tmp/fightparty.png
godot --headless --path . --script res://tests/replay.gd -- /path/to/last_match.json
godot --headless --path . --script res://tests/crowd_perf.gd -- --waves=3
godot --path . --script res://tests/render_perf.gd
python tools/import_units.py --check
python tools/unit_table.py --check
```

- `test_sim.gd`：约 840 项检查，覆盖买卖退款与多资源、无效输入、波次与 64 波结束规则、安全时限、永久兵营、同时击杀与同时基地摧毁、基地防御层、宝库与灵核、防御塔选址与种族塔、周期经济/中央井/气厂/兑换、护甲/护盾/溅射/多段、攻击模式与投送、各技能组件、召唤物、种族与公开、电脑购买与建塔、镜像公平、确定性、战报重放、空间查询等价与等预算克制。运行时脚本错误也计为失败。约 1 分钟。
- `ui_smoke.gd`：通过真实主场景验证开局设置与自定义值、种族选择与商店过滤、多兵种放置/移动/删除与翻页、暂停与后台通知、首次交战公开、已出场单位取消确认与不退款、点选建塔、完整对局（缩短为 3 波）、结算与重开、按种族保存兵营；有显示服务时输出截图，无界面时跳过截图。它用程序调用界面动作，不代替实机触摸验证。
- `replay.gd` 默认读取最近一局战报；规则版本不一致或未完成的日志会拒绝。
- `render_perf.gd` 需要真实显示环境才能代表画面帧率；headless 下的数字只说明脚本能运行。

## 修改兵种数值后

1. 改 `data/units.json`，或改 Excel 后运行 `python tools/import_units.py`（见 README 第十三节）。
2. 运行 `python tools/unit_table.py` 重新生成 [兵种数值总表](UNIT_TABLE.md)。
3. 运行一键检查。平衡调整可能让克制测试失败：先判断是否属于预期变化，再更新测试预期，不要直接删除测试。
4. 价格变化后检查 `races.json` 的默认阵容是否仍买得起（`test_sim` 会打印 WARN）。

## 构建

```powershell
./tools/build.ps1 -Godot 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
./tools/build.ps1 -Godot '...' -SkipAndroid
```

脚本导入资源、运行 `test_sim.gd`，再生成 Windows EXE、ZIP 和 Android 调试 APK；`-OutputDirectory` 可指定输出目录。打包前建议先跑一键检查。也可以直接导出：

```bash
godot --headless --path . --export-release 'Windows Desktop' build/windows/FightParty.exe
godot --headless --path . --export-debug Android build/FightParty-android-test.apk
godot --headless --path . --export-debug 'Android Cloud Test' build/FightParty-cloud-test.apk
```

导出预设：`Windows Desktop`；`Android`（包名 `org.pickher.fightparty`）；`Android Cloud Test`（包名 `org.pickher.fightparty.cloudtest`，显示名 FightParty Test，可与原包并存）。当前两个 Android 预设均为 versionName 0.13.0 / versionCode 47。签名 keystore 只保存在本机或云端编辑器设置中，绝不提交；同包名升级必须使用同一签名。产物放在已忽略的 `build/` 目录。

最近一次实际构建并发布的测试 APK 是 0.7.4（versionCode 24），之后的源码改动没有重新打包；手机上的安装包不会随源码更新。

## 字体与许可

`assets/NotoSansSC.ttf` 是 Noto Sans SC 变量字体 wght=500 的静态子集，覆盖 scripts、data、tests 中出现的文字与基本 ASCII。新增界面中文后，下载 Google Fonts 的原始 `NotoSansSC[wght].ttf`，在装有 fonttools 的环境运行：

```bash
python tools/subset_font.py /path/to/NotoSansSC-original.ttf
```

字体来源 https://github.com/google/fonts/tree/main/ofl/notosanssc ，许可证在 `assets/OFL.txt`；Godot MIT 声明在 `assets/GODOT-LICENSE.txt`（另见 https://godotengine.org/license/ ）。
