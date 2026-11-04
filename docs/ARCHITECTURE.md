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
- `get_snapshot(viewer)`：深拷贝 tick、wave、budget、bases、units、attack_waves、双方上一波阵容、查看方自己的下一波阵容与胜负，不含敌方待出兵阵容。
- `CommanderAI.choose(last_enemy, budget)`：返回合法网格阵容。调用者不得传入未公开信息。

单位状态包括稳定 ID、team、kind、当前位置/上一步位置、hp、cooldown、born tick，以及首次开火后记录的 locked_target_id（0 表示未锁定）。表现层以模拟余量在 prev 与 pos 之间插值，绘制的形状、颜色、血条和弹道不参与命中判定。

## 每步顺序与公平

1. 增加 tick；若 `unit_lifetime` 大于 0 则撤离到期单位（默认 0 不撤离），保存上一位置。到达出兵时刻且未超过 `wave_limit` 时，整份兵营出场、标记为已部署，再给双方发 `wave_income`。
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

Godot `user://settings.cfg` 保存音量、最近阵容和上次的开局设置（`match` 段，超出 setup_options 范围的值被忽略）；开局设置以 `Sim.new(seed, overrides)` 的 overrides 传入模拟；`user://last_match.json` 保存规则版本、种子、开局设置（`settings`，覆盖 rules 的字段）、双方全部买/卖/移动操作及其 tick（`actions`）、每波 tick/出兵前矿物/阵容（`waves`，仅供查看）和结束结果。只保留最近一局；无云端上传。文件写失败时提示，游戏仍可继续。Windows 的 user:// 通常位于 `%APPDATA%/Godot/app_userdata/FightParty`。

`tests/replay.gd` 读入记录，用相同种子和设置新建模拟，在每步之前执行该 tick 记录的操作（`BattleSim.apply_action()`），推进到结束并比较结果。相同引擎、相同数据版本是复现前提；配置版本不匹配直接拒绝。

## 未来联机边界

未来以独立 Godot headless 进程运行相同模拟核心。客户端只上报阵容，服务端按玩家身份、轮次、预算和占格校验并确认；服务端广播权威状态和事件，客户端插值。不能信任客户端报送的伤害、资源、时间或胜负。

届时需要新增房间生命周期、轮次锁定、超时沿用阵容、连接恢复与协议版本管理。这些功能首版仅预留边界，不包含伪装成可用后端的空实现，不宣称已有联网防作弊能力。

当前规则版本为 0.3.0，旧版战报会因规则版本不同被拒绝重放。目标有效性依据每步开始时的状态判断，因此本步死亡或移出射程会在下一步触发重新索敌。攻击基地沿用无敌军目标时的推进逻辑，不建立敌军单位锁定。

## 可复用技能

`BattleSim` 负责固定步调度、索敌和统一结算，`scripts/skills/` 按配置能力处理具体行为，逻辑不依赖兵种 ID。新增兵种可在 `skills` 下组合现有技能，配置契约见 [SKILLS.md](SKILLS.md)。

- `healing.gd`：选择受伤友军和安全站位，替代普通敌军索敌/攻击；治疗进入统一结算，`heal` 事件用于画治疗连线。
- `deployment.gd`：迫击炮与穿刺者共用展开/收起状态机。拥有 `skills.deployment` 即初始化 `siege_state`、`siege_until_tick`、`siege_scan_tick`、`siege_scan_ids`；`mode` 仅决定架设或埋地的文字/外观。暂停与后台停止模拟时转换计时也停止。
- `multi_attack.gd`：决定一次攻击的打击次数，以及横向扫射从哪一端起始。普通攻击和直线攻击都读取它，每击单独计算伤害。
- `stimulant.gd`：敌军进入可攻击范围时自动施放，扣最大生命一定比例、临时提高攻速/移速；自身代价在末尾统一结算。
- `on_hit_slow.gd`：命中后排队施加减速，后续移动阶段读取状态，避免先行动的单位改变对方本步位移。
- `line_attack.gd`：创建和推进正向或横向传播波。所有单位决定移动后、统一结算前，通过单位运动与波前运动的相对位置计算连续碰撞时刻，伤害进入本步 `hits/base_hits`。

模拟步在覆盖 `prev` 之前统一保存各存活单位上一模拟步位移，供部署技能判断外围敌军是否靠近。少量目标用连续扫描的 ID 交集确认，密集敌军立即触发；架设中和已架设状态都使用射程内敌军及外围接近敌军决定是否保持。

`attack_waves` 与其快照包含固定起点/方向、来源位置、伤害、技能外观、strike 序号、已推进距离、每波命中 ID 集等。波与发射者生命周期独立；双重攻击生成两条独立波。`line_attack` 事件描述本步新扫过的线段，表现层不提前画完路径。全波到达固定末端后移除；对局结算后模拟停止。

每次击中单位产生独立 `attack_hit` 事件（id、kind、team、strike、amount）；同一步两击仍分别发出事件，最终 HP 扣除保持统一累计。`damage` 是单位在该步受到的总伤害，`base_damage` 是基地该步总伤害，避免表现层重复扣血。0.3.0 起，命中按受害者 id 排队为“加成后原始伤害”数组（`queue_hit`），结算时逐击经 `Shield.absorb` 先扣护盾、再按护甲值扣生命，每击至少 `min_damage`。`raw_damage(weapon, kind)` 只对轻甲/重甲加 `bonus`；`expected_damage(weapon, victim)` 供索敌、AI 反制和多武器选择估算（有护盾时不减护甲）。存活单位在末尾执行护盾恢复与 `regen` 回血，二者共用 `last_hit_tick`。事件当前没有被动或触发器系统。

## 种族（0.3.0）

`sim.races` 来自 `rules.races`（可被开局 overrides 覆盖并写入战报）。`buy` 与阵容校验用 `kind_error` 拒绝其他种族与 stub 兵种。`main.gd` 的配兵卡只列本方种族兵种，stub 显示为灰色“尚未实装”。AI 的反制函数 `counter_for` 不查表，按“对该敌方兵种的预期每秒伤害 ÷ 价格”在本方可用兵种中选最高者；前排与辅助兵种来自 `races.json` 的 `ai` 配置。

## 结构体（0.2.2）

门口防御塔、宝库和玩家建造的防御塔都放在 `units` 中，`structure: true`，速度 0，沿用普通索敌、伤害、溅射和传播攻击，因此不需要单独的战斗循环。`BattleSim.is_structure()` 用于在治疗、击杀统计、最后阶段可攻击部队统计和防卫圈选目标中排除它们；`_can_hit_unit()` 按武器的 `attacks_structures`（缺省同 `attacks_base`）过滤。宝库死亡时在统一结算阶段给另一方加 `treasury_reward`。`build_tower(team)` 校验次数与矿物后立即生成，并写入 `actions`（`build_tower`），重放时同样执行。

## 战场布局（0.1.9）

出生区、基地中心与半径、移动边界都来自 `rules.layout`，只按我方坐标填写；`BattleSim.mirror_x(team, x)` 按 `world_width` 镜像到敌方，`base_pos(team)` 和 `clamp_to_field(point)` 供模拟、医疗兵与传播攻击共用，`main.gd` 的 `_world()` 也按 `world_width/world_height` 缩放。改布局只需改配置，镜像公平测试会检查左右一致。

## 0.1.8 空地分类与防卫圈

兵种 `layer` 表示自身所属空/地层，`target_layers` 表示当前武器可命中的层，`attacks_base` 控制基地攻击。默认 ground/仅对地/可攻击基地，保持旧配置语义。锁定维持、普通索敌、溅射受害者、部署扫描和传播波均进行层过滤；传播波保存发射时允许命中的层，地刺和巨像不会伤害飞行单位。局部分离仅在同层进行；医疗兵不把飞机当作跟随掩护，治疗范围沿用原有不区分生物/机械/空地的规则。

`defender_zone.gd` 在普通索敌前推进模式，复用 `deployment.gd` 的计时与扫描。后者接受可选 context（中心、范围、目标层、部署配置），因此防卫圈以区域中心检查占用和外围接近，炮兵/穿刺者仍以自身为中心。展开时保存 `defender_center`，改变武器而不改变自身空中层；`_weapon_stats` 合并防卫武器覆盖字段，`_can_hit_unit` 叠加固定圆形区域约束。圈外锁定失效，圈中心只有收起后重新展开才能改变。共享普通攻击冷却，变形不刷新冷却。
