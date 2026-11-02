# FightParty 新手使用与修改指南

本机工程目录：D:\MyCode\FightParty

桌面的“FightParty指导.txt”是这份 README 的相同内容副本。以后修改 README 后，桌面副本不会自动更新，需要重新复制。

FightParty 是公平配兵、按波次出兵、残兵推进的原创自动战斗游戏。目前为 Windows + Android 离线人机原型 v0.1.0，使用 Godot 4.7.2 标准版和 GDScript。

## 一、双击桌面快捷方式开始游戏

双击桌面的“FightParty开始游戏”快捷方式即可启动。

这个快捷方式用 Godot 直接运行 D:\MyCode\FightParty 的项目源码，不是运行之前导出的旧 EXE。你修改文件并保存后，关闭游戏，再双击快捷方式，就会使用修改后的内容。

快捷方式指向本机的 Godot 程序：

```text
C:\Users\ASUS\Documents\Codex\2026-11-01\2\work\tools\godot\Godot_v4.7.2-stable_win64.exe
```

启动参数：

```text
--path "D:\MyCode\FightParty"
```

请保留 Godot 目录和项目目录。若以后移动它们，在快捷方式上右键 → 属性，更新程序路径、--path 后的项目路径，以及“起始位置”。

## 二、游戏打开后怎么玩

1. 看下方兵种卡片的价格、定位与克制提示。
2. 点兵种卡片，再点左下方网格，放置或替换单位。右边是前排，左边是后排。
3. “移除单位”：先点工具，再点要移除的单位。
4. “移动位置”：先点来源格，再点目标格；目标已占用时交换位置。
5. “清空阵容”清空下一波配置，也允许不派兵。
6. 点右上角“开始准备”，30 秒后双方同时出兵，之后每 30 秒出下一波。
7. 战斗时仍可配置下一波；不能直接指挥已经在场的部队。
8. 根据右下角敌方上一波阵容调整组合；AI 也只能参考你上一波的公开配置。

双方首波预算都是 600，每波加 100，上限 1200；剩余不结转，击杀不加钱，调整待出兵阵容不收额外费用。残兵继续推进，出生 90 秒后撤离。摧毁基地获胜；8 分钟后比较基地剩余生命，相同为平局。

空格键开始/暂停/继续；Esc 打开或关闭玩法说明。查看说明时计时暂停。结算后点击“调整阵容，再来一局”。

## 三、想改代码：在 Godot 编辑器里打开工程

1. 双击上文的 Godot_v4.7.2-stable_win64.exe，进入项目管理器。
2. 点击“导入”，选择 D:\MyCode\FightParty\project.godot。
3. 打开工程，等待首次资源扫描和导入完成。
4. 在左侧“文件系统”展开 scripts，双击 .gd 文件，即可在内置编辑器中阅读和修改。
5. 按 Ctrl+S 保存，再按 F5 运行整个项目。
6. 测试完关闭游戏窗口；若仍在调试，可按 F8 停止，再继续修改。

F5 运行整个工程，F6 只运行当前场景。初学时统一使用 F5。

JSON 数值文件可以用记事本等文本编辑器打开。如果 Godot 没有在内置编辑器打开 JSON，就从资源管理器右键文件，选择“打开方式 → 记事本”。保存时保持 UTF-8 编码和 .json 后缀。

当前 UI 由代码直接绘制，场景树里不会出现每张卡片各自的 Button 节点。修改卡片位置、颜色或提示文字，主要看 scripts/main.gd；修改战斗规则，主要看 scripts/battle_sim.gd。

## 四、需要哪些软件与环境

- 修改和在电脑运行：Godot 4.7.2 标准版即可，本机已经准备好。不需要 Python、.NET SDK、C++ 编译器、数据库或服务器。
- 保存版本和同步 GitHub：Git，本机已经安装，工程也已关联远程仓库。
- 导出独立 Windows EXE：需要 4.7.2 对应导出模板。只按 F5 运行源码时不用导出模板。
- 导出 Android APK：需要对应导出模板、Java JDK、Android SDK。本机此前用 JDK 21.0.10 和 Android Build Tools 36.0.0 成功构建，也已有 Android Studio。
- Python 只用于可选的字体维护工具 tools/subset_font.py，不是游戏运行环境。

Godot 的“编辑器 → 管理导出模板”用于安装模板；“编辑器 → 编辑器设置 → 导出 → Android”中填写 Java SDK Path 和 Android SDK Path。本机 Android SDK 位于 C:\Users\ASUS\AppData\Local\Android\Sdk。

Windows 使用 Compatibility；安卓测试包使用 Mobile/Vulkan。安卓已通过构建和签名检查，但最终包的实际运行、触摸、后台恢复和真机帧率尚未验证，不是已发布的手机成品。详细情况见 docs/TEST_REPORT.md。

## 五、先认识文件和基本语法

- .gd：GDScript，Godot 的脚本语言，缩进风格像 Python，但不是 Python。
- .tscn：场景文件，描述节点关系和绑定的脚本。
- .json：配置数据；JSON 不允许直接写 # 或 // 注释，因此字段解释放在下文。
- project.godot：项目入口和设置，包括主场景、窗口、渲染器。
- .ps1：PowerShell 打包脚本；.py：可选的 Python 字体维护脚本。
- .godot 目录：自动生成的导入缓存，不是主要学习对象，不提交到 Git。

GDScript 中 var 定义变量，const 定义常量，func 定义函数，if 判断条件，for 遍历，return 返回结果。Array 是数组，Dictionary 是键值对字典，Vector2 是二维坐标。

以 # 或 ## 开头的行是注释，不参与执行。本次已经给主要脚本、测试和工具添加中文导读、函数说明与关键流程注释。

缩进决定代码属于哪个函数或条件，请保持原缩进，避免混用 Tab 和空格。res:// 表示工程目录，user:// 表示玩家数据目录。

## 六、建议按这个顺序研究项目

以下路径都相对于 D:\MyCode\FightParty：

1. data/units.json：兵种价格、血量、伤害、射程，最适合第一次修改。
2. data/rules.json：出兵间隔、预算、基地血量与对局时限。
3. scripts/catalog.gd：读取配置，以及定义默认开局阵容。
4. scripts/commander_ai.gd：电脑怎样根据上一波选择反制兵种。
5. scripts/battle_sim.gd：配兵校验、生成单位、自动寻敌、移动、扣血和胜负。
6. scripts/main.gd：入口、界面、按钮操作、每帧调度和存档。
7. scenes/main.tscn：绑定 main.gd 的主场景，是 F5 启动的画面。
8. tests：规则、界面、重放和性能测试，熟悉基础后再研究。
9. tools：打包和字体维护，日常修改玩法时不用动。

整体流程：玩家点击配兵 → main.gd 处理操作 → battle_sim.gd 校验并保存下一波 → 到时双方出兵 → 模拟器计算战斗 → main.gd 读取状态并绘制单位、血条和特效。

## 七、units.json：兵种字段解释

打开 data/units.json，找到 units 下的对象。内部 ID 分别是 guard（盾卫）、rifle（步枪兵）、breaker（破甲手）、swarm（蜂群兵）、mortar（迫击炮）、sniper（狙击手）。

- name：界面显示的中文名称。
- symbol：预留的字母标识；当前单位形状主要由 main.gd 绘制代码决定。
- cost：单位占用的配兵预算。
- hp：单位出生生命值。
- armor：护甲标签，light 为轻甲，heavy 为重甲。
- damage：基础单次伤害。
- interval：攻击间隔，单位秒，越小攻击越快。
- range：攻击距离，按逻辑战场坐标计算，不等于屏幕像素。
- speed：每秒移动的逻辑距离。
- splash：范围伤害半径，0 表示单体攻击。
- light_multiplier：攻击轻甲的伤害倍率。
- heavy_multiplier：攻击重甲的伤害倍率。
- color：单位的十六进制颜色。
- role、counter：定位和克制提示；改数值不会自动重写这些文字。
- 顶层 version：配置版本标记，规则变化时应考虑版本和旧战报兼容性。

例如基础伤害 20、轻甲倍率 1.5，对轻甲的单次理论伤害是 30。攻击基地只使用基础伤害，范围攻击不伤友军。

不要随意改内部 ID：AI 字典、默认阵容、绘制和测试都可能引用它。新增兵种也要同时考虑这些位置。

## 八、rules.json：对局规则字段解释

- wave_seconds：同时出兵间隔，默认 30 秒。
- start_budget：首波预算，默认 600。
- budget_growth：每波预算增量，默认 100。
- max_budget：预算上限，默认 1200。
- base_hp：双方基地初始生命，默认 3000。
- match_seconds：最长对局时间，默认 480 秒。
- unit_lifetime：单位最多存活时间，默认 90 秒。
- tick_rate：每秒模拟步数，当前 20，初学时保持不变。main.gd 里还有 0.05 秒节拍、插值与按 20 换算的显示逻辑，不能只改 JSON。
- columns、rows：布阵列数和行数，当前 6×4。UI、AI、出生位置也有相应布局，不能只改这两个数字。
- world_width、world_height：当前尺寸标记为 1200×400；出生点、边界、画面映射仍有固定数值，只改这两个配置不会完成战场尺寸改造。
- version：战报采用的规则版本；规则改变后应同步考虑版本，避免混用旧战报。

更改出兵间隔、最长时间和残兵寿命时，界面里的固定说明也要同步修改。更快出兵或更长寿命会增加同屏单位，需要重新检查性能。

## 九、第一次练习：让盾卫更耐打

1. 关闭正在运行的游戏。
2. 打开 D:\MyCode\FightParty\data\units.json。
3. 找到 "guard" 对象中的 "hp":480，只把 480 改为 800。
4. 保存，保留原来的逗号、引号、花括号和 .json 文件后缀。
5. 按 F5，或双击桌面“FightParty开始游戏”，开始新的一局。
6. 放置盾卫，观察它能否坚持更久。双方共用配置，因此敌方盾卫也变成 800 血。
7. 想恢复，把 800 改回 480，再保存并重启。

一次只改一项，更容易看出结果。之后可以练习改价格、攻击间隔和出兵间隔。

修改价格或起始预算后，要检查 scripts/catalog.gd 中的 starter 默认阵容是否仍买得起。平衡调整可能让原来的克制测试失败，需要判断是否属于预期变化，而不是直接删除失败测试。

以前导出的 FightParty.exe 是导出当时的快照，不会读取源码的后续修改。测试最新代码用 F5 或桌面源码快捷方式；要把修改后的游戏发给别人，则需要重新导出。

## 十、常见问题

- 快捷方式打不开：检查 Godot 程序和 D:\MyCode\FightParty\project.godot 是否还在原位置。
- 添加图片/字体后无法直接运行：先在 Godot 编辑器打开工程，等待资源导入，再按 F5。
- 闪退或黑屏：在编辑器运行，查看下方“输出”“调试器”的报错，不要反复双击猜原因。
- 改 JSON 后报错：检查引号、逗号和花括号；不要添加注释或末尾多余的逗号。
- 改完没效果：确认保存的是 D 盘这个工程，运行的是 F5/源码快捷方式，而不是旧 EXE。
- 缩进错误：检查新加的语句是否与同一代码块对齐。
- 新增中文显示方块：项目使用裁剪字体，按 docs/DEVELOPMENT.md 重新生成字体。只增加代码注释不需要重做字体，因为注释不会显示在游戏里。
- 两个副本容易混淆：日常修改的主目录是 D:\MyCode\FightParty，早先 C 盘工作目录的源码不会自动同步这里的修改。

## 十一、测试、打包与 Git（熟悉基础后再用）

以下示例在 PowerShell 执行。先定义 Godot 控制台版路径，再导入和运行规则测试：

```powershell
$godotExe = 'C:\Users\ASUS\Documents\Codex\2026-11-01\2\work\tools\godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path 'D:\MyCode\FightParty' --editor --import --quit
& $godotExe --headless --path 'D:\MyCode\FightParty' --script res://tests/test_sim.gd
```

测试出现 RESULT ... 0 failures 表示该轮没有失败。规则测试还包含 200 单位模拟耗时检查。

tests/ui_smoke.gd 会覆盖本机最近阵容和战报，不要用它来正常开始游戏。tests/render_perf.gd 是渲染压力测试，tests/replay.gd 用来复现已完成战报。

只构建 Windows（需要已安装导出模板）：

```powershell
& 'D:\MyCode\FightParty\tools\build.ps1' -Godot $godotExe -SkipAndroid
```

输出在项目 build 目录；脚本先导入、测试，再打包。安卓配置详见 docs/DEVELOPMENT.md。

查看自己改了什么，以下命令只查看，不提交、不上传：

```powershell
git -C 'D:\MyCode\FightParty' status
git -C 'D:\MyCode\FightParty' diff
```

“提交”保存本地版本，“推送”才上传 GitHub。仅编辑、保存文件不会自动上传。先做小改动，运行正常后再保存版本。

## 十二、进一步阅读与 3D 画面

- D:\MyCode\FightParty\docs\DESIGN.md：玩法与兵种初始数值。
- D:\MyCode\FightParty\docs\ARCHITECTURE.md：分层、接口、数据流和联机边界。
- D:\MyCode\FightParty\docs\DEVELOPMENT.md：测试、打包、字体维护。
- D:\MyCode\FightParty\docs\TEST_REPORT.md：实际验证结果与安卓未验证项。

首版没有真人联机、账号、复杂地形、空军、成品美术或商店发布。今后可以保留平面战斗逻辑，加入 3D 模型、倾斜镜头、动画和特效，形成 2D 玩法、3D 画面；Godot 和 GDScript 可以继续使用。画面层需要改造，手机性能需要重新验证。

## 十三、用 Excel 调整或新增兵种

最方便的方式：打开 `D:\MyCode\FightParty\data\兵种配置.xlsx`，修改并保存，然后双击项目根目录的 `导入兵种.cmd`。看到“已写入”或“数据相同”后，完全关闭游戏并重新打开（桌面开始游戏快捷方式也可以）。

表中包含当前全部 6 个兵种和 16 列：ID、名称、标记、价格、生命、护甲、伤害、攻击间隔、射程、移速、溅射半径、对轻甲倍率、对重甲倍率、颜色、定位说明和克制说明。“填写说明”页逐项解释字段和单位。

操作规则：

1. 在“兵种”页第 6 行开始修改数据，保留第 5 行英文列名。允许整行排序、整列移动；不要单独排序某一列。
2. 新增兵种时，复制一条完整数据行到下方，填写唯一的新 ID 和全部字段。新增单位使用默认圆形图形，兵种卡片每页 6 张，超过后可翻页。
3. 已有 ID 不可删除或改名，因为 AI 和存档可能引用；显示名称 `name` 可以改。ID 只能用小写英文字母、数字和下划线，以字母开头，不能是 `move` 或 `erase`。
4. 价格必须为正整数；生命和攻击间隔必须大于 0；其他数值不可为负。护甲只支持 `light`（轻甲）和 `heavy`（重甲），颜色是 6 位十六进制文本，不带 `#`。
5. 直接填写数字和文字。公式不会导入，避免读取到未重算的旧缓存；如在表中计算过，导入前先粘贴为值。

导入工具只需要 Python 3.8+，不需要安装 pip 包，也不要求电脑安装 Excel（编辑表格可用 Excel 或 WPS）。本机已安装 Python。Windows 双击脚本优先使用 `py -3`，其次使用 `python`；其他电脑需安装 Python 并加入 PATH。

也可以在仓库根目录运行（云端一般使用 `python3`）：

```powershell
python tools/import_units.py --check
python tools/import_units.py
python tools/import_units.py "其他位置的兵种配置.xlsx"
```

`--check` 只校验不写入。默认读取 `data/兵种配置.xlsx`，写入 `data/units.json`。英文键决定字段对应关系，行号与列名会出现在错误提示里。所有行校验通过后才写入；存在改动时先把原 JSON 备份到 `data/backups/units-时间戳.json`，再原子替换目标文件。重复导入相同数据不写入、不新增备份；原有版本号、额外元数据和表中未覆盖的未来字段会保留。

恢复时，关闭游戏，把需要的备份复制覆盖 `data/units.json`，再同步 Excel 中相应数值。**这是 Excel 到 JSON 的单向导入**：手动修改 JSON 不会自动反映到 Excel；提交代码时应同时保存表格和导入后的 JSON。备份和 Excel 临时锁文件不进入 Git。

新增兵种会进入 AI 的普通选择池；专属克制映射仍在 `scripts/commander_ai.gd`。改变价格后 AI 会按实际最低价寻找保底单位，默认阵容超预算时会保留其中买得起的单位。`role` 和 `counter` 只是说明文字，改成“刺客”不会自动获得侧翼切入行为；仇恨系统尚未实现。

导入影响从源码运行的游戏，已经导出的 Windows EXE / Android APK 需要重新打包。改数值也可能改变原有平衡测试的结果，需检查预期是否还合理。

工具测试（只在临时目录或内存修改数据，不覆盖玩家存档）：

```powershell
python -m unittest discover -s tests -p test_import_units.py
godot --headless --path . --script res://tests/test_unit_editor.gd
```

## 十四、发给朋友的 Windows 调试包

朋友无需 GitHub 账号或代码编辑器。包内附带 Godot，解压后双击“开始游戏.cmd”即可试玩；只有编辑、导入兵种表时需要 Excel/WPS 和 Python。

- 朋友操作说明：[运行与兵种调试](docs/朋友调试说明.txt)。
- 打包脚本模板与制作步骤：[tools/friend_package](tools/friend_package/README.md)。
- 已交付包验证记录：[朋友调试包验证记录](docs/朋友调试包验证记录.txt)。

调试包 ZIP 和引擎不提交到源码仓库；表格、导入工具、游戏源码、启动脚本模板及说明文件纳入版本管理。

## 十五、项目与第三方声明

完整项目仓库：https://github.com/Pickher/FightParty

Godot Engine 使用 MIT 许可：https://godotengine.org/license/ 。中文字体来自 Google Noto Sans SC（SIL OFL 1.1），声明位于 assets/OFL.txt；Godot 声明位于 assets/GODOT-LICENSE.txt。

单位图形、图标和短音效由项目代码生成，未使用《星际争霸》的素材、角色或商标作为游戏内容。
