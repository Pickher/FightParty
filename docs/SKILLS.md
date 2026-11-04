# 可复用技能配置（0.5.0）

每个 `data/units.json` 兵种可添加 `skills` 字典。未配置技能时使用普通移动、索敌和攻击。技能实现位于 `scripts/skills/`；状态与计算属于模拟层，外观由 `main.gd` 绘制。

## 已支持的技能

| 配置键 | 用途 | 参数 |
| --- | --- | --- |
| `deployment` | 展开后攻击，收起后移动 | `deploy_seconds`、`pack_seconds`：转换秒数；`deploy_enemy_threshold`：立即展开人数阈值 X，需严格大于 X；`scan_seconds`：少量敌人连续两次确认间隔；`hold_range_multiplier`：检查外围接近敌人的射程倍率；`mode`：`siege`/`burrow` 外观 |
| `line_attack` | 沿固定路径逐步推进，到达才伤害 | `pattern`：`forward`/`transverse`；`length`：路径长度，默认兵种 range；`speed`：传播速度；`half_width`：路径半宽；`effect`：`spike`/`beam` 外观 |
| `multi_attack` | 一次攻击分别打击多次，共享一次冷却 | `count`：次数，默认 1，巨像为 2 |
| `healing` | 跟随后排、躲避敌军、治疗友军 | `heal`：单次治疗；`follow_distance`：前排后方距离；`danger_distance`：敌军后方安全距离；使用兵种 range/interval 作为治疗距离/间隔 |
| `weapon_switch` | 多把武器，按目标自动切换（0.3.0） | `switch_seconds`：换武器耗时，期间不能开火；`weapons`：武器数组，每把可覆盖 `damage`、`bonus`、`interval`、`range`、`splash`、`target_layers`、`attacks_base`，并带 `id`、`label` |
| `regen` | 脱战后自动回血（0.3.0） | `delay`：最后一次受伤后多少秒开始；`per_second`：每秒回复生命 |
| `yamato` | 引导后的单体重炮（0.3.2） | `damage`：伤害；`range`：射程；`channel_seconds`：引导秒数；`cooldown_seconds`：冷却秒数；`min_target_hp`：目标生命+护盾至少多少才开炮 |

必填参数按表完整填写；仅 `line_attack.length`、`multi_attack.count` 有默认值。正向直线从自身向目标方向走满 length；横向直线以开火瞬间目标位置为中心，垂直于攻击方向。横向多击从两端交替起始，每条都走完全长。

`damage` 是每击伤害，`interval` 是整组攻击间隔，`range` 是启动攻击/锁定的距离。每条传播轨迹独立记录命中，不保证命中目标。没有 `line_attack` 的多重攻击会在开火步分别结算普通单体/溅射伤害；有此技能时使用传播判定，不使用 `splash` 圆形溅射。

## 多武器、回血与护盾（0.3.0）

`weapon_switch.gd`：索敌时用兵种顶层的 `range`、`target_layers`（应填写各武器的并集），选定目标后对每把能打该层的武器计算“预期每击伤害 ÷ 间隔”，取最高者，同分保留当前武器；没有敌军目标（攻击基地）时用第一把 `attacks_base` 不为 false 的武器。换到另一把武器后 `switch_seconds` 内不能开火，产生 `weapon_switch` 事件。合并后的武器按“兵种:序号”缓存在 `sim.mode_weapons`。特工用它在穿甲弹（克重甲）与狙击弹（克轻甲）之间切换，1.5 秒切换期是它的破绽；雷神的对地重炮与对空导弹切换为 0 秒。

```json
"weapon_switch": {
  "switch_seconds": 1.5,
  "weapons": [
    { "id": "armor_piercing", "label": "穿甲弹", "damage": 30, "bonus": { "heavy": 60 }, "interval": 1.5 },
    { "id": "precision", "label": "狙击弹", "damage": 30, "bonus": { "light": 30 }, "interval": 1.07 }
  ]
}
```

`regen.gd`：单位最后一次受伤（`last_hit_tick`）`delay` 秒后，每步回复 `per_second × 0.05` 生命，封顶最大生命。蟑螂为 3 秒、20/秒；缝合巨尸为 5 秒、8/秒。

护盾不是技能，而是兵种顶层的 `shield` 数值，由 `shield.gd` 处理：出生时初始化；每击的加成后伤害先由护盾全额吸收（不减护甲值），溢出部分再减护甲值进入生命；距上次受伤 `rules.shield_regen_delay` 秒后按 `shield_regen_per_second` 恢复。治疗不恢复护盾。

## 强化剂与命中减速

```json
"skills": {
  "stimulant": {
    "health_cost_ratio": 0.15,
    "duration": 20,
    "attack_multiplier": 1.3,
    "speed_multiplier": 1.5
  },
  "on_hit_slow": {
    "duration": 2,
    "speed_multiplier": 0.5
  }
}
```

`stimulant.gd` 在敌军进入攻击范围且部署限制解除后自动施放。生命代价基于最大生命，严格剩余大于代价才允许使用；持续期间不叠加、不刷新，期满后按同一条件重新判断。当前生命和治疗不会因单位处理顺序提前变化。攻速倍率用于消耗基础攻击冷却，移速倍率用于移动；技能状态保存在单位快照中，暂停自然停止计时。基础数据不被增益改写。

`on_hit_slow.gd` 在命中时记录待施加状态，统一结算后开始影响后续移动。重复命中不叠乘，取最强减速和最晚到期时间；同配置命中即刷新两秒。若未来配置不同强度，同名减速当前也采用此合并规则。普通、多重、溅射、传播攻击都可携带；传播波保存发射时配置，允许发射者死亡后仍命中施加。不会影响基地或改变伤害。

这两项可与攻击类技能组合；治疗目前替代攻击流程，挂载强化剂不会自动给医疗兵生成施放行为。治疗单位仍可以被敌方减速。增益和减速倍率相乘，架设/埋地的禁止移动限制优先。

## 巨像的组合

```json
"skills": {
  "line_attack": {
    "pattern": "transverse",
    "length": 180,
    "speed": 180,
    "half_width": 14,
    "effect": "beam"
  },
  "multi_attack": { "count": 2 }
}
```

## 穿刺者的组合

```json
"skills": {
  "deployment": {
    "deploy_seconds": 1.0,
    "pack_seconds": 0.75,
    "deploy_enemy_threshold": 2,
    "scan_seconds": 0.5,
    "hold_range_multiplier": 1.2,
    "mode": "burrow"
  },
  "line_attack": {
    "pattern": "forward",
    "speed": 260,
    "half_width": 14,
    "effect": "spike"
  }
}
```

给其他攻击兵种挂载 `deployment` 即可使用相同展开限制；给穿刺者增加 `multi_attack` 则可产生多条独立地刺。`burrow` 当前只改变展开外观，不提供隐身。

## 调度与扩展约束

1. `healing` 当前是替代攻击的支援行为，优先执行并结束该单位本步行为；不能通过同时配置其他技能得到“边治疗边攻击”或“架设后治疗”。
2. 普通攻击单位先索敌，再经过 `deployment` 的移动/开火限制；允许攻击敌军时先判断强化剂，再按增益倍率递减冷却。允许开火时消耗一次冷却，按 `multi_attack` 生成多击。已有展开状态只限制单位，已发出的攻击波仍继续。
3. 所有单位决定移动后，推进旧攻击波并判断命中。治疗、伤害、自身生命代价、减速和移动最终统一应用，保持双方同时行动；同一步各击分别产生 `attack_hit`，HP 使用总伤害结算。

新增兵种复用上述能力只需挂载配置，并补充价格/数值、UI 外观与 AI 选择。新增突进、隐身或变形等能力时，需要实现独立技能模块，并在生成单位、移动/索敌或攻击阶段接入相应调用，补充行为测试。任意填写一个新技能名不会自动获得功能，当前没有通用触发器或插件注册系统。

0.1.5 的顶层 `deploy_seconds` 等字段已迁至 `skills.deployment`，治疗字段迁至 `skills.healing`，`spike_speed`/`spike_half_width` 改为 `skills.line_attack.speed`/`half_width`。自定义旧兵种配置需一并迁移；规则版本 0.1.6 会拒绝旧版本战报重放。

## 大和炮（0.3.2）

`yamato.gd` 在每步普通行动之前调用。冷却就绪时，在 `range` 内找生命+护盾不低于 `min_target_hp` 的敌方单位（先非结构体，再按生命+护盾从高到低，同分 ID 小者），记下 `yamato_target` 与开炮 tick，发出 `yamato_charge` 事件。引导期间及开炮那一步，该单位不移动、不走普通攻击流程（普通冷却仍照常恢复）。到时若目标仍在场，按普通命中排队 `damage` 原始伤害（不吃护甲类型加成，经护盾与护甲值结算），发出 `attack_hit` 与 `yamato` 事件，并设置 `yamato_ready_tick`；目标已死亡则取消、不消耗冷却。锁定后不再检查射程。可与 `weapon_switch` 组合，大和舰就是这样配置的：

```json
"yamato": { "damage": 720, "range": 280, "channel_seconds": 2.0, "cooldown_seconds": 71.0, "min_target_hp": 300 }
```

## 防卫区域与武器模式

`skills.defender_zone` 组合通用部署状态机与固定圆形警戒区，不需要同时挂 `deployment`。参数包含 `deploy_seconds`、`pack_seconds`、`deploy_enemy_threshold`、`scan_seconds`、`hold_range_multiplier`，再加 `radius`（圆半径）和 `weapon`（防卫模式武器覆盖字段）。展开时固定中心，收起后才能重新圈地。

解放者的 `weapon` 覆盖 damage=160、interval=2.56、range=476、splash=0、target_layers=[ground]、attacks_base=false。基础武器配置用于飞行模式。单位自身 `layer=air` 始终保持，所以对地防卫不等于降落。

当前该技能的自动策略专门在对空武器与对地防卫区之间切换，可以给其他具有相同模式规则的兵种复用；不是任意多形态的通用变形编辑器。不要同时挂载另一套 deployment 或 healing，以免争用状态或支援行为优先跳过模式调度。

解放者配置示例（基础属性仍在兵种顶层）：

```json
"layer": "air",
"target_layers": ["air"],
"attacks_base": false,
"skills": {
  "defender_zone": {
    "deploy_seconds": 2.9,
    "pack_seconds": 1.5,
    "deploy_enemy_threshold": 2,
    "scan_seconds": 0.5,
    "hold_range_multiplier": 1.2,
    "radius": 140,
    "mode": "defender",
    "weapon": {
      "target_layers": ["ground"],
      "attacks_base": false,
      "damage": 160,
      "interval": 2.56,
      "range": 476,
      "splash": 0
    }
  }
}
```

对空能力是配置属性（`target_layers`），新增兵种无需在索敌逻辑中添加 ID 分支。0.3.0 的完整对空名单见 [DESIGN.md](DESIGN.md) 兵种表的“层 → 目标”列；每个种族都有可用的对空单位。

## 0.4.0 格数与防卫扇形

旧示例的像素式距离已迁移为“格”。当前 defender_zone 使用 shape=sector、angle_degrees=40、weapon.range=8，不再读取 radius 或存储 defender_center。技能扫描与开火同属前向扇形，外围保持范围为 8×1.2=9.6 格。

weapon_switch.policy=air_superiority 用于雷神，preferred_layer=air 控制未锁定时优先对空，light_air_threshold=3 与 cluster_radius=2.5 控制成群轻甲模式。weapons 顺序为高爆单体对空、轻甲溅射对空、后备对地。数值与边界见 [WORLD_UNITS.md](WORLD_UNITS.md)。

spawn_count 与 size 是单位基础字段，而不是需要单独调度的技能；各个个体仍独立使用自己的技能和状态。

## 0.5.0 预留技能实现

本轮技能模块、兵种行为、状态和召唤时序，以 [ROSTER_SKILLS.md](ROSTER_SKILLS.md) 为准。新增实现未运行验证；旧文中的 stub 清单为历史状态。
