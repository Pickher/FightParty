# 0.6.0：技能组件与统一生命周期

每一种挂载技能都有独立的组件类，继承 `scripts/skills/skill.gd`。`skill_system.gd` 维护配置键到类的注册表，按单位 ID 创建、调度和移除实例。兵种继续使用原有 JSON，已有技能键和参数不用改名。

0.7.0 起兵种基础属性与当前资源由公共单位模型管理，详见 [UNIT_MODEL.md](UNIT_MODEL.md)。组件 owner 指向 Unit.state 的同一字典引用；可通过 sim.unit_model(owner) 取得实例。主动技能可用 can_pay_energy/pay_energy 共用能量池，自然回血优先配置 health_regen；regen 组件仍可作为额外恢复。

## 参数与状态如何独立

每个组件包含 `id`、`owner`、`config`、`state`。config 在挂载时深拷贝，state 为该实例自己的字典；两个单位即使挂同一个技能类，也不共享冷却、目标、扫描记录或武器缓存。组件只保存单位数据引用，不保存 sim 或每步 ctx，避免引用环。

组件实例存在 SkillSystem.instances 中，不直接塞入单位字典。单位的 `skill_states[技能键]` 是状态的深拷贝，可供画面和快照读取。少量旧字段（例如 siege_state、blink_ready_tick、yamato_target）通过显式 view_fields 白名单投影到单位字典，以兼容当前界面；这些是显示副本，不能用修改它们的方式修改技能的真实状态。状态中某个字段被删除时，其旧投影也会清除。

编辑 units.json 的参数后重启/新建对局，新实例就会使用新值。运行时可通过 `sim.skill_system.get_component(unit, "blink")` 取得具体实例；调整实例 config 只影响该实例，带缓存的武器组件应重新建局而不是绕过生命周期热改参数。

## 复用示例

给另一个兵种挂闪烁，只需在其配置中添加：

```json
"skills": {
  "blink": {
    "distance": 6,
    "cooldown": 9,
    "shield_ratio": 0.25
  }
}
```

它与追猎者使用同一个 blink.gd 类，但用 6 格、9 秒的独立参数。无需在兵种类或 BattleSim 中再写一份闪烁，也无需增加按兵种 ID 判断的分支。

## 独立组件清单

| 组件键/文件 | 行为 |
| --- | --- |
| deployment | 架设/埋地的部署门槛；两者机制相同，以参数和外观模式区分 |
| defender_zone | 前向扇形防卫，组件内部复用部署状态机服务 |
| healing | 后排治疗与避让 |
| stimulant | 扣血强化、攻速和移速倍率 |
| multi_attack | 每个攻击周期的独立打击次数 |
| line_attack | 用传播攻击替代普通直接命中 |
| weapon_switch | 按目标切换武器及切换计时 |
| yamato | 引导式大和炮 |
| regen | 脱战生命再生 |
| on_hit_slow | 命中施加减速 |
| delayed_area | 延迟/持续区域施法；风暴、胆汁、新星用参数复用 |
| blink | 后撤瞬移 |
| charge | 接敌冲锋 |
| dive | 自定义钻地切入 |
| aura | 对周围单位施加增益/减伤/伤害光环 |
| barrier | 独立屏障吸收与冷却 |
| dot | 命中附加持续毒伤 |
| ramp_damage | 连续攻击同一目标蓄能 |
| chain_attack | 多目标弹射 |
| suicide | 主动自爆和被击杀后的爆炸 |
| summon | 计时/命中召唤 |
| on_death | 死亡时触发配置的召唤/范围效果 |
| corpse_raise | 监听附近死亡并复生临时单位 |

这些组件的实现均在各自文件中。原 mobility.gd、combat_effects.gd、status_effects.gd 等混合入口已移除。

## 统一接口

| 阶段 | 接口与用途 |
| --- | --- |
| 挂载与移除 | configure、on_spawn、on_removed |
| 步初采样 | on_frame：光环等先统一采样，避免单位处理顺序改变本步增益 |
| 索敌前 | before_target：治疗、大和炮可接管本步行动；范围施法、防卫模式也在此推进 |
| 选定目标 | on_target：召唤、武器选择 |
| 行动前 | before_action：部署门槛、强化、主动自爆、位移 |
| 普通开火替代 | on_attack：返回 true 即接管普通攻击，例如传播波 |
| 完成一次普通打击 | after_attack：弹射、攻击基地时的命中召唤 |
| 实际命中 | on_hit：毒伤、减速、命中召唤；弹射后续命中也经过同一入口 |
| 受击吸收 | absorb：屏障等额外吸收层，之后进入基础护盾/护甲结算 |
| 存活与死亡 | on_survived、on_death、on_unit_death |
| 数据查询 | modify_weapon、modify_search、can_target、discovery_radius、target_priority、attack_count、attack_rate、movement_multiplier、damage_multiplier |

ctx 包含 sim、unit、dt 和本步共用的 hits、moves、heals、self_costs、base_hits、pending_slows、motion；完成索敌后再补 target、weapon、goal、distance、reach、can_act、armed、handled。组件向本步队列提交行动，不自行推进模拟时钟。

按 priority 排序，同优先级按技能键稳定排序。治疗与大和炮先接管，随后施法/模式，再处理部署、强化、自爆和位移。第一个接管行动/攻击的组件阻止后续同阶段替代行为；被动参数查询仍通过统一入口计算。基础攻击冷却每步消费一次，强化参数在行动前生效。

## 公共服务不是技能集合

services 下放的是所有组件可以复用的世界机制：

- deployment_service：无所有者的部署状态机，状态字典由调用组件持有。
- line_service、area_service：已经发出的传播波和区域实体推进。
- summon_service：召唤入场队列、寿命和母体依赖清理。
- status_service、slow_service：施加到其他单位身上的定身、毒伤、减速的统一存储/结算。
- shield_service：基础生命/护盾规则，护盾是兵种基础属性，不需要额外挂载主动技能。

服务不负责“这个兵种应该施放什么技能”。已发出的传播波保存命中组件的配置快照，发射者死亡后仍能通过同一组件接口施加效果；不会把活的组件对象或 sim 引用放进世界快照。

## 新增技能步骤

1. 在 skills 下创建继承 skill.gd 的文件，只实现需要的接口；状态放进 state，参数从 config 读取。
2. 在 SkillSystem.TYPES 注册技能键。
3. 在一个或多个兵种的 skills 中挂该键，填写不同参数。
4. 如需界面显示，优先读取 skill_states；兼容旧字段才显式填写 view_fields。

未知技能键会在挂载时明确报错，避免看似配置了却没有行为。deployment 与 defender_zone 不能同时挂载，因为它们代表互斥的两种部署策略。

## 本轮范围与验证

本轮是组件化重构，沿用 0.5.0 数值和自动战斗策略，没有把兵种数据改为另一套格式。拆分时修正了召唤队列计数误读尚不存在的 hp 字段；队列项不再被当成已入场单位读取。

按用户要求，未运行 Godot 导入、模拟、UI、重放、性能测试或打包。旧测试若直接修改 unit 中的技能显示字段，需要改为调整组件 state/配置，或者通过生命周期推进；旧版本通过记录不代表 0.6.0 已验证。


## 0.7.3 架设技能的可选武器

`deployment` 支持 `weapon`（架设武器参数）和 `mobile_can_attack`（未架设时可用普通武器，默认 false）。存在 weapon 时，UnitDefinition 将它规范化为独立 WeaponDefinition，按移动炮默认值合并覆盖。组件在 before_target 阶段推进架设状态，随后 modify_weapon 根据最终状态选择武器；本步刚完成架设时即可读取正确的伤害/射程/间隔。modify_search 使用架设武器的发现范围，架设扫描/保持也使用该武器的目标层与建筑规则。移动炮与架设炮共享单位冷却。

没有配置 weapon 的原有部署兵种继续沿用 before_action 流程，不能因为本次坦克改动而在移动模式攻击。收放和已架设状态移动倍率为 0；切换不修改组件外的兵种模板。当前坦克参数见 WORLD_UNITS.md。


2026-11-08 0.7.4：多段攻击使用当前武器的 hit_count 作为基础，再经 multi_attack 组件乘算；普通攻击和 line_service 都通过 SkillSystem.attack_count(sim, unit, active_weapon) 读取。巨像/截击机已迁移到 hit_count=2，保留组件以兼容旧配置。伤害、溅射、弹射及命中效果逐段运行，冷却每轮一次。


## 2026-11-09 0.7.5

新增 independent_weapons 独立组件。配置 weapons 为数组，每组含 id/label/count/weapon，UnitDefinition 将每组 weapon 规范化为 WeaponDefinition。组件在 before_target 消费普通攻击行动，挂载单位的基础武器不再额外开火。state.mounts 只保存组号和 AttackCycle 纯数据状态，可快照，不生成隐藏单位。不同炮位独立锁定/冷却，闲置炮位先分散、再按最近距离选敌；锁定不被重新分配。

普通Unit和独立炮位共用units/attack_cycle.gd，普通单段命中共用BattleSim.queue_direct_strike，保留hit_count、溅射倍率、护盾/护甲、命中/攻击后效果的结算入口。当前人族防御塔使用8+2组数，未来可直接配置其他武器/数量；这里不实现治疗、传播攻击或变形等武器专用技能的自动组合。
