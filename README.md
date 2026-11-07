# FightParty 新手使用与修改指南

本机工程目录：D:\MyCode\FightParty

桌面的“FightParty指导.txt”是这份 README 的相同内容副本。以后修改 README 后，桌面副本不会自动更新，需要重新复制。

FightParty 是公平配兵、按波次出兵、残兵推进的原创自动战斗游戏。当前源码为 Windows + Android 离线人机原型 v0.3.2，使用 Godot 和 GDScript；Windows 原环境为 4.7.2，云端验证环境为 4.6.3。已有下载页的 APK 仍为 0.1.4。

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

1. 看下方兵种卡片的价格、定位与克制提示。超过九种时，点“选择兵种”右侧的 < / > 翻页。
2. 点兵种卡片，再点左下方网格，放置或替换单位。右边是前排，左边是后排。
3. “移除单位”：先点工具，再点要移除的单位。
4. “移动位置”：先点来源格，再点目标格；目标已占用时交换位置。
5. “清空阵容”清空下一波配置，也允许不派兵。
6. 点右上角“开始准备”，30 秒后双方同时出兵，之后每 30 秒出下一波。
7. 战斗时仍可配置下一波；不能直接指挥已经在场的部队。
8. 根据右下角敌方上一波阵容调整组合；AI 也只能参考你上一波的公开配置。

每局开始前弹出“开局设置”：开局资金 0 / 600★ / 1000 / 自定义，每轮收入 100 / 300★ / 500 / 自定义，出兵间隔 20 / 30★ / 45 秒 / 自定义（★ 为推荐，自定义用 −/+ 调整）；双方使用同一份设置，重开时再次弹出并记住上次选择。买下的单位永久留在兵营，每波整份出场。按推荐设置，双方开局 600 矿物，每次出兵后各得 300；矿物可以结转，击杀不加钱。本轮新买、还没出场的单位取消可全额退回；出场过的单位也能取消，但不退款，界面会二次确认。移动兵营单位免费。部队一直战斗到阵亡。摧毁基地获胜；第 64 波后不再出兵，先失去全部可攻击部队（医疗兵不算）的一方失败，双方同时失去为平局；若 64 波后 600 秒仍未分出胜负，比较基地剩余生命。

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
2. data/rules.json：出兵间隔、开局矿物与每轮收入、基地血量与波数上限。
3. data/races.json：四个种族、默认开局阵容与电脑配兵参数。scripts/catalog.gd 负责读取这些配置。
4. scripts/commander_ai.gd：电脑怎样根据上一波按护甲公式现算反制兵种。
5. scripts/battle_sim.gd：配兵校验、生成单位、自动寻敌、移动、扣血和胜负。
6. scripts/main.gd：入口、界面、按钮操作、每帧调度和存档。
7. scenes/main.tscn：绑定 main.gd 的主场景，是 F5 启动的画面。
8. tests：规则、界面、重放和性能测试，熟悉基础后再研究。
9. tools：打包和字体维护，日常修改玩法时不用动。

整体流程：玩家点击配兵 → main.gd 处理操作 → battle_sim.gd 校验并保存下一波 → 到时双方出兵 → 模拟器计算战斗 → main.gd 读取状态并绘制单位、血条和特效。

## 七、units.json：兵种字段解释

打开 data/units.json，找到 units 下的对象。0.3.0 起共有四个种族（人族、虫族、神族、腐族）约 40 个兵种，完整清单与 SC2 参考见 docs/DESIGN.md 的“种族、护甲与护盾”一节。旧 ID guard（盾卫）、breaker（破甲手）、sniper（狙击手）已经删除：盾卫改名“先锋” vanguard 归神族，破甲手与狙击手合并为人族“特工” agent。

- name：界面显示的中文名称。
- symbol：字母标识；还没有专属外形的兵种画成圆形加这个字母。
- race：所属种族 terran / zerg / protoss / blight；结构体为 neutral。每局只能买本方种族的兵种。
- status：ready 表示已实装、可购买；stub 表示只是预留数据（缺少技能），卡片显示灰色“尚未实装”，电脑也不会选。
- pending：stub（或部分 ready 兵种）还缺的技能模块名单，方便以后实现。
- requires：以后要做的“解锁前置”（兵营里有前置兵种才能买），目前只记录、不生效。
- sc2：参考的《星际争霸 II》单位，只借定位与数值比例，不使用素材。
- cost：购买一名永久单位花费的矿物。
- hp：单位出生生命值。shield：神族护盾值，见下文。
- armor_type：护甲类型 none（无甲）/ light（轻甲）/ heavy（重甲）/ special（特殊甲）。
- armor：护甲点数，每次受击先减去这么多伤害（护盾吸收的部分不减）。无甲单位的护甲点数必须为 0。
- layer：自身所属层，ground 地面或 air 空中；变换武器模式不改变所属层。
- target_layers：武器可攻击的层列表；attacks_base 表示是否可以攻击基地。
- damage：基础单次伤害。
- bonus：穿甲加成，例如 {"heavy":30} 表示打重甲时每发多 30。
- interval：攻击间隔，单位秒，越小攻击越快。
- range：攻击距离，按逻辑战场坐标计算，不等于屏幕像素。
- speed：每秒移动的逻辑距离。
- skills：可复用技能配置，省略时使用普通移动/攻击。详细字段及组合示例见 [docs/SKILLS.md](docs/SKILLS.md)。
- skills.healing：`heal` 为单次治疗量；`follow_distance`、`danger_distance` 控制后排跟随与避敌。医疗兵当前每 0.5 秒治疗 12，范围 160。
- skills.deployment：`deploy_seconds`、`pack_seconds` 为展开/收起耗时；`deploy_enemy_threshold`、`scan_seconds` 控制人数阈值与扫描确认；`hold_range_multiplier` 控制外围保持范围。`mode` 用 siege 显示架设，用 burrow 显示埋地，埋地暂不隐身。
- skills.line_attack：`pattern` 为 forward（从自身沿目标方向传播）或 transverse（以目标位置为中心横向扫射）；`speed` 为传播速度，`half_width` 为半宽，`length` 为固定长度，省略时使用 range；`effect` 选择 spike/beam 外观。
- skills.defender_zone：划定固定防卫圈并切换武器，复用展开/收起时序。解放者普通模式对空，防卫模式仅对圈内地面单位。
- skills.stimulant：自动交战强化剂，配置最大生命扣除比例、持续秒数、攻速倍率与移速倍率。劫掠者为 15%、20 秒、1.3、1.5。
- skills.on_hit_slow：命中后移动减速，配置持续秒数与移速倍率；劫掠者为 2 秒、0.5，重复命中刷新、不叠加。
- skills.multi_attack.count：每次攻击的独立打击次数，巨像为 2。每击都按护甲规则结算，共享一次攻击冷却；直线攻击每击拥有独立轨迹及命中记录。
- skills.weapon_switch：多武器。特工有穿甲弹与狙击弹，按目标护甲自动换弹，换弹 1.5 秒不能开火；雷神对地、对空各一把武器，换武器没有延迟；大和舰的对地/对空激光炮组同理。
- skills.yamato：大和炮。damage 伤害、range 射程、channel_seconds 引导秒数（期间不能移动和开火）、cooldown_seconds 冷却、min_target_hp 目标生命+护盾下限。大和舰为 720、280、2、71、300。
- skills.regen：脱战再生，`delay` 秒没受伤后每秒回 `per_second` 生命（蟑螂、缝合巨尸）。
- splash：范围伤害半径，0 表示单体攻击。
- color：单位的十六进制颜色。
- role、counter：定位和克制提示；改数值不会自动重写这些文字。
- 顶层 version：配置版本标记，规则变化时应考虑版本和旧战报兼容性。

护甲规则（0.3.0）：每发伤害 = damage + 对应护甲类型的 bonus − 目标 armor，最少 0.5。无甲和特殊甲不吃任何 bonus。例如劫掠者 damage 30、bonus heavy 30，打重甲、护甲 3 的蟑螂是 30 + 30 − 3 = 57；打轻甲、护甲 0 的步枪兵是 30。神族先扣护盾：护盾按 damage + bonus 扣，不减护甲点数；打穿护盾的剩余部分再减护甲。连续 7 秒没受伤后每秒回 7.5 护盾；医疗兵只回生命。攻击基地只使用基础伤害，范围攻击不伤友军。

解放者价格为 300（0.1.9 起，原为 1200），开局矿物即可购买；它在两个模式下都不能攻击基地。防卫圈是允许选取地面目标的范围，圈内仍逐个攻击。

不要随意改内部 ID：data/races.json 的默认阵容和电脑配兵参数、绘制和测试都可能引用它。新增兵种也要同时考虑这些位置。

data/races.json 是种族表：每个种族的中文名、主题色、一句风格描述（只是介绍，不带任何种族克制机制）、开局默认阵容 starter，以及电脑参数 ai（front 为保证数量的前排兵种、front_min 为数量；support 为辅助兵种，兵营总价加矿物达到 support_value 时买一个）。

## 八、rules.json：对局规则字段解释

- wave_seconds：同时出兵间隔，默认 30 秒。
- start_minerals：双方开局矿物，默认 600。
- wave_income：每次出兵后双方各得的矿物，默认 300。
- wave_limit：最后一波的编号，默认 64；之后不再出兵也不再发收入。
- final_phase_max_seconds：最后一波后的安全时限，默认 600 秒；到时比较基地剩余生命，防止双方互相打不到时对局卡死。
- base_hp：双方基地初始生命，默认 3000。基地本身不攻击。
- structures：是否放置门口防御塔和宝库，默认 true；测试用 false 隔离单位行为。
- treasury_reward：摧毁对方宝库时攻击方获得的矿物，默认 400。
- tower_max_builds：每方每局可建造防御塔的次数，默认 1；被摧毁不归还次数。防御塔价格取 units.json 中 tower 的 cost（默认 500）。
- unit_lifetime：单位最多存活秒数，默认 0 表示不撤离（0.1.8 为 90）。
- tick_rate：每秒模拟步数，当前 20，初学时保持不变。main.gd 里还有 0.05 秒节拍、插值与按 20 换算的显示逻辑，不能只改 JSON。
- columns、rows：布阵列数和行数，当前 18×8（0.2.1 起，原为 6×4）。UI 网格按这两个数自动等分，AI 的前后排格子顺序也按它们生成；改尺寸时要同步调整 layout 的出生间距，并检查 catalog.gd 的默认阵容格子。
- world_width、world_height：逻辑战场尺寸，当前 1200×400；敌方坐标按 world_width 镜像，画面映射也按这两个值缩放。
- layout：战场布局，全部按我方（左侧）坐标填写，敌方自动镜像。base_x/base_y/base_radius 是基地中心与判定半径；gate_x/gate_y、treasury_x/treasury_y、tower_x/tower_y 是门口防御塔、宝库与防御塔建造位；spawn_x/spawn_dx/spawn_y/spawn_dy 是出生区第 0 格位置与列/行间距；bounds 是单位可移动的边界。医疗兵无掩护时退向 spawn_x。
- races：双方种族，默认 ["terran","terran"]；开局设置可以覆盖，整局固定并写入战报。未知种族按 terran 处理。
- race_setup：开局弹窗两行种族选择的标题 labels 与推荐值 recommended（默认我方 terran、电脑 random）。random 在建局时随机成具体种族，写入战报的是随机后的结果，所以重放不会再随机。
- min_damage：每发命中的最低伤害，默认 0.5。shield_regen_delay、shield_regen_per_second：护盾脱战多少秒后开始恢复、每秒恢复多少，默认 7 秒、7.5。
- setup_options：开局设置弹窗的选项。每个字段（start_minerals、wave_income、wave_seconds）有 label、unit、choices 三个预设、recommended 推荐值（应等于同名默认值）、自定义的 step/min/max。
- version：战报采用的规则版本；规则改变后应同步考虑版本，避免混用旧战报。

更改出兵间隔、最长时间和残兵寿命时，界面里的固定说明也要同步修改。更快出兵或更长寿命会增加同屏单位，需要重新检查性能。

## 九、第一次练习：让恶火更耐打

1. 关闭正在运行的游戏。
2. 打开 D:\MyCode\FightParty\data\units.json。
3. 找到 "hellbat" 对象中的 "hp":365，只把 365 改为 600。
4. 保存，保留原来的逗号、引号、花括号和 .json 文件后缀。
5. 按 F5，或双击桌面“FightParty开始游戏”，开始新的一局。
6. 放置恶火，观察它能否坚持更久。双方共用配置，因此敌方恶火也变成 600 血。
7. 想恢复，把 600 改回 365，再保存并重启。

一次只改一项，更容易看出结果。之后可以练习改价格、攻击间隔和出兵间隔。

修改价格或开局矿物后，要检查 data/races.json 中各种族的 starter 默认阵容是否仍买得起（买不起时开局兵营为空）。平衡调整可能让原来的克制测试失败，需要判断是否属于预期变化，而不是直接删除失败测试。

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

tests/ui_smoke.gd 会覆盖本机最近阵容和战报，不要用它来正常开始游戏。tests/render_perf.gd 是渲染压力测试，tests/crowd_perf.gd 是满兵营大规模模拟基准，tests/replay.gd 用来复现已完成战报。

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
- [docs/SKILLS.md](docs/SKILLS.md)：技能配置、组合方式与扩展入口。
- D:\MyCode\FightParty\docs\DEVELOPMENT.md：测试、打包、字体维护。
- D:\MyCode\FightParty\docs\TEST_REPORT.md：实际验证结果与安卓未验证项。

首版没有真人联机、账号、复杂地形、成品美术或商店发布。今后可以保留平面战斗逻辑，加入 3D 模型、倾斜镜头、动画和特效，形成 2D 玩法、3D 画面；Godot 和 GDScript 可以继续使用。画面层需要改造，手机性能需要重新验证。

## 十三、项目与第三方声明

完整项目仓库：https://github.com/Pickher/FightParty

Godot Engine 使用 MIT 许可：https://godotengine.org/license/ 。中文字体来自 Google Noto Sans SC（SIL OFL 1.1），声明位于 assets/OFL.txt；Godot 声明位于 assets/GODOT-LICENSE.txt。

单位图形、图标和短音效由项目代码生成，未使用《星际争霸》的素材、角色或商标作为游戏内容。
