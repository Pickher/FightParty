# FightParty 新手使用与修改指南

项目后续安排见 [项目规划](docs/PROJECT_PLAN.md) 和 [待完成任务清单](docs/PROJECT_BACKLOG.md)。两份文档以 v0.11.3 为评估基线，区分已有功能、待验证内容与后续工作。

当前特性分支在 [V01 战场视图](docs/V01_BATTLEFIELD_CAMERA.md) 上新增折叠部队配置、实际人数列表、点按/拖线和自动排布，操作及待验收项见 [部队配置说明](docs/MOBILE_FORMATION.md)。本次未运行游戏、测试、模拟或打包。

本机工程目录：D:\MyCode\FightParty

桌面的“FightParty指导.txt”是这份 README 的相同内容副本。以后修改 README 后，桌面副本不会自动更新，需要重新复制。

FightParty 是公平配兵、按波次出兵、残兵推进的原创自动战斗游戏。当前源码为 Windows + Android 离线人机原型，规则版本 **0.12.3**，使用 Godot 和 GDScript；Windows 原环境为 4.7.2，云端验证环境为 4.6.3。最近一次打包的测试 APK 仍是 0.7.4，之后的改动需要重新打包才会进入手机。

当前玩法规则见 [游戏设计](docs/DESIGN.md)，兵种数值见 [兵种数值总表](docs/UNIT_TABLE.md)，已有测试结果见 [测试报告](docs/TEST_REPORT.md)，不代表当前特性分支已验收。需要用户安排验证时，可用一条命令执行检查（见第十一节）；日常代码修改不自动运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot 'C:\Users\ASUS\Documents\Codex\2026-11-01\2\work\tools\godot\Godot_v4.7.2-stable_win64_console.exe'
```

0.12.3：整合医疗运输机逻辑及旧阵容迁移，同时保留 0.12.2 混编行军与 U04 界面待设计事项。医疗运输机暂代人族医疗兵，850 矿/2 架，空中机械、避战、双束治疗生物友军；原医疗兵仅停用，代码保留。部分继承数值尚待确认，当前美术仅为占位轮廓。来源、临时参数和验证边界见 [医疗运输机](docs/MEDIVAC.md)。未运行游戏、测试或打包。

0.12.2：追猎者、执政官在附近有其他类别友军时按混编部队限速行军，纯同类恢复原本行军速度；保留自身减速、攻击和闪现，跳虫不改。范围与具体规则见 [混编行军限速](docs/FORMATION_PACE.md)。未运行游戏、测试或打包。

0.12.0：新增折叠式部队配置，购买组内成员可独立排布，坐标用于后续波次并随设置/战报保存。默认战场大视图；最初打开配置会暂停；当前行为见下方操作说明。未执行运行验证。

0.11.5：哨兵改为护盾支援，并按组出售。一次购买 500 矿、出场 2 名（与特战队员同一套组购买、未出场退款和电脑购买）。接敌时开启防御护盾（半径 4.5、持续 12.86 秒、花费 100 能量）；已处于其他哨兵护盾范围内则不重复开启，直到那层护盾消失。友军护盾不满时优先回盾，一名哨兵同时最多锁定 2 个目标，每个目标只被一名哨兵锁定；每 0.5 秒回复 5 点护盾并消耗 2 点能量。附近没有可攻击友军时像医疗兵一样后撤并跟随下一波，附近友军护盾都满了才攻击。裂解光束伤害 9→4.5（护盾额外伤害仍为 4）。旧战报重放结果会变化。0.11.5 当时的 `tools/check.sh` 全部通过，不代表 0.12.0 已验收。

0.11.4（基线记录）：恶火碰撞/分离半径0.6→0.75（取原图恶火变体SeparationRadius）并在攻击冷却中散开，降低坦克溅射叠伤；新增规则`engage_radius`=30（原图wanttoattack自动施法范围）：没有目标的单位会转向30格内偏离行军方向超过45°的最近可攻击敌人，近战被远程溅射后不再沿路线脱离部队。旧战报重放结果会变化。`tools/check.sh`全部通过。

0.5～0.11.3 各版本的改动摘要已移到 [README 版本说明（历史）](docs/archive/README_VERSION_NOTES.md)；其中的旧数值和“未运行验证”说明不代表当前状态。

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

1. 默认显示战场大视图，点下方「部队配置」展开面板；打开时战斗与倒计时照常推进；若已手动暂停，则保持暂停。
2. 「招募部队」按组购买；「现有部队」显示各兵种已有组数与实际人数（当前特战队员一组 4 名）。
3. 选兵种，再选 1 名、一组、全部或用 −/+ 调人数。点空处放置；按住拖出直线、松手后均匀排布，短线会展开多排。
4. 「下一批」或一次成功布置后切到下一批；点已有士兵可重新选择并修改。绿色/红色预览提示可否放下，拖出框松手取消。
5. 「一键自动排布」按近战、普通火力、远程部署和辅助的前后定位排布，还能继续拖线微调。
6. 删除/退款/清空走「格阵管理」原界面，仍按购买组管理；已有单兵位置的组请用新面板改变实际出生位置。
7. 点「收起，返回战场」，再点右上角「开始准备」；65 秒后双方出第一波，之后按出兵间隔（推荐 45 秒）出下一波。
8. 战斗期间可以打开配置调整后续波次，不能直接指挥场上部队。到达出兵时刻时只使用已提交的布阵，不使用拖线预览。
9. 所有种族双方从空兵营开始，电脑从正常收入事件起买兵。可以手动保存本族布阵；新局开始准备前可在空兵营手动载入已存阵容，按当前资源扣费。
9. 可在格阵管理的敌情区查看敌方上一波阵容；AI 也只能参考你上一波的公开配置。完整操作和边界见 [部队配置说明](docs/MOBILE_FORMATION.md)。

每局开始前弹出“开局设置”：选择我方与电脑种族（人族/虫族/神族/腐族/随机，推荐我方人族、电脑随机），开局资金 200★ / 600 / 1000 / 自定义，出兵间隔 30 / 45★ / 60 秒 / 自定义（★ 为推荐，自定义用 −/+ 调整）。双方使用同一份设置，重开时再次弹出并记住上次选择。

买下的单位永久留在兵营，每波整份出场。收入不按波次发放，而是每 3 秒发一次矿物：第 1～10 波每次 30，第 11～40 波 60，第 41 波起 120，第 64 波起停止。第 10 波起中央资源井开放，占领方每次额外 +3 矿。兵营下方“经济”按钮可以建造/拆除气厂（把一部分矿物收入转成瓦斯，部分兵种需要瓦斯）和把瓦斯换回矿物。矿物可以结转，击杀不加钱；摧毁敌方宝库得 1 灵核。本轮新买、还没出场的单位取消可全额退回；出场过的单位也能取消，但不退款，界面会二次确认。移动兵营单位免费。部队一直战斗到阵亡。

每方每局可以建一座防御塔：点“建造防御塔”后在己方半场点选落点（不能越过中线或压住建筑）。基地开局 15000 生命，其中 5000 是防御层，打到 10000 以下就永久失去防御层和反击。摧毁基地获胜；第 64 波后不再出兵，先失去全部可攻击部队的一方失败，双方同时失去为平局；若 64 波后 600 秒仍未分出胜负，比较基地剩余生命。

注意：现在各种族的默认阵容都超过推荐开局资金 200，所以第一次玩或换种族时兵营是空的，需要自己购买。完整规则见 [docs/DESIGN.md](docs/DESIGN.md)。

空格键开始/暂停/继续；Esc 打开或关闭玩法说明，部队配置打开时 Esc 收起配置。查看说明时计时暂停。结算后点击“调整阵容，再来一局”。

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

- 修改和在电脑运行：Godot 4.7.2 标准版即可，本机已经准备好。不需要 .NET SDK、C++ 编译器、数据库或服务器。
- 保存版本和同步 GitHub：Git，本机已经安装，工程也已关联远程仓库。
- 导出独立 Windows EXE：需要 4.7.2 对应导出模板。只按 F5 运行源码时不用导出模板。
- 导出 Android APK：需要对应导出模板、Java JDK、Android SDK。本机此前用 JDK 21.0.10 和 Android Build Tools 36.0.0 成功构建，也已有 Android Studio。
- Python 3 用于运行检查脚本中的导入器测试、Excel 导入（tools/import_units.py）、兵种总表（tools/unit_table.py）和字体维护，不是游戏运行环境。

Godot 的“编辑器 → 管理导出模板”用于安装模板；“编辑器 → 编辑器设置 → 导出 → Android”中填写 Java SDK Path 和 Android SDK Path。本机 Android SDK 位于 C:\Users\ASUS\AppData\Local\Android\Sdk。

Windows 使用 Compatibility；安卓测试包使用 Mobile/Vulkan。安卓已通过构建和签名检查，但最终包的实际运行、触摸、后台恢复和真机帧率尚未验证，不是已发布的手机成品。详细情况见 docs/TEST_REPORT.md。

## 五、先认识文件和基本语法

- .gd：GDScript，Godot 的脚本语言，缩进风格像 Python，但不是 Python。
- .tscn：场景文件，描述节点关系和绑定的脚本。
- .json：配置数据；JSON 不允许直接写 # 或 // 注释，因此字段解释放在下文。
- project.godot：项目入口和设置，包括主场景、窗口、渲染器。
- .ps1：PowerShell 检查与打包脚本；.sh：同功能的 Linux/macOS 检查脚本；.py：Python 工具与导入器测试。
- .godot 目录：自动生成的导入缓存，不是主要学习对象，不提交到 Git。

GDScript 中 var 定义变量，const 定义常量，func 定义函数，if 判断条件，for 遍历，return 返回结果。Array 是数组，Dictionary 是键值对字典，Vector2 是二维坐标。

以 # 或 ## 开头的行是注释，不参与执行。本次已经给主要脚本、测试和工具添加中文导读、函数说明与关键流程注释。

缩进决定代码属于哪个函数或条件，请保持原缩进，避免混用 Tab 和空格。res:// 表示工程目录，user:// 表示玩家数据目录。

## 六、建议按这个顺序研究项目

以下路径都相对于 D:\MyCode\FightParty：

1. data/units.json：兵种价格、血量、伤害、射程，最适合第一次修改。
2. data/rules.json：出兵间隔、开局矿物、周期收入与经济、地图布局、基地血量与波数上限。
3. data/races.json：四个种族、供测试用的历史示例阵容与电脑配兵参数。scripts/catalog.gd 负责读取这些配置。
4. scripts/commander_ai.gd：电脑怎样根据上一波按护甲公式现算反制兵种。
5. scripts/battle_sim.gd：配兵校验、生成单位、自动寻敌、移动、扣血和胜负。
6. scripts/main.gd：入口、界面、按钮操作、每帧调度和存档。
7. scenes/main.tscn：绑定 main.gd 的主场景，是 F5 启动的画面。
8. tests：规则、界面、重放和性能测试，熟悉基础后再研究。
9. tools：一键检查、Excel 导入、兵种总表、打包和字体维护。

整体流程：玩家点击配兵 → main.gd 处理操作 → battle_sim.gd 校验并保存下一波 → 到时双方出兵 → 模拟器计算战斗 → main.gd 读取状态并绘制单位、血条和特效。

## 七、units.json：兵种字段解释

0.9.0起，下面的武器字段（damage、bonus、interval、range、target_layers等）均填写在单位的`attack_modes`对应模式中，不再放在单位顶层。`primary_mode`引用默认模式ID；`attack_duration`是本轮出手持续时间，`interval`是本轮结束后的等待时间。完整结构与每种兵种的初始模式见[攻击模式与弹道](docs/ATTACK_MODES.md)。

打开 data/units.json，找到 units 下的对象。当前四个种族共 43 个可购买兵种，另有 3 种召唤物和 6 种结构体；完整数值见 [docs/UNIT_TABLE.md](docs/UNIT_TABLE.md)（运行 `python tools/unit_table.py` 从 JSON 重新生成）。

- name：界面显示的中文名称。
- symbol：字母标识；还没有专属外形的兵种画成圆形加这个字母。
- race：所属种族 terran / zerg / protoss / blight；结构体为 neutral。每局只能买本方种族的兵种。
- status：ready 表示已实装、可购买；summoned 表示只能由技能召唤；stub 表示只是预留数据（缺少技能），卡片显示灰色“尚未实装”，电脑也不会选。当前没有 stub 兵种。
- pending：stub（或部分 ready 兵种）还缺的技能模块名单，方便以后实现。
- requires：以后要做的“解锁前置”（兵营里有前置兵种才能买），目前只记录、不生效。
- sc2：参考的《星际争霸 II》单位，只借定位与数值比例，不使用素材。
- cost、gas_cost、core_cost：购买一组永久单位花费的矿物、瓦斯和灵核。
- spawn_count：每组的个体数，每波出场这么多名。
- hp：单位出生生命值。shield：神族护盾值，见下文。
- armor_type：护甲类型 none（无甲）/ light（轻甲）/ heavy（重甲）/ special（特殊甲）。
- armor：生命护甲点数，伤害进入生命时每段减去这么多。shield_armor 是护盾护甲，伤害进入护盾时减去。无甲 none 只表示未分类，也可以有护甲点数。
- layer：自身所属层，ground 地面或 air 空中；变换武器模式不改变所属层。
- target_layers：武器可攻击的层列表；attacks_base 表示是否可以攻击基地。
- damage：基础单次伤害。
- bonus：护甲类型加成，例如 {"heavy":30} 表示打重甲时每段多 30。bonus_tags 按目标标签加成，例如 {"biological":5}。
- hit_count：每轮命中段数，每段独立扣护甲。
- interval：本轮出手结束后的攻击间隔，单位秒；两轮起手之间还需加上出手持续时间及额外前后摇。
- range：攻击距离，单位“格”，不等于屏幕像素。
- speed：每秒移动的格数。
- size、collision_radius：模型占地与避让圆半径，见 [docs/WORLD_UNITS.md](docs/WORLD_UNITS.md)。
- skills：可复用技能配置，省略时使用普通移动/攻击。详细字段及组合示例见 [docs/SKILLS.md](docs/SKILLS.md)。
- skills 下常见的组件：healing（治疗）、deployment（架设/埋地）、line_attack（直线攻击）、defender_zone（解放者防卫扇形）、stimulant（强化剂）、on_hit_slow（命中减速）、weapon_switch（多武器切换）、yamato（大和炮）、combat_mobility（交战机动）、summon（召唤）、independent_weapons（独立炮位）等。每个组件的参数与当前数值见 [docs/SKILLS.md](docs/SKILLS.md) 和 Excel 的“技能参数”页。
- splash：范围伤害半径，0 表示单体攻击；splash_rings 可设置按距离衰减的倍率。
- color：单位的十六进制颜色。
- role、counter：定位和克制提示；改数值不会自动重写这些文字。
- 顶层 version：配置版本标记，规则变化时应考虑版本和旧战报兼容性。

护甲规则：每段伤害 = damage + 对应护甲类型的 bonus + 符合标签的 bonus_tags − 目标 armor，最少 0.5。无甲和特殊甲不吃护甲类型加成。例如劫掠者 damage 13、bonus heavy 13，打重甲、护甲 4 的蟑螂是 13 + 13 − 4 = 22；打轻甲、护甲 3 的特战队员是 13 − 3 = 10。神族先扣护盾：进入护盾的部分减 shield_armor（默认 0），打穿护盾的剩余部分再减生命护甲。护盾按兵种参数在脱战后恢复；医疗兵只回生命。真实伤害（例如基地防御层）跳过护甲。攻击基地只计基础伤害，范围攻击不伤友军。

不要随意改内部 ID：data/races.json 的默认阵容和电脑配兵参数、绘制和测试都可能引用它。新增兵种也要同时考虑这些位置。

data/races.json 是种族表：每个种族的中文名、主题色、一句风格描述（只是介绍，不带任何种族克制机制）、测试用历史示例阵容 starter，以及电脑参数 ai（front 为保证数量的前排兵种、front_min 为数量；support 为辅助兵种，兵营总价加矿物达到 support_value 时买一个）。

## 八、rules.json：对局规则字段解释

- first_wave_seconds：首波准备时间，默认65秒。
- wave_seconds：之后同时出兵间隔，默认45秒。
- start_minerals：双方开局矿物，推荐200。
- economy：周期收入、阶段、中央占领、气厂分流和灵核奖励配置，见[地图与经济](docs/DESERT_STORM_ECONOMY.md)。wave_income保留为0，不再发每波收入。
- wave_limit：最后一波的编号，默认 64；之后不再出兵也不再发收入。
- final_phase_max_seconds：最后一波后的安全时限，默认 600 秒；到时比较基地剩余生命，防止双方互相打不到时对局卡死。
- base_hp：基地核心生命上限，默认10000。开局额外获得gate_tower.hp的5000生命，总计15000；降至10000及以下后永久失去额外上限与反击。
- base_regen_per_second：仅剩核心时每秒回血，默认5；防御层存在时采用gate_tower.health_regen，同为整座基地5/秒，不叠加。回血不能复活基地或恢复失效的防御层。
- structures：是否启用基地防御层和放置宝库，默认true；false时基地只有核心生命、不反击，供隔离单位行为使用。基地防御模块不生成独立单位，在基地中心以8格射程、每0.5秒造成300点无视护甲的光束伤害，可对地对空。
- treasury_reward：旧矿物奖励保留为0；宝库现在按economy.outpost_core_reward奖励灵核。
- tower_max_builds：每方每局可建造防御塔的次数，默认 1；被摧毁不归还次数。防御塔按种族不同：人族 terran_bunker、虫族 zerg_tower_cluster、神族 protoss_photon_cannon、腐族 tower，价格取各自的 cost（神族 600，其他 500）。
- unit_lifetime：单位最多存活秒数，默认 0 表示不撤离。
- tick_rate：每秒模拟步数，当前 20，初学时保持不变。main.gd 里还有 0.05 秒节拍、插值与按 20 换算的显示逻辑，不能只改 JSON。
- columns、rows：布阵列数和行数，当前 18×8。UI 网格按这两个数自动等分，AI 的前后排格子顺序也按它们生成；改尺寸时要同步调整 layout 的出生参数，并检查 races.json 测试用示例阵容的格子编号。
- world_width、world_height：逻辑战场尺寸，当前196×118；敌方坐标绕场地中心点对称，画面映射也按这两个值缩放。
- layout：战场布局，全部按我方（左侧）坐标填写，敌方按point_symmetry点对称。base_x/base_y/base_radius是基地中心与判定半径，基地防御模块共用此位置；treasury_x/treasury_y、tower_x/tower_y是宝库与防御塔旧候选位；spawn_x/spawn_y是出兵中心，spawn_width/spawn_height是组中心展开跨度，spawn_column_spacing是最大列距；bounds是单位可移动的边界。医疗兵无掩护时退向spawn_x。
- races：双方种族，默认 ["terran","terran"]；开局设置可以覆盖，整局固定并写入战报。未知种族按 terran 处理。
- race_setup：开局弹窗两行种族选择的标题 labels 与推荐值 recommended（默认我方 terran、电脑 random）。random 在建局时随机成具体种族，写入战报的是随机后的结果，所以重放不会再随机。
- min_damage：每发命中的最低伤害，默认 0.5。shield_regen_delay、shield_regen_per_second：护盾脱战多少秒后开始恢复、每秒恢复多少，默认 7 秒、7.5。
- setup_options：开局设置弹窗的选项。每个字段（start_minerals、wave_seconds）有 label、unit、choices 三个预设、recommended 推荐值（应等于同名默认值）、自定义的 step/min/max。
- world_unit、distance_schema、map_reference：距离单位说明与参考地图的来源坐标，只作记录，不参与战斗计算。
- version：战报采用的规则版本；规则改变后应同步考虑版本，避免混用旧战报。

更改出兵间隔、最长时间和残兵寿命时，界面里的固定说明也要同步修改。更快出兵或更长寿命会增加同屏单位，需要重新检查性能。

## 九、第一次练习：让恶火更耐打

1. 关闭正在运行的游戏。
2. 打开 D:\MyCode\FightParty\data\units.json。
3. 找到 "hellbat" 对象中的 "hp":90，只把 90 改为 150。
4. 保存，保留原来的逗号、引号、花括号和 .json 文件后缀。
5. 按 F5，或双击桌面“FightParty开始游戏”，开始新的一局（我方选人族）。
6. 放置恶火，观察它能否坚持更久。双方共用配置，因此电脑的人族恶火也变成 150 血。
7. 想恢复，把 150 改回 90，再保存并重启。

一次只改一项，更容易看出结果。之后可以练习改价格、攻击间隔和出兵间隔。

修改价格或开局矿物后，检查手动招募及显式载入预设的预算约束；正常开局不使用 starter。平衡调整可能让原来的克制测试失败，需要判断是否属于预期变化，而不是直接删除失败测试。

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

以下示例在 PowerShell 执行。先定义 Godot 控制台版路径（必须是带 `_console` 的 exe，才能看到输出），再一条命令运行全部检查：

```powershell
$godotExe = 'C:\Users\ASUS\Documents\Codex\2026-11-01\2\work\tools\godot\Godot_v4.7.2-stable_win64_console.exe'
cd 'D:\MyCode\FightParty'
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot $godotExe
```

它依次运行资源导入、规则模拟测试、兵种编辑器测试、界面冒烟测试、战报重放、Excel 导入器测试和兵种总表同步检查，每项显示 ok 或 FAIL，最后给出汇总；全部通过时退出码为 0。详细日志在 build\check-logs\ 下。加 `-Perf` 还会运行大规模模拟和渲染性能测试（多花约 3 分钟）。Linux/macOS 用 `GODOT=/path/to/godot tools/check.sh`。每项内容与单独运行方法见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

注意：界面冒烟测试会覆盖本机最近阵容和战报（user:// 目录），不要在想保留战报时运行；它也不能代替正常开始游戏。

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

- D:\MyCode\FightParty\docs\DESIGN.md：当前玩法规则。
- [docs/UNIT_TABLE.md](docs/UNIT_TABLE.md)：由数据生成的兵种数值总表。
- [docs/WORLD_UNITS.md](docs/WORLD_UNITS.md)：战场尺度、出生队形与单位体积。
- D:\MyCode\FightParty\docs\ARCHITECTURE.md：分层、接口、数据流和联机边界。
- [docs/SKILLS.md](docs/SKILLS.md)：技能配置、组合方式与扩展入口。
- D:\MyCode\FightParty\docs\DEVELOPMENT.md：一键检查、单项测试、打包、字体维护。
- D:\MyCode\FightParty\docs\TEST_REPORT.md：最新验证结果、未验证项与待决定事项。
- [docs/archive/](docs/archive/README.md)：各版本的历史记录，旧数值不代表当前规则。

首版没有真人联机、账号、复杂地形、成品美术或商店发布。今后可以保留平面战斗逻辑，加入 3D 模型、倾斜镜头、动画和特效，形成 2D 玩法、3D 画面；Godot 和 GDScript 可以继续使用。画面层需要改造，手机性能需要重新验证。

## 十三、用 Excel 批量修改兵种

当前表格在 [data/units/兵种配置.xlsx](data/units/兵种配置.xlsx)，与 `data/units.json` 同属兵种数据目录。已按当前代码导出全部52个单位、召唤物和建筑。0.9.0起所有武器数值（包括伤害类型、加成、段数、持续时间和弹道）独立列在“武器模式”页，单位属性不重复存武器。当前只保留这一份编辑表；旧版表格需刷新后编辑。保留[原版数值核对记录](docs/SC2_BALANCE_REFERENCE.md)、待确认清单及技能核对页，待确认字段路径已随模式迁移。黄色/灰色标记格可留空，导入保留兼容值；其他数值格不能清空。

1. 用Excel/WPS打开新表。“兵种属性”一行一个单位，可改生命、护盾、能量、移速、碰撞半径、每组数量和自然恢复等。
2. 在“武器模式”筛选兵种ID，修改F列数值。每种模式独立保存伤害、加成、射程、段数、持续时间、轮后间隔及弹道参数，包括只有一种模式的兵种。保留模式ID。
3. 在“技能参数”筛选兵种ID，修改F列数值，例如强化剂持续时间、埋地耗时和模式引用。地刺速度、双重攻击段数现在在对应武器模式中。修改参数只能调整已有机制，新能力仍需写代码。
4. 保存并关闭表格，在项目根目录执行 `python tools/import_units.py`，或把编辑后的表格交给 AI 导入。导入后重启源码游戏；已导出的 APK/EXE 需要重新打包。

保留页签、英文列名、兵种 ID、参数路径及全部数据行。“源数据”隐藏页用于识别用户编辑及并发修改，不能删除。支持筛选、整行排序和属性整列移动；不要单独排序某一列。新增单位、技能或删除参数先交给开发者处理。属性页中原本空白的字段可按同列其他单位格式补值；清空已有数值不会删除字段。

字段有中文标题；攻击间隔填秒、射程填格、移速填格/秒、价格按组、生命/伤害按单体。倍率 `1.3` 表示 +30%，`0.5` 表示一半。布尔填 `true/false`。数组/对象字段仍用 JSON，例如模型尺寸 `[0.8,0.8]`、重甲加成 `{"heavy":14}`。不要填公式；计算结果请粘贴为值。

导入仅需 Python 3.8+ 标准库，无需安装 Excel 或 pip 包。Windows 可使用 `py -3` 或 `python`；云端一般使用 `python3`：

```sh
python tools/import_units.py --check
python tools/import_units.py
python tools/import_units.py "其他位置的兵种配置.xlsx"
```

`--check` 只校验不写入。默认读取新表，写入 `data/units.json`；所有数据通过校验后才自动备份到 `data/backups/` 并原子替换。未编辑的字段保留当前源码的值；同一字段在表格和源码中分别修改时会提示冲突，列表按整体判断。重复导入无变化不会写入或新增备份。游戏仍读取 JSON，表格保存本身不会自动生效。

如代码已更新，要生成一份新表，先导入或另存已有编辑，再运行：

```sh
python -m pip install openpyxl
python tools/unit_workbook.py --output "data/units/兵种配置-更新.xlsx"
```

生成工具需要 openpyxl；为保护未导入的编辑，它拒绝覆盖现有文件。导入工具兼容旧版工作簿格式，但请使用上面的新版当前表。

## 十四、项目与第三方声明

完整项目仓库：https://github.com/Pickher/FightParty

Godot Engine 使用 MIT 许可：https://godotengine.org/license/ 。中文字体来自 Google Noto Sans SC（SIL OFL 1.1），声明位于 assets/OFL.txt；Godot 声明位于 assets/GODOT-LICENSE.txt。

单位图形、图标和短音效由项目代码生成，未使用《星际争霸》的素材、角色或商标作为游戏内容。
