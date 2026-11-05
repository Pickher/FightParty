# 0.7.0 公共单位模型

所有普通兵、召唤物和防御建筑共用 `UnitDefinition + Unit + WeaponDefinition`，差异来自数据和独立技能组件。三个类均继承 RefCounted，不依赖场景节点。无需为每个兵种复制一个子类。

## 三个类的职责

- `scripts/units/unit_definition.gd`：兵种模板。最大生命、护盾、能量、初始能量、移速、护甲、体积、种族、空地层、单位类型、标签、自然恢复和武器/技能配置。每局每个兵种一份，构造后按只读使用。
- `scripts/units/unit.gd`：每个战场单位一份实例。当前生命/护盾/能量、位置、受击/扣能量时间、攻击阶段及兼容状态字典；负责公共资源、恢复和攻击时序。
- `scripts/units/weapon_definition.gd`：武器模板。伤害、类型、加成、射程、间隔、前后摇、溅射及可攻击目标层。换武器和解放者防卫武器同样经过此类规范化。

`BattleSim.definitions[kind]` 保存模板，`BattleSim.unit_instances[id]` 保存单位实例。`sim.unit_model(unit)` 从旧字典接口取得实例。

## 一份状态，两个访问接口

现有技能、空间桶和画面需要字典，因此 `spawn_unit()` 仍返回 `Unit.state`，`sim.units` 和 `sim.by_id` 仍持有这份字典。它与实例内部状态是同一引用，不是复制后定期同步的第二份数据：

```gdscript
var unit: Dictionary = sim.spawn_unit(0, "rifle", Vector2(20, 60))
var model = sim.unit_model(unit)
model.hp -= 10.0  # unit.hp 随之变化
unit.hp -= 5.0   # model.hp 也立即可读
```

实例属性写入会限制资源上下限；旧字典接口的写入仍需调用方遵守公共结算规则。新代码优先调用实例方法。技能的独立 `state` 仍归技能组件，不合并进模板；画面字段仍按白名单投影。

快照调用 `Unit.snapshot()` 深拷贝纯数据，不输出对象引用。死亡/到期/失去母体后，技能完成移除回调，再从实例表删除单位。不保存 Unit → Sim 的引用。

## 公共配置字段

旧 JSON 字段继续支持，避免商店/AI/表格导入器立即迁移。读取时生成规范化模板和配置视图；`hp/shield/energy` 在配置中是上限，在实例状态中是当前值。

| 分类 | 配置字段 | 含义 |
| --- | --- | --- |
| 资源 | hp、shield、energy、initial_energy | 最大生命/护盾/能量，出生能量；无护盾/能量设 0 |
| 防御 | armor_type、armor、shield_armor | 护甲类型、生命护甲和护盾护甲 |
| 移动/体积 | speed、size | 格/秒、宽×高 |
| 分类 | race、layer、unit_type、tags | 种族、ground/air、unit/summon/structure、多标签 |
| 回血 | health_regen、health_regen_delay | 每秒恢复量、最后一次受击后的等待秒数 |
| 回盾 | shield_regen、shield_regen_delay | 每秒恢复量、最后一次受击后的等待秒数 |
| 回能量 | energy_regen、energy_regen_delay | 每秒恢复量、最后一次实际扣能量后的等待秒数 |
| 武器 | damage、damage_type、bonus、bonus_tags | 基础伤害、类型、护甲类型加成、标签加成 |
| 攻击时间 | interval、windup、backswing | 周期间隔、前摇、后摇，单位秒 |
| 命中范围 | range、splash、target_layers | 射程、圆形溅射半径、可攻击空地层 |
| 建筑目标 | attacks_base、attacks_structures | 是否能攻击基地/其他建筑 |

所有存活单位每步统一恢复，资源不超过上限；死亡单位不恢复。蟑螂的 20/秒（受击后 3 秒）、缝合巨尸的 8/秒（受击后 5 秒）从原 `regen` 技能迁入基础属性，避免重复恢复。独立 `regen` 技能仍可用作额外被动恢复，与基础恢复相加。

当前有护盾单位沿用 7.5/秒、受击后 7 秒的参数，现在可以逐兵种修改；全局规则只作为未填写字段的兼容默认值。现有兵种能量及回能量暂设 0，主动技能默认费用 0，不在本次结构迁移中重新平衡施法频率。

## 标签与伤害

`tags` 允许多选 biological（生物）、mechanical（机械）、psionic（灵能）、caster（施法）、massive（巨型）等；可继续添加 scout（侦察）等标签。模板自动加入自身空地层、护甲类型和单位类型标签。重甲 `heavy` 与巨型 `massive` 相互独立。标签本身不自动赋予技能。

用 `sim.has_tag(unit, "biological")` 或 `model.has_tag("biological")` 查询。`bonus.light/heavy` 保留现有加成；`bonus_tags` 可配置对生物、机械等的额外伤害，匹配多个标签时逐项相加。

普通、直线传播和弹射武器共用伤害属性：physical 按护甲结算，spell 跳过生命/护盾护甲，true 还跳过远程光环减伤。三者仍先经过技能屏障与护盾，true 不代表无视所有防御。旧区域技能的 ignore_armor 仍可用，显式 damage_type 优先。现有武器保留 physical，既有法术效果沿用原配置。

传播攻击仍由 line_attack 技能及世界服务负责，发射时保存武器类型/加成快照；攻速不会改变地刺传播速度或强制命中目标。

## 攻击时序

`idle → windup → 发射/伤害 → backswing → idle`。

interval 是两次攻击启动的最短间隔，包含前后摇，不是三者相加。若配置 interval 小于 windup + backswing，模板会提高到两者之和。例：interval=1.0、windup=0.2、backswing=0.3，0.2 秒时开火，0.5 秒时动作恢复，1 秒时可以启动下一次攻击。

前摇内换目标、目标离开射程/死亡、换武器、架设或其他技能接管行动，都会取消此次未发射攻击并允许重新准备；首次开火才写入锁定目标。后摇阻止普通移动，剩余攻击冷却允许移动；特殊位移技能仍能接管行动。目标锁定仍遵循“开火后保持，目标死亡或离开射程后重新寻找”。

攻速倍率同时加快间隔、前摇和后摇。时序受固定步精度约束。现有所有武器前后摇默认 0，保留之前的即时出手节奏。双重攻击保持由 multi_attack 组件决定，在一次开火事件中处理两击。

## 配置能量的例子

以下是给现有施法兵种增添能量限制的局部配置示例，并非本轮自动套用的数值：

```json
{
  "energy": 200,
  "initial_energy": 75,
  "energy_regen": 0.5625,
  "energy_regen_delay": 0,
  "skills": {
    "delayed_area": {
      "energy_cost": 75
    }
  }
}
```

在原技能配置中增加 energy_cost，保留伤害、范围、冷却等其余字段。治疗、强化剂、闪烁、冲锋、突入、延迟区域、大和炮、需触发的光环、屏障和定时召唤，已在实际触发点接入扣费。能量不足不启动效果/冷却；持续技能仅在启动时扣一次，治疗每次治疗扣一次，召唤只有实际排入队列才扣费。大和炮引导启动时扣费，中断不返还。被动命中、死亡和常驻光环不自动收费。

新技能在确认目标和冷却符合条件后调用 `pay_energy(sim)`；复杂技能可先用 `can_pay_energy(sim)` 判断。二者共用所属单位的能量池。能量上限非零时，战场近景显示紫色能量条。

## 后续扩展与验证状态

通常新增兵种只添加一份 JSON 模板和技能组合；新武器可使用顶层旧字段或 weapon 子对象（后者优先）。特殊能力继续作为技能组件注册，不需要复制单位生命周期。

本轮按用户要求未运行 Godot 导入、模拟、UI、重放、性能检查或打包，也未新增自动测试。此前版本的测试通过记录不适用于 0.7.0。后续用户要求验证时，应重点覆盖资源上限/恢复延迟/共用能量、前摇取消与锁定、后摇与移动、攻速倍率、多武器切换、传播伤害属性及召唤/死亡的实例清理。修改模板的测试夹具应在创建 BattleSim 前配置 Catalog.extra_units，不能依赖运行中改写 catalog 来变更已有实例模板。
