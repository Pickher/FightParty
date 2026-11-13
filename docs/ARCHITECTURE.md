# 架构与接口

## 分层

`data` 是带版本的兵种（`units.json`）、种族（`races.json`）与规则（`rules.json`）配置；`Catalog` 负责加载、合并种族列表、判断兵种是否已实装（`is_ready`）、按种族筛选兵种（`race_units`）与读取种族默认阵容（`starter(race)`）。

`BattleSim` 是 RefCounted 对象，不依赖 SceneTree、Node、物理引擎或画面，包含全部矿物与兵营操作（`buy`/`sell`/`move`/`submit_formation`）、波次、单位状态、固定步模拟和结算。测试可在 Godot headless 模式下运行。

`CommanderAI.new(seed, race)` 按种族建立可用兵种池；`buy_list()` 只接收上一波公开阵容、自己的兵营与矿物和本地伪随机生成器，输出准备购买的格子列表，再由 `main.gd` 逐个调用 `buy()`。`main.gd` 是本地对局控制与表现适配器：接收点击、提交阵容、调度固定步、绘制快照、呈现事件和保存设置。它不计算伤害。

## 最小接口

- 阵容：`Array[{kind: String, cell: int}]`，cell 为 row×6+column，允许空数组。
- `submit_formation(team, formation) -> String`：成功返回空串，失败返回原因，原提交保持不变。深拷贝输入，防止调用方随后改动影响待出兵阵容。
- `validate_formation(formation, allowed_budget, team)`：AI、玩家和测试共享校验；兵种合法性由 `kind_error(team, kind)` 判断（未知/结构体、stub 未实装、不属于本方种族都拒绝）。
- `step() -> Array[Dictionary]`：推进一个 0.05 秒模拟步，产生 wave、attack、heal、line_attack、attack_hit、skill_used、damage、death、expired、base_damage、weapon_switch、ended 事件。damage 事件的数值是生命与护盾损失之和。结束后的 step 不再推进。
- `get_snapshot(viewer)`：深拷贝 tick、wave、budget、bases、units、attack_waves、双方上一波阵容、双方种族、`revealed`、查看方自己的下一波阵容与胜负，不含敌方待出兵阵容；首次交战前对方种族为空字符串、对方上一波阵容为空数组。
- `visible_enemy_formation(viewer)` / `visible_race(viewer, team)`：按公开规则给出 viewer 可见的对方上一波阵容与种族。`main.gd` 的电脑购买和敌情栏只用这两个接口。
- `CommanderAI.choose(last_enemy, budget)`：返回合法网格阵容。调用者不得传入未公开信息。

单位状态包括稳定 ID、team、kind、当前位置/上一步位置、hp、cooldown、born tick，以及首次开火后记录的 locked_target_id（0 表示未锁定）。表现层以模拟余量在 prev 与 pos 之间插值，绘制的形状、颜色、血条和弹道不参与命中判定。

精灵动画（目前只有大和舰，`scripts/battlecruiser_visual.gd`）是只读的表现对象，接口与 cloud/test 上特战队员的 `rifle_visual.gd` 相同：`reset()`、`update(delta)`、`observe(units, prune_missing)`、`event(event, before, units, revealed)`、`draw_unit()`、`draw_corpse()`、`draw_frame()`。`main.gd` 每步先快照大和舰并观察，再 `step()`，再观察并逐个传入事件，最后再观察一次；攻击/大和炮事件没有攻击者 ID，按同队同兵种、发射位置匹配，匹配后在事件里写入 `muzzle` / `left`，特效据此从炮口画起。它不改单位、不改事件结算。

## 每步顺序与公平

1. 增加 tick；若 `unit_lifetime` 大于 0 则撤离到期单位（默认 0 不撤离），保存上一位置。到达出兵时刻且未超过 `wave_limit` 时，整份兵营出场、标记为已部署。首波与常规出兵使用独立倒计时；不再按出兵发钱，经济组件每3秒独立结算，见[地图与经济](DESERT_STORM_ECONOMY.md)。
2. 到达波次边界且未达到总时限时，从双方阵容同时创建单位，并写入波次记录。
3. 按 80×80 空间桶索引单位。发现半径为自身攻击距离的 150%，取最近敌人（0.3.0 删除了狙击手的低生命加权）。多武器单位用兵种顶层射程与目标层索敌（`_search_stats`），选定目标后再由 `weapon_switch` 选武器，切换期间不开火。尚未开火时每步重选；首次开火后持续锁定，直到目标死亡、撤离或离开攻击范围才重新索敌。暂不考虑迷雾。
4. 以同一份步初状态决定所有单位的移动、治疗和攻击；技能模块累计治疗、伤害与基地伤害。移动决定后推进已发射的攻击波，按本步运动轨迹判断命中。
5. 一次性应用位置、伤害、死亡与击杀，再判断双方基地和时间结算。

同一步死亡单位仍可完成已决定的攻击；不会因为先处理我方就阻止敌方开火。分离向量基于旧位置，避免原地依次更新导致方向偏差。距离相同以稳定 ID 决定，镜像对局测试检查左右一致性。浮点与版本差异仍可能影响跨平台重放，不承诺跨架构确定性锁步。

0.2.0 取消寿命后，场上单位数量由交战消耗决定；0.2.1 网格为 18×8，每方每波至多 144 个单位。为此做了空间查询优化，结果与逐个比较完全一致（`_spatial_equivalence` 测试用 960 次随机比较验证）：
- 除全体 80×80 空间桶外，另建按阵营分开的桶，以及本步的 id → 单位索引。锁定目标直接按 id 查，不再遍历候选。
- 索敌和防卫圈选地面目标时，按桶的环由近到远搜索，并裁剪到搜索圆的包围盒；整桶比当前最佳更远时跳过，确定不会有更近目标后提前结束。
- 部署扫描、防卫圈占用检查和传播攻击只查询敌方桶。传播攻击只检查前沿本步扫过区域附近的单位。
- 分离避让改用 20×20 细网格。
- 解放者防卫模式的合并武器按兵种缓存。
- 热点函数不再用 `get(key, [])` 创建临时容器。

基准（云端 Linux 单核，`tests/crowd_perf.gd`，双方各 144 格、12 波）：每步平均从 14.3 ms 降到约 7.4 ms，最慢从约 55–68 ms 降到约 25 ms，峰值约 326 个单位，没有无限累积。手机 CPU 可能慢数倍，真机仍需验证。

## 保存与复现

Godot `user://settings.cfg` 保存音量、每个种族各自的最近阵容（`player` 段的 `formation_<种族>`）和上次的开局设置（`match` 段，含 `race_0`/`race_1` 种族选择；超出 setup_options 范围的值被忽略）；保存时先读入旧文件，避免覆盖其他种族的阵容；开局设置以 `Sim.new(seed, overrides)` 的 overrides 传入模拟；`user://last_match.json` 保存规则版本、种子、开局设置（`settings`，覆盖 rules 的字段）、双方全部买/卖/移动操作及其 tick（`actions`）、每波 tick/出兵前矿物/阵容（`waves`，仅供查看）和结束结果。只保留最近一局；无云端上传。文件写失败时提示，游戏仍可继续。Windows 的 user:// 通常位于 `%APPDATA%/Godot/app_userdata/FightParty`。

`tests/replay.gd` 读入记录，用相同种子和设置新建模拟，在每步之前执行该 tick 记录的操作（`BattleSim.apply_action()`），推进到结束并比较结果。相同引擎、相同数据版本是复现前提；配置版本不匹配直接拒绝。

## 未来联机边界

未来以独立 Godot headless 进程运行相同模拟核心。客户端只上报阵容，服务端按玩家身份、轮次、预算和占格校验并确认；服务端广播权威状态和事件，客户端插值。不能信任客户端报送的伤害、资源、时间或胜负。

届时需要新增房间生命周期、轮次锁定、超时沿用阵容、连接恢复与协议版本管理。这些功能首版仅预留边界，不包含伪装成可用后端的空实现，不宣称已有联网防作弊能力。

当前规则版本为 0.7.3，旧版战报会因规则版本不同被拒绝重放。目标有效性依据每步开始时的状态判断，因此本步死亡或移出射程会在下一步触发重新索敌。攻击基地沿用无敌军目标时的推进逻辑，不建立敌军单位锁定。

## 可复用技能

`BattleSim` 负责固定步调度、索敌和统一结算，`scripts/skills/` 按配置能力处理具体行为，逻辑不依赖兵种 ID。新增兵种可在 `skills` 下组合现有技能，配置契约见 [SKILLS.md](SKILLS.md)。

- `healing.gd`：选择受伤友军和安全站位，替代普通敌军索敌/攻击；治疗进入统一结算，`heal` 事件用于画治疗连线。
- `deployment.gd`：迫击炮与穿刺者共用展开/收起状态机。拥有 `skills.deployment` 即初始化 `siege_state`、`siege_until_tick`、`siege_scan_tick`、`siege_scan_ids`；`mode` 仅决定架设或埋地的文字/外观。暂停与后台停止模拟时转换计时也停止。
- `multi_attack.gd`：决定一次攻击的打击次数，以及横向扫射从哪一端起始。普通攻击和直线攻击都读取它，每击单独计算伤害。
- `stimulant.gd`：敌军进入可攻击范围时自动施放，扣最大生命一定比例、临时提高攻速/移速；自身代价在末尾统一结算。
- `yamato.gd`：大和炮先于普通行动调度；引导期间停止移动与普通攻击，命中进入统一 queue_hit 结算。
- `on_hit_slow.gd`：命中后排队施加减速，后续移动阶段读取状态，避免先行动的单位改变对方本步位移。
- `line_attack.gd`：创建和推进正向或横向传播波。所有单位决定移动后、统一结算前，通过单位运动与波前运动的相对位置计算连续碰撞时刻，伤害进入本步 `hits/base_hits`。

模拟步在覆盖 `prev` 之前统一保存各存活单位上一模拟步位移，供部署技能判断外围敌军是否靠近。少量目标用连续扫描的 ID 交集确认，密集敌军立即触发；架设中和已架设状态都使用射程内敌军及外围接近敌军决定是否保持。

`attack_waves` 与其快照包含固定起点/方向、来源位置、伤害、技能外观、strike 序号、已推进距离、每波命中 ID 集等。波与发射者生命周期独立；双重攻击生成两条独立波。`line_attack` 事件描述本步新扫过的线段，表现层不提前画完路径。全波到达固定末端后移除；对局结算后模拟停止。

每次击中单位产生独立 `attack_hit` 事件（id、kind、team、strike、amount）；同一步两击仍分别发出事件，最终 HP 扣除保持统一累计。`damage` 是单位在该步受到的总伤害，`base_damage` 是基地该步总伤害，避免表现层重复扣血。0.3.0 起，命中按受害者 id 排队为“加成后原始伤害”数组（`queue_hit`），结算时逐击经 `Shield.absorb` 先扣护盾、再按护甲值扣生命，每击至少 `min_damage`。`raw_damage(weapon, kind)` 只对轻甲/重甲加 `bonus`；`expected_damage(weapon, victim)` 供索敌、AI 反制和多武器选择估算（有护盾时不减护甲）。存活单位在末尾执行护盾恢复与 `regen` 回血，二者共用 `last_hit_tick`。事件当前没有被动或触发器系统。

## 种族（0.3.0）

`sim.races` 来自 `rules.races`（可被开局 overrides 覆盖并写入战报）。`buy` 与阵容校验用 `kind_error` 拒绝其他种族与 stub 兵种。`main.gd` 的配兵卡只列本方种族兵种，stub 显示为灰色“尚未实装”。AI 的反制函数 `counter_for` 不查表，按“对该敌方兵种的预期每秒伤害 ÷ 价格”在本方可用兵种中选最高者；前排与辅助兵种来自 `races.json` 的 `ai` 配置。

0.3.1 起 `revealed` 在第一次有单位、结构体或基地受到敌方伤害的那一步末尾置为 true，并发出 `revealed` 事件（只发一次）。它完全由模拟过程决定，所以战报不需要额外记录，重放时会在同一 tick 公开。表现层在公开前把敌方单位画成灰色“?”、敌方结构体画成灰色八边形，传播攻击也只用阵营色。

## 结构体（0.2.2）

宝库和玩家建造的防御塔放在`units`中，`structure: true`，速度0，沿用普通索敌、伤害、溅射和传播攻击。`BattleSim.is_structure()`用于在治疗、击杀统计、最后阶段可攻击部队统计和防卫圈选目标中排除它们；`_can_hit_unit()`按武器的`attacks_structures`（缺省同`attacks_base`）过滤。宝库死亡时在统一结算阶段由经济组件给另一方增加灵核，不再奖励矿物。`build_tower(team, position)`统一校验次数、矿物和选址后生成，玩家通过战场点选位置；塔身必须全部在己方半场和地图内，不能与基地、宝库或其他建筑重叠。成功才扣矿和次数。`actions`中的`build_tower`保存`position:[x,y]`，重放按实际坐标建造；没有坐标的旧战报兼容旧候选位。

0.8.1：基地防御改由`units/base_defense.gd`维护。`bases`是唯一生命池，`base_defenses`保存每方不可逆的active标记及AttackCycle锁定/冷却状态；`gate_tower`仅提供防御层生命、武器和防御期回血配置，不生成单位。攻击共用空间索敌、AttackCycle、queue_direct_strike与真实伤害结算，在同一步统一结算。基地先扣血、永久撤销耗尽的防御层，再以当前上限回血；归零不回血。快照及最终战报包含base_max_hp、base_defenses，避免仅凭当前生命推断曾经失效的防御层。structures=false只生成核心、不反击。基地不新增可被溅射命中的重复实体。

## 战场布局（0.1.9）

出生区、基地中心与半径、移动边界都来自 `rules.layout`，只按我方坐标填写；`BattleSim.mirror_x(team, x)` 按 `world_width` 镜像到敌方，`base_pos(team)` 和 `clamp_to_field(point)` 供模拟、医疗兵与传播攻击共用，`main.gd` 的 `_world()` 也按 `world_width/world_height` 缩放。改布局只需改配置，镜像公平测试会检查左右一致。

## 0.1.8 空地分类与防卫圈

兵种 `layer` 表示自身所属空/地层，`target_layers` 表示当前武器可命中的层，`attacks_base` 控制基地攻击。默认 ground/仅对地/可攻击基地，保持旧配置语义。锁定维持、普通索敌、溅射受害者、部署扫描和传播波均进行层过滤；传播波保存发射时允许命中的层，地刺和巨像不会伤害飞行单位。局部分离仅在同层进行；医疗兵不把飞机当作跟随掩护，治疗范围沿用原有不区分生物/机械/空地的规则。

`defender_zone.gd` 在普通索敌前推进模式，复用 `deployment.gd` 的计时与扫描。后者接受可选 context（中心、范围、目标层、部署配置），因此防卫圈以区域中心检查占用和外围接近，炮兵/穿刺者仍以自身为中心。展开时保存 `defender_center`，改变武器而不改变自身空中层；`_weapon_stats` 合并防卫武器覆盖字段，`_can_hit_unit` 叠加固定圆形区域约束。圈外锁定失效，圈中心只有收起后重新展开才能改变。共享普通攻击冷却，变形不刷新冷却。

## 0.4.0 尺度与绘图迁移

当前尺度与建筑表以 [WORLD_UNITS.md](WORLD_UNITS.md) 和 data/rules.json 为准；上文版本历史中的圆形防卫区、旧桶宽和固定显示大小不再适用于当前版本。粗桶 4 格、细桶 2 格；分离搜索半径按模型实际接触距离计算。组槽位在 _spawn_wave 展开为多个独立单位，成本/退款/兵营操作保持按组。

DefenderZone 不再保存 defender_center，按自身位置、阵营朝向和 ±20° 进行统一扇形过滤。Deployment 的可选 context 支持 sector_angle_degrees，扫描、保持和命中使用相同几何范围。WeaponSwitch 支持空军优先的目标搜索，以及轻甲数量/密度触发的模式选择。

battle_view.gd 只绘制子视口的战场，main.gd 把纹理画进固定区域再绘制界面和弹层；相机矩形决定世界到屏幕的等比例映射。unit_art.gd 共用模型绘制，size 决定世界占地，UI 标记按屏幕大小显示。相机不写入战报也不参与模拟。

## 0.5.0 预留技能实现

本轮技能模块、兵种行为、状态和召唤时序，以 [ROSTER_SKILLS.md](ROSTER_SKILLS.md) 为准。新增实现未运行验证；旧文中的 stub 清单为历史状态。

## 0.6.0 技能组件化

技能实例、统一生命周期与状态归属以 [SKILL_COMPONENTS.md](SKILL_COMPONENTS.md) 为准。BattleSim 只调用 SkillSystem，旧版静态技能集合入口已迁移为独立组件和公共服务。

## 0.7.0 公共单位模型

详见 [UNIT_MODEL.md](UNIT_MODEL.md)。UnitDefinition 保存兵种公共属性和多套 WeaponDefinition；Unit 保存每个战场实体的唯一状态，处理能量、自然恢复与攻击阶段。旧 units/by_id/技能接口引用 Unit.state，同一状态不进行双份同步。BattleSim.definitions 和 unit_instances 管理模板和实例，死亡/撤离后释放；快照仍输出纯字典。回盾改用逐兵种参数，原蟑螂/缝合巨尸自然回血迁入基础属性；前后摇和能量已支持配置，旧兵种默认 0。


## 0.7.1 紧凑战场

当前地图为 90×18 格，以特战队员 2.25 格/秒换算成 40×8 个参考距离单位。点位与出生区见 WORLD_UNITS.md；出生中心与组槽位解耦，实际占用列居中并受最大跨度约束，保留左右镜像和上下位置。建筑占地、基地半径、近景缩放及尺寸标注同步调整；单位技能、射程、移动速度保持现有数值。本次未运行验证。


## 0.7.2 碰撞与溅射参数

UnitDefinition 新增 collision_radius 与 separate_when_stopped，前者供空间桶、出生留距和分离统一使用，后者只在允许移动的攻击冷却阶段整理队形。WeaponDefinition 新增 splash_multiplier，直接攻击按主目标 ID 区分全额伤害与护甲前的次目标倍率。见 WORLD_UNITS.md 和 UNIT_MODEL.md；本轮未运行验证。


## 0.7.3 坦克移动/架设武器

架设组件支持可选 weapon 和 mobile_can_attack，在读取本步武器前推进状态，已架设才切到新武器。移动炮单体 21+14 重甲、1.04 秒、7 格；架设炮主目标 52+33 重甲、3 秒、13 格、旁侧 50% 溅射。保持原扫描与收放时间，共享单位攻击冷却，不改其他部署兵种的开火限制。未运行验证。


## 0.9.0 攻击序列与弹体

正式配置把武器归入attack_modes，UnitDefinition构造独立WeaponDefinition，技能用mode_id引用；Catalog/UnitDefinition生成兼容投影供现有UI和技能读字段，JSON不保留单位顶层武器真值。普通单位、独立炮位和基地共享AttackCycle及AttackSequence服务。AttackCycle把出手阶段和轮后冷却分开，序列保存模式/命中技能快照，按步内偏移逐段发射；Projectile按固定或距离弹道推进，命中才进入queue_direct_strike。传播模式每段走LineService，未发出段随死亡/中断取消，已发弹体继续。快照新增attack_sequences/projectiles/next_projectile_id，数据均为纯字典；攻击事件带source_id、mode、time，移动单位的炮口动画可稳定匹配发射者。命中仍按既有固定步同时结算，具体口径及全兵种初值见ATTACK_MODES.md。


0.9.1：delivery.type=beam由BeamService处理，不创建AttackSequence/Projectile。每个持有者/炮位保存beam_state（目标、模式、切换截止时间、累计作用时间）；每0.5秒一次正常伤害/治疗，使用原有每命中护甲结算。active_beams仅用于连续画面并包含在快照中，重置不影响beam_state。医疗兵与基地也复用此服务；目标切换等0.3秒，不做0.05秒细分伤害计算。


## 0.9.2 攻击行为接口

新增scripts/attacks/attack_behavior.gd公共接口、projectile_attack/beam_attack/line_attack三类及attack_registry统一注册入口。BattleSim、基地、独立炮位与医疗兵调用行为接口，AttackSequence委托can_emit/emit，场上推进及目标死亡回调由注册器固定顺序分发。AI/DPS和简介通过行为获取段数、预估和名称，不再散落beam/wave等字符串判断。行为实例共享且无单位状态；模式和快照仍仅持有数据。底层服务与公共命中、护甲、溅射保持原逻辑。正式数据/Excel使用projectile+flight、beam、line；旧枚举在WeaponDefinition构造时兼容转换。详见ATTACK_BEHAVIORS.md。

## 周期经济

`BattleSim`持有`DesertStormEconomy`组件，配置位于`rules.economy`。战斗移动、死亡和基地伤害统一结算后再扫描中央井与支付收入；因此死亡单位不能占领，基地被摧毁的当步不发钱。气厂/兑换动作通过`apply_action`进入日志，波次与结算记录双方资源，快照仅返回自己的钱包。UI不直接增减瓦斯或灵核。
