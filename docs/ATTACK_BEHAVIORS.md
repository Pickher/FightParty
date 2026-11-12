# 攻击行为抽象（0.9.2）

兵种决定生命、移动、护甲和拥有哪些武器模式；武器模式保存伤害、加成、段数、持续时间、轮后等待及delivery参数；攻击行为决定如何投送和推进攻击。三者分别维护，多个兵种可直接选用相同的行为实现，不需要复制兵种AI。

| 攻击类型 | 实现 | 常用参数 | 当前例子 |
|---|---|---|---|
| 射弹 projectile | scripts/attacks/projectile_attack.gd | flight、seconds/speed、tracking | 特战队员、特工、坦克、雷神、维京；接触武器也使用零飞行的接触子方式 |
| 激光 beam | scripts/attacks/beam_attack.gd | tick_interval、switch_delay，伤害或healing | 医疗兵、哨兵、虚空辉光舰、基地反击 |
| 直线推进 line | scripts/attacks/line_attack.gd | pattern、length、speed、half_width、effect | 恶火、穿刺者、巨像 |

所有行为实现AttackBehavior公共接口：is_continuous区分连续作用与分段出手，tick处理连续作用，can_emit/emit处理一段出手，advance推进在场攻击，target_died处理失去目标，hit_count/expected_dps/skill_name提供类型对应的预估和简介。行为对象共享且不持有单位状态；单位、独立炮位、基地分别保存自己的纯字典时钟与目标。

统一注册点为scripts/attacks/attack_registry.gd的TYPE_SCRIPTS。注册顺序固定，保留原来射弹先于直线波的固定步结算顺序。底层ProjectileService/BeamService/LineService继续负责场上弹体、光束和轨迹数据，避免重写现有推进规则。AttackSequence只管理分段时间表，发射方式交给行为，不再写具体类型判断。兵种、医疗兵、地堡、基地均通过同一注册入口使用行为。

多段攻击、溅射及分圈、对甲加成、护盾/护甲与命中技能仍由公共时间表/命中结算处理，可与攻击类型组合；damage_type的physical/spell/true表示伤害减免规则，不是这里的攻击类型。

## 配置已有类型

射弹飞行方式flight为contact/fixed/distance。contact在实际挥击时检查接触范围；fixed固定延迟，seconds=0表示发射时立即命中；distance按发射距离/speed计算耗时。tracking控制追踪；目标死亡后范围弹保留最后落点。

```json
{"type":"projectile","flight":"fixed","seconds":0,"tracking":true}
```

```json
{"type":"projectile","flight":"distance","speed":25,"tracking":true}
```

激光仍按当前规则每0.5秒完整结算一次，切换目标先等待0.3秒再重新累计0.5秒。首次接敌0.5秒后首结算，换目标后0.8秒首结算；本次抽象不调整该节奏。模式attack_duration=0.5、hit_count=1、interval=0，治疗量使用模式healing而非单位属性。

```json
{"type":"beam","tick_interval":0.5,"switch_delay":0.3,"tracking":true}
```

直线推进的forward从自身向前传播固定长度，transverse在目标两侧横向扫射。同一个行为通过pattern参数支持穿刺者/恶火和巨像，无需分别复制逻辑。

```json
{"type":"line","pattern":"forward","length":5,"speed":15,"half_width":0.3,"effect":"flame","tracking":false}
```

## 新兵种与新类型

给新兵种增加attack_modes，填写模式数值并选择delivery.type即可复用；武器技能继续通过mode_id引用。模式不持有行为对象，快照仍是纯字典。

需要一种新机制时，在scripts/attacks目录继承attack_behavior.gd，实现所需生命周期方法，在TYPE_SCRIPTS注册一次，再给武器配置新的类型ID。可继承已有类型覆盖其中一个方法；专门的在场数据服务按需要添加。新增类型的Excel枚举和参数规则同步到tools/unit_workbook.py，不需要改BattleSim、基地或地堡的分发流程。

旧配置instant/fixed/distance/wave在武器构造时兼容映射到projectile/line，正式JSON和Excel统一使用三个类型名；飞行子方式单独放入flight。所有现有数值、激光0.5秒完整扣甲、雷神各模式、零耗时枪炮和坦克分圈溅射均保留。按用户要求，本次不运行Godot导入、模拟、测试、UI或打包。
