# 兵种数值总表

> 由 `python tools/unit_table.py` 从 `data/units.json`（规则 0.13.0）生成，请勿手改；改数值后重新生成。
> 价格按组（每组 `spawn_count` 名），生命、护盾、伤害按个体。间隔单位秒，射程与速度单位格、格/秒。
> 攻击模式列：伤害（类型/标签加成）×每轮段数 / 轮后间隔 / 射程（可打的层，投送类型）。

## 人族 `terran`

| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |
|---|---|---|---|---:|---|---|---|---:|---|---|
| `rifle` | 特战队员 | 可用 | 220/0/0 | 3 | 55 | 轻 3 | 地 | 2.25 | 电磁步枪 9 / 0.86 / 5（地、空，projectile） | `stimulant` |
| `hellbat` | 恶火 | 可用 | 130/0/0 | 1 | 90 | 轻 5 | 地 | 4.25 | 火焰喷射 11（+14轻） / 2.5 / 4.5（地，line） | `line_attack` |
| `marauder` | 劫掠者 | 可用 | 560/0/0 | 4 | 125 | 重 4 | 地 | 2.25 | 震荡榴弹 13（+13重） / 1.5 / 6（地，projectile） | `stimulant`、`on_hit_slow` |
| `medic` | 医疗兵 | 暂时停用 | 380/380/0 | 1 | 78 | 轻 4 | 地 | 2.25 | 治疗光束 0 / 0 / 4，治疗 12（地、空，beam） | `healing` |
| `medivac` | 医疗运输机 | 可用 | 850/0/0 | 2 | 150 | 重 4 | 空 | 2.5 | 双束医疗 0 / 0 / 4，治疗 12（地、空，beam） | `medivac_healing` |
| `agent` | 特工 | 可用 | 750/0/0 | 1 | 125 | 轻 3 | 地 | 2.75 | 穿甲弹 13（+60重、+13轻） / 0.05 / 7（地、空，projectile）<br>狙击弹 30（+30轻） / 1.07 / 8（地、空，projectile） | `weapon_switch`、`combat_mobility` |
| `widow_mine` | 寡妇雷 | 可用 | 360/0/0 | 2 | 90 | 轻 3 | 地 | 2.8125 | 哨戒导弹 85（+30重） / 23 / 4，溅射 1.75（地、空，projectile） | `deployment`、`combat_mobility` |
| `mortar` | 坦克 | 可用 | 850/0/0 | 1 | 175 | 重 4 | 地 | 2.25 | 机动炮击 21（+14重） / 1.04 / 7（地，projectile）<br>攻城炮击 52（+33重） / 3 / 13，溅射 2.5（地，projectile） | `deployment` |
| `viking` | 维京 | 可用 | 990/0/0 | 2 | 180 | 重 3 | 空 | 2.25 | 对空导弹 26（+8重） / 2 / 11（空，projectile） | `combat_mobility` |
| `liberator` | 解放者 | 可用 | 1200/0/0 | 1 | 180 | 重 3 | 空 | 3.38 | 对空散射 10 / 1.29 / 5（空，projectile）<br>防卫炮击 160（+30重） / 2.36 / 17（地，projectile） | `defender_zone`、`combat_mobility` |
| `thor` | 雷神 | 可用 | 1250/0/0 | 1 | 400 | 特殊 4 | 地 | 1.88 | 高射炮击 23（+15重）×2 / 1 / 10（空，projectile）<br>雷神之锤导弹 9（+9轻）×4 / 1.9 / 14，溅射 1.2（空，projectile）<br>重炮射击 39（+11重）×2 / 1 / 7（地，projectile） | `weapon_switch`、`combat_mobility` |
| `battlecruiser` | 大和舰 | 可用 | 1200/0/0 | 1 | 550 | 重 6 | 空 | 1.875 | 对地激光炮组 11 / 0.16 / 6（地，projectile）<br>对空激光炮组 9 / 0.16 / 6（空，projectile） | `weapon_switch`、`yamato`、`mobile_attack`、`combat_mobility` |
| `terran_bunker` | 防御塔 | 结构体 | 500/0/0 | 1 | 1200 | 重 3 | 地 | 0 | 驻军特战队员 15 / 0.43 / 6（地、空，projectile）<br>驻军劫掠者 20（+20重） / 0.75 / 7（地，projectile） | `independent_weapons` |

## 虫族 `zerg`

| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |
|---|---|---|---|---:|---|---|---|---:|---|---|
| `zergling` | 跳虫 | 可用 | 300/0/0 | 4 | 50 | 轻 3 | 地 | 3.5 | 利爪撕咬 13 / 0.497 / 0.1（地，projectile） | `combat_mobility` |
| `baneling` | 毒爆虫 | 可用 | 110/0/0 | 1 | 35 | 无 3 | 地 | 3.5 | 酸液自爆 52 / 1 / 0.25，溅射 2.2（地，projectile） | `suicide` |
| `roach` | 蟑螂 | 可用 | 380/0/0 | 2 | 150 | 重 4 | 地 | 3 | 酸液喷吐 22 / 1.43 / 4（地，projectile） | — |
| `hydralisk` | 刺蛇 | 可用 | 540/0/0 | 3 | 100 | 轻 3 | 地 | 3.15 | 骨针射击 15 / 0.59 / 5（地、空，projectile） | `mobility_burst` |
| `ravager` | 破坏者 | 可用 | 260/0/0 | 1 | 160 | 无 4 | 地 | 3.85 | 等离子喷吐 22 / 1.4 / 6（地，projectile） | `delayed_area` |
| `piercer` | 穿刺者 | 可用 | 850/0/0 | 1 | 190 | 重 4 | 地 | 4.13 | 地刺穿透 26（+13重） / 1.75 / 12（地，line） | `deployment`、`line_attack` |
| `tunneler` | 虫群宿主 | 可用 | 800/0/0 | 1 | 160 | 重 4 | 地 | 2.9531 | 孵化支援（无普通攻击） 0 / 1 / 7（地，projectile） | `summon` |
| `mutalisk` | 飞龙 | 可用 | 120/0/0 | 1 | 120 | 轻 3 | 空 | 5.6 | 刃虫弹射 12 / 1.09 / 3（地、空，projectile） | `chain_attack` |
| `infestor` | 感染虫 | 可用 | 400/0/0 | 1 | 90 | 重 3 | 地 | 3.15 | 感染支援（无普通攻击） 0 / 1 / 10（地、空，projectile） | `delayed_area` |
| `ultralisk` | 雷兽 | 可用 | 700/0/0 | 1 | 500 | 重 6 | 地 | 4.13 | 巨刃横扫 44 / 0.61 / 1，溅射 1.4286（地，projectile） | `combat_mobility` |
| `brood_lord` | 巢虫领主 | 可用 | 1450/0/0 | 1 | 225 | 重 4 | 空 | 2.5 | 巢虫轰击 26×2 / 1.79 / 10（地，projectile） | `summon` |
| `broodling` | 巢虫 | 召唤物 | 0/0/0 | 1 | 20 | 轻 3 | 地 | 4.13 | 巢虫撕咬 7 / 0.57 / 0.1（地，projectile） | — |
| `locust` | 蝗虫 | 召唤物 | 0/0/0 | 1 | 130 | 轻 3 | 地 | 2.62 | 蝗虫喷吐 13 / 0.5 / 3（地，projectile） | — |
| `zerg_tower_cluster` | 爬虫防御群 | 结构体 | 500/0/0 | 1 | 2400 | 重 1 | 地 | 0 | 脊针爬虫 25（+5重） / 0.399 / 7（地，projectile）<br>孢子爬虫 15（+5 biological） / 0.249 / 7（空，projectile） | `independent_weapons` |

## 神族 `protoss`

| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |
|---|---|---|---|---:|---|---|---|---:|---|---|
| `vanguard` | 先锋 | 可用 | 250/0/0 | 1 | 200/100 | 轻 4 | 地 | 3.125 | 双刃斩击 22×2 / 0.92 / 0.1（地，projectile） | `charge`、`combat_mobility` |
| `adept` | 使徒 | 可用 | 280/0/0 | 2 | 70/70 | 轻 4 | 地 | 2.5 | 共鸣之刃 13（+15轻） / 1.38472 / 4（地，projectile） | `psionic_transfer`、`combat_mobility` |
| `stalker` | 追猎者 | 可用 | 180/0/0 | 1 | 80/80 | 重 4 | 地 | 4.13 | 粒子碎裂炮 16（+8重） / 1.34 / 6（地、空，projectile） | `blink`、`formation_pace` |
| `sentry` | 哨兵 | 可用 | 500/0/0 | 2 | 40/40 | 无 4 | 地 | 3.5 | 裂解光束 4.5 / 0 / 5（地、空，beam） | `aura`、`shield_restore` |
| `immortal` | 不朽者 | 可用 | 470/0/0 | 1 | 200/100 | 重 4 | 地 | 3.15 | 相位炮击 26（+39重） / 1.143 / 6（地，projectile） | `combat_mobility`、`shield_armor_buff` |
| `high_templar` | 高阶圣堂武士 | 可用 | 780/0/0 | 1 | 40/40 | 轻 3 | 地 | 2.82 | 灵能冲击 7 / 1.25 / 6（地，projectile） | `delayed_area`、`combat_mobility` |
| `archon` | 执政官 | 可用 | 450/0/0 | 1 | 10/350 | 无 3 | 地 | 3.94 | 灵能震荡 34（+13 biological） / 1.25 / 3，溅射 1（地、空，projectile） | `formation_pace` |
| `colossus` | 巨像 | 可用 | 1250/0/0 | 1 | 250/100 | 重 4 | 地 | 3.15 | 双束热能扫射 21（+11轻）×2 / 1.1 / 7（地，line） | `line_attack`、`combat_mobility` |
| `disruptor` | 干扰者 | 可用 | 1250/0/0 | 1 | 100/100 | 重 4 | 地 | 3.15 | 净化支援（无普通攻击） 0 / 1 / 13（地，projectile） | `delayed_area`、`combat_mobility` |
| `void_ray` | 虚空辉光舰 | 可用 | 300/0/0 | 1 | 150/100 | 重 3 | 空 | 3.3203 | 棱镜光束 9（+4重） / 0 / 6（地、空，beam） | `weapon_buff`、`combat_mobility` |
| `carrier` | 航母 | 可用 | 1600/0/0 | 1 | 300/150 | 重 5 | 空 | 2.62 | 舰载机支援（无普通攻击） 0 / 1 / 8（地、空，projectile） | `summon`、`combat_mobility` |
| `interceptor` | 拦截机 | 召唤物 | 0/0/0 | 1 | 40/40 | 轻 3 | 空 | 10.5 | 脉冲炮击 8×2 / 2.14 / 2（地、空，projectile） | `strafe_attack` |
| `protoss_photon_cannon` | 光子炮台 | 结构体 | 600/0/0 | 1 | 1500/1500 | 重 1 | 地 | 0 | 光子炮 20 / 0.124 / 9（地、空，projectile） | — |

## 腐族 `blight`

| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |
|---|---|---|---|---:|---|---|---|---:|---|---|
| `swarm` | 蜂群兵 | 可用 | 50/0/0 | 5 | 90 | 轻 0 | 地 | 3 | 蜂群撕咬 15 / 0.55 / 0.7857（地，projectile） | — |
| `rotling` | 腐仆 | 可用 | 50/0/0 | 4 | 55 | 无 0 | 地 | 2.5 | 腐爪攻击 12 / 0.46 / 0.7857（地，projectile） | — |
| `splitter` | 分裂尸 | 可用 | 75/0/0 | 1 | 200 | 轻 0 | 地 | 2.125 | 裂尸挥击 18 / 0.8 / 0.7857（地，projectile） | `on_death` |
| `bloater` | 膨胀者 | 可用 | 75/0/0 | 1 | 270 | 轻 0 | 地 | 1.625 | 膨胀冲击 15 / 1 / 0.7857（地，projectile） | `on_death` |
| `spitter` | 喷吐者 | 可用 | 75/0/0 | 1 | 150 | 轻 0 | 地 | 2.125 | 毒液喷吐 21（+9重） / 0.8 / 5（地、空，projectile） | `dot` |
| `fly_swarm` | 腐蝇群 | 可用 | 75/0/0 | 3 | 135 | 轻 0 | 空 | 3.125 | 腐蝇啃噬 15 / 0.6 / 2（地、空，projectile） | — |
| `spore_drifter` | 孢子漂浮体 | 可用 | 100/0/0 | 1 | 300 | 轻 0 | 空 | 1.625 | 孢子射击 30 / 0.86 / 7，溅射 1.0714（空，projectile） | `on_death` |
| `abomination` | 缝合巨尸 | 可用 | 175/0/0 | 1 | 900 | 重 3 | 地 | 1.75 | 巨尸劈砍 45 / 1 / 0.9286，溅射 1.0714（地，projectile） | — |
| `plague_herald` | 瘟疫使者 | 可用 | 125/0/0 | 1 | 200 | 轻 0 | 地 | 1.875 | 瘟疫支援（无普通攻击） 0 / 1 / 5（地，projectile） | `aura` |
| `gravedigger` | 掘墓人 | 可用 | 125/0/0 | 1 | 200 | 轻 0 | 地 | 1.875 | 复生支援（无普通攻击） 0 / 1 / 5（地，projectile） | `corpse_raise` |
| `brood_mother` | 腐化之母 | 可用 | 250/0/0 | 1 | 430 | 重 3 | 地 | 1.875 | 孵化支援（无普通攻击） 0 / 1 / 8（地，projectile） | `summon` |

## 中立结构 `neutral`

| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |
|---|---|---|---|---:|---|---|---|---:|---|---|
| `gate_tower` | 基地防御模块 | 结构体 | 0/0/0 | 1 | 5000 | 重 0 | 地 | 0 | 基地防御光束 300 / 0 / 8（地、空，beam） | — |
| `treasury` | 宝库 | 结构体 | 0/0/0 | 1 | 5000/1000 | 重 3 | 地 | 0 | 宝库守卫炮 10 / 1 / 4.2857（地、空，projectile） | — |
| `tower` | 防御塔 | 结构体 | 500/0/0 | 1 | 1500 | 重 3 | 地 | 0 | 防御炮击 70 / 1.2 / 8.5714（地、空，projectile） | — |
