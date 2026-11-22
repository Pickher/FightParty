# 架构与接口（规则 0.12.0）

本文描述当前代码结构。各版本逐条追加的实现记录见 [历史归档](archive/ARCHITECTURE_HISTORY.md)。

## 分层

| 层 | 文件 | 职责 |
| --- | --- | --- |
| 数据 | `data/rules.json`、`data/units.json`、`data/races.json` | 规则、兵种、种族与电脑参数，带版本号 |
| 读取 | `scripts/catalog.gd` | 加载配置、构造 `UnitDefinition`、按种族筛选（`race_units`）、判断实装（`is_ready`）、测试用历史阵容（`starter`）、种族防御塔（`tower_kind`） |
| 模型 | `scripts/units/` | `UnitDefinition`（兵种模板）、`WeaponDefinition`（攻击模式）、`Unit`（战场实例状态）、`AttackCycle`（出手/冷却）、`BaseDefense`（基地防御层） |
| 模拟 | `scripts/battle_sim.gd` | 兵营操作、波次、固定步模拟、统一结算、胜负、快照与战报；不依赖场景树、节点、物理或渲染 |
| 攻击 | `scripts/attacks/` | `AttackBehavior` 接口与 `projectile`/`beam`/`line` 三种投送行为，经 `attack_registry.gd` 分发 |
| 技能 | `scripts/skills/` | `SkillSystem` 调度各技能组件；`services/` 提供序列、弹体、光束、直线、范围、护盾、减速、状态、召唤、部署等公共服务 |
| 经济 | `scripts/economy/desert_storm_economy.gd` | 周期收入、中央井、气厂、瓦斯兑换、灵核奖励 |
| 电脑 | `scripts/commander_ai.gd` | 只做购买与建塔决策 |
| 布阵 | `scripts/formation_layout.gd`、`formation_panel.gd` | 纯几何排布/校验与独立配置面板；通过模拟接口调整已有成员，详见 [部队配置](MOBILE_FORMATION.md) |
| 表现 | `scripts/main.gd`、`battle_view.gd`、`unit_art.gd`、`unit_summary.gd`、`rifle_visual.gd`、`battlecruiser_visual.gd` | 输入、界面、调度固定步、绘制快照与事件、保存设置与战报；不计算伤害 |

`main.gd` 每帧累计时间，够 0.05 秒推进一次 `BattleSim.step()`（20 Hz，单帧最多补 0.25 秒），未开始、暂停、说明页、经济面板和切后台时不推进；部队配置不暂停进行中的对局。表现层在 `prev` 与 `pos` 之间插值，绘制的形状、血条和特效不参与命中。

## 模拟接口

- 阵容：`Array[{kind, cell}]`，`cell = row × columns + column`，允许空数组。兵营内部条目另有 `deployed`（是否出场过）和可选 `member_positions`（组内成员相对出兵中心的坐标数组）。
- `buy(team, kind, cell)`、`sell(team, cell)`、`move(team, from, to)`、`submit_formation(team, formation)`：成功返回空字符串，失败返回原因且不改状态。`submit_formation` 按格比较，同格同兵种保留，其余先卖后买，整份资源足够才执行。
- `deployment_bounds()`、`deployment_members(team)`：提供部署边界和展开后的成员位置；`arrange_members(team, placements)` 免费重排已有成员，校验整批后写入位置，不经买卖、不改变出场状态，只影响后续波次。`restore_deployment(team, placements)` 只允许开局恢复完整组内坐标，保留旧布局重叠并记录独立动作。
- `validate_formation(formation, budget, team)`、`kind_error(team, kind)`：玩家、电脑与测试共享校验。
- `build_tower(team, position)`、`tower_error`、`tower_position_error`、`suggested_tower_position`：建塔资格、选址与电脑默认落点使用同一套规则。
- `economy.set_gasworks(sim, team, count)`、`economy.exchange_gas(sim, team)`：经济操作，写入战报。
- `apply_action(action)`：按战报重放一条操作（buy/sell/move/build_tower/gasworks/exchange_gas）。
- `step() -> Array`：推进一步并返回事件（wave、attack、attack_hit、damage、death、structure_destroyed、base_damage、base_defense_lost、income、income_tier、center_captured、revealed、tower_built、ended 等）。结束后不再推进。
- `get_snapshot(viewer)`：深拷贝的可见状态。包含 tick、波次、基地生命与上限、防御层状态、单位快照、攻击序列/弹体/传播波/光束/技能区域、双方上一波公开阵容、可见种族、`revealed`、查看方自己的兵营、矿物与经济快照。不含敌方待出兵兵营和敌方钱包；首次交战前对方种族为空字符串、上一波阵容为空数组。
- `visible_enemy_formation(viewer)`、`visible_race(viewer, team)`：电脑购买与敌情栏只用这两个接口。
- `CommanderAI.new(seed, race)`；`buy_list(last_enemy, roster, minerals, gas, cores)` 返回 `[{kind, cell}]`，`tower_plan(...)` 返回 `build`/`save`/空。调用方不得传入未公开信息，结果仍由 `buy()`/`build_tower()` 校验。

## 每步顺序

1. tick 加一；移除到期单位（召唤物寿命，或 `unit_lifetime` 大于 0 时的撤离），记录每个单位上一步位移并保存 `prev`。
2. 到达出兵时刻且未超过 `wave_limit` 时，双方整份兵营同时出场并标记已部署，写入波次记录。
3. 重建空间桶（粗桶 4 格、细桶 2 格、按阵营分桶、id 索引）。
4. 技能帧开始、状态推进、基地防御层开火。
5. 每个单位基于**同一份步初状态**：技能前置（可接管行动）→ 索敌与技能选目标 → 选武器 → 推进攻击时钟 → 光束持续作用、发起攻击序列，或移动（目标方向加局部分离）。伤害、治疗、位移、减速、自身代价都只排队。
6. 推进攻击序列、弹体、光束、直线传播与范围技能，按本步运动轨迹判定命中。
7. 统一应用：位置 → 减速 → 治疗（按上限封顶）→ 逐段伤害（`Shield.absorb`：护盾护甲、护盾、生命护甲、最低伤害）→ 死亡。存活单位执行自然恢复与技能存活回调；结构体死亡触发宝库灵核奖励；其余死亡计击杀并触发死亡技能。召唤队列在此统一生成。
8. 结算基地伤害、防御层失效与基地回血；首次出现敌方伤害时公开种族。
9. 经济组件扫描中央井并按 3 秒节拍发放收入（死亡单位不能占领，基地被摧毁当步不发钱）。
10. 判定胜负：基地归零（同时归零为平局）；最终阶段某方没有可攻击部队；或超过安全时限比较基地生命。

同一步互相致命的单位都能完成已决定的攻击；分离向量基于旧位置；距离相同按稳定 ID 决定。不承诺跨平台、跨架构的确定性锁步。

## 单位、武器与攻击

- `UnitDefinition` 保存兵种公共属性与多套 `WeaponDefinition`；`primary_mode` 指定默认模式，技能用 `mode_id`/`mode_ids` 引用其他模式。`Catalog` 为旧 UI/技能生成兼容投影，JSON 不保留单位顶层武器真值。见 [公共单位模型](UNIT_MODEL.md) 与 [攻击模式](ATTACK_MODES.md)。
- `Unit` 是每个战场实体唯一的可变状态；`sim.units`、`by_id` 与技能都引用同一个 `Unit.state` 字典，`sim.unit_model(unit)` 取实例。死亡或到期后释放。
- `AttackCycle` 区分出手阶段（`attack_duration`、前后摇、`strike_offsets`）与轮后冷却（`interval`）；每轮 `hit_count` 段，每段独立扣甲并触发命中效果。
- 攻击行为（[攻击行为抽象](ATTACK_BEHAVIORS.md)）：`projectile` 经 AttackSequence 逐段发射、Projectile 飞行，命中才进入 `queue_direct_strike`；`beam` 由 BeamService 每 0.5 秒结算一次，切换目标等 0.3 秒；`line` 由 LineService 推进固定起点、方向和长度的传播波，按相对运动做连续碰撞。行为对象共享且无单位状态。
- 基地防御层、独立炮位（地堡、爬虫防御群）和医疗兵复用同一套攻击周期与行为。

## 技能组件

`SkillSystem` 在固定生命周期钩子上调用挂载的技能实例（帧开始、索敌前、选目标、行动前后、命中、吸收伤害、存活、死亡、帧结束），技能参数与状态互相隔离，逻辑不依赖兵种 ID。配置契约见 [技能配置](SKILLS.md)，组件与服务见 [技能组件](SKILL_COMPONENTS.md)，各兵种行为见 [兵种技能实现](ROSTER_SKILLS.md)。

## 结构体与基地

宝库与防御塔是 `units` 中 `structure: true`、速度 0 的普通实体，沿用索敌、伤害、溅射与传播攻击；`is_structure()` 用于在治疗、击杀统计、最终阶段可攻击部队统计中排除它们，武器的 `attacks_structures`（缺省同 `attacks_base`）控制能否攻击它们。

基地不是实体：`bases[team]` 是唯一生命池，`base_defenses[team]` 保存不可逆的 `active` 标记与攻击周期状态，`gate_tower` 只提供防御层生命、武器与回血配置。`structures=false` 时只有核心生命、不放宝库，供测试隔离单位行为。

## 性能

空间查询按桶的环由近到远搜索并提前结束，结果与逐个比较一致（`test_sim.gd` 的空间等价检查）。部署扫描、传播攻击只查询敌方桶；分离用细桶。

最新基准（云端 Linux 单核，`tests/crowd_perf.gd`，人族对人族，电脑用 100000 矿物各买 130/131 组，连续 3 波）：平均 40 ms/步，最慢 120 ms/步，峰值 599 个单位。平均值低于 20 Hz 的 50 ms 预算，但峰值超出；手机 CPU 可能慢数倍，真机仍需验证。

## 保存与复现

- `user://settings.cfg`：音量、每个种族的最近兵营及可选单兵位置（`player/formation_<种族>`）、开局设置与种族选择（`match` 段，`economy_schema` 匹配时才读取自定义值）。
- `user://last_match.json`：规则版本、种子、开局设置覆盖（`settings`）、全部操作及其 tick（`actions`）、每波阵容与经济账本（`waves`）、经济事件、经济配置、初始矿物与最终结果。只保留最近一局，不上传。
- 单兵位置按购买组保存；无坐标阵容沿用旧出生算法。恢复设置时先按经济规则购买，再校验位置；新战报的排布动作不兼容旧版本程序，详见 [部队配置兼容约定](MOBILE_FORMATION.md)。
- `tests/replay.gd` 用相同种子和设置新建模拟，在对应 tick 前执行 `apply_action()`，推进到结束并比较结果；规则版本不一致或日志未完成时拒绝。相同引擎、相同数据版本是复现前提。

## 未来联机边界

未来以独立 Godot headless 进程运行同一模拟核心：客户端只上报兵营操作，服务端按身份、资源和占格校验后广播权威状态，客户端插值。不能信任客户端报送的伤害、资源、时间或胜负。房间、断线恢复与协议版本尚未实现，当前没有伪装成可用后端的空实现。
