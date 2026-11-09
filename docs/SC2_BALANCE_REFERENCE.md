# 虫族与神族数值核对（0.8.0）

参考截至2026-11-09的《虚空之遗》正式服5.0.17对战规则，不使用战役/合作模式或PTR数值。

- [暴雪5.0.17正式补丁](https://news.blizzard.com/en-us/article/24309308/starcraft-ii-5-0-17-patch-notes)：最新明确修订优先。
- [暴雪5.0.15补丁](https://news.blizzard.com/en-us/article/24225313/starcraft-ii-5-0-15-patch-notes)：多数平衡回退基线。
- 基础武器/生命/属性按各兵种Liquipedia条目核对，并与[2026-06-27抓取快照](https://github.com/ysh020603/SC2_DATA_Agent/tree/main/data_sc2_260701/markdown)交叉比对。快照不是最新游戏客户端导出数据。
- 每段伤害=基础伤害+3×每级升级增量；对甲/标签加成按该字段自己的增量计算，不是把零攻数值乘3。生命护甲=基础护甲+3，神族护盾护甲=3。法术伤害不随三攻升级。
- 价格、每组数量、模型尺寸、碰撞半径、人族、建筑及腐族配置保持；新增蝗虫仅为0价、不可购买的召唤物。
- 三攻三防不等于所有专属科技均已研究。冲锋/闪烁/风暴等已有主动能力继续挂载；其他未默认研究的独立科技记录在技能核对页，刺蛇/潜伏者/巨像采用基础射程5/8/7，专属科技另有+1/+2/+2。
- 无轻甲/重甲标签的单位用armor_type=none表示“未分类”，并不代表没有护甲值；例如执政官仍有3点生命护甲与3点护盾护甲。

## 当前确定的普通武器与生命

伤害均为单段，括号加成为额外伤害。无普通攻击者的JSON间隔/接敌距离只是运行占位，Excel已留空标色。

| 兵种 | 生命/护盾 | 每段伤害 | 段数 | 额外伤害 | 间隔秒 | 射程格 | 护甲/盾甲 | 来源 |
| --- | --- | ---: | ---: | --- | ---: | --- | --- | --- |
| 跳虫 | 35/0 | 8 | 1 | — | 0.497 | 0.1 | 3/0 | [参考](https://liquipedia.net/starcraft2/Zergling_(Legacy_of_the_Void)) |
| 毒爆虫 | 30/0 | 22 | 1 | — | 1 | 0.25 | 3/0 | [参考](https://liquipedia.net/starcraft2/Baneling_(Legacy_of_the_Void)) |
| 蟑螂 | 145/0 | 22 | 1 | — | 1.43 | 4 | 4/0 | [参考](https://liquipedia.net/starcraft2/Roach_(Legacy_of_the_Void)) |
| 刺蛇 | 90/0 | 15 | 1 | — | 0.59 | 5 | 3/0 | [参考](https://liquipedia.net/starcraft2/Hydralisk_(Legacy_of_the_Void)) |
| 破坏者 | 120/0 | 22 | 1 | — | 1.14 | 6 | 4/0 | [参考](https://liquipedia.net/starcraft2/Ravager) |
| 穿刺者 | 190/0 | 26 | 1 | heavy+13 | 1.43 | 8 | 4/0 | [参考](https://liquipedia.net/starcraft2/Lurker_(Legacy_of_the_Void)) |
| 虫群宿主 | 160/0 | 0 | — | — | — | — | 4/0 | [参考](https://liquipedia.net/starcraft2/Swarm_Host_(Legacy_of_the_Void)) |
| 飞龙 | 120/0 | 12 | 1 | — | 1.09 | 3 | 3/0 | [参考](https://liquipedia.net/starcraft2/Mutalisk_(Legacy_of_the_Void)) |
| 感染虫 | 90/0 | 0 | — | — | — | — | 3/0 | [参考](https://liquipedia.net/starcraft2/Infestor_(Legacy_of_the_Void)) |
| 雷兽 | 500/0 | 44 | 1 | — | 0.61 | 1 | 5/0 | [参考](https://liquipedia.net/starcraft2/Ultralisk_(Legacy_of_the_Void)) |
| 巢虫领主 | 225/0 | 26 | 2 | — | 1.79 | 10 | 4/0 | [参考](https://liquipedia.net/starcraft2/Brood_Lord_(Legacy_of_the_Void)) |
| 先锋 | 100/50 | 11 | 2 | — | 0.86 | 0.1 | 4/3 | [参考](https://liquipedia.net/starcraft2/Zealot_(Legacy_of_the_Void)) |
| 追猎者 | 80/80 | 16 | 1 | heavy+8 | 1.34 | 6 | 4/3 | [参考](https://liquipedia.net/starcraft2/Stalker_(Legacy_of_the_Void)) |
| 哨兵 | 40/40 | 9 | 1 | shields+4 | 0.71 | 5 | 4/3 | [参考](https://liquipedia.net/starcraft2/Sentry_(Legacy_of_the_Void)) |
| 不朽者 | 200/100 | 26 | 1 | heavy+39 | 1.143 | 6 | 4/3 | [参考](https://liquipedia.net/starcraft2/Immortal_(Legacy_of_the_Void)) |
| 高阶圣堂武士 | 40/40 | 7 | 1 | — | 1.25 | 6 | 3/3 | [参考](https://liquipedia.net/starcraft2/High_Templar_(Legacy_of_the_Void)) |
| 执政官 | 10/350 | 34 | 1 | biological+13 | 1.25 | 3 | 3/3 | [参考](https://liquipedia.net/starcraft2/Archon_(Legacy_of_the_Void)) |
| 巨像 | 250/100 | 13 | 2 | light+8 | 1.07 | 7 | 4/3 | [参考](https://liquipedia.net/starcraft2/Colossus_(Legacy_of_the_Void)) |
| 干扰者 | 100/100 | 0 | — | — | — | — | 4/3 | [参考](https://liquipedia.net/starcraft2/Disruptor) |
| 虚空辉光舰 | 150/100 | 9 | 1 | heavy+4 | 0.36 | 6 | 3/3 | [参考](https://liquipedia.net/starcraft2/Void_Ray_(Legacy_of_the_Void)) |
| 航母 | 300/150 | 0 | — | — | — | — | 5/3 | [参考](https://liquipedia.net/starcraft2/Carrier_(Legacy_of_the_Void)) |
| 巢虫 | 20/0 | 7 | 1 | — | 0.57 | 0.1 | 3/0 | [参考](https://liquipedia.net/starcraft2/Broodling_(Legacy_of_the_Void)) |
| 拦截机 | 40/40 | 8 | 2 | — | 2.14 | 2 | 3/3 | [参考](https://liquipedia.net/starcraft2/Interceptor_(Legacy_of_the_Void)) |
| 蝗虫 | 50/0 | 13 | 1 | — | 0.43 | 3 | 3/0 | [参考](https://liquipedia.net/starcraft2/Locust_(Legacy_of_the_Void)) |

## 机制与范围取舍

先锋以狂热者为原型，穿刺者以潜伏者为原型。钻地兽改名虫群宿主，内部ID仍保留tunneler，避免破坏阵容/存档引用；旧dive技能移除，改为每43秒在自身附近生成2只地面蝗虫，存活18秒。原版的飞行与俯冲落地、宿主埋地暂未完整实现，已在表中标记。

虚空辉光舰去掉旧版持续蓄能，使用独立weapon_buff组件实现棱镜校准：额外+6对重甲、14.3秒、42.9秒冷却、移速倍率0.75。不朽者屏障为100、2秒、32秒冷却，并拦截触发的首次伤害。感染虫由定身改为减速75%及随目标持续伤害。哨兵与干扰者的护盾额外伤害走共用shield_bonus字段，单独作用于当次命中时仍存在的护盾，额外部分不会溢出伤害生命。

近战0.1/0.25/1等原版射程保留，新增可选range_from_edge，以模型接触边缘计算该武器攻击距离；仅相应虫/神近战配置启用，防止中心距离要求造成模型互相钻入。发现与锁定范围也匹配此口径；其他兵种原有中心距离规则不改。

神经寄生、微生物护罩、力场、幻象、反馈、融合、部分埋地/隐身与特殊地形等能力仅记录资料及待实现状态，没有把它们冒充为已实现。腐族本轮保持现状，没有新增实现。

## 明天填写表格

当前表为data/units/兵种配置.xlsx。黄色空白是未确认；灰色空白是不适用。批注注明运行时保留值，游戏JSON不写null或猜测性0。可以填写原属性/技能页对应格，也可以填写“待确认清单”D列；两个位置填不同值会报错。

“技能核对”页列出能力名称、参考参数、已接入/简化实现/待实现/未默认研究状态及链接，该页不直接生成技能实现。“待确认字段”隐藏页标识允许空白的路径，不能删除。来源与审核元数据在data/units/sc2_reference.json，确认后应同步清理对应标记，避免下一次生成又清空。

未确认重点包括：地刺/横扫几何与传播速度、顺劈/执政官分层溅射、部分法术时间口径、是否默认额外护甲科技、原有神族自然回盾参数。它们在运行JSON仍保留兼容值，因此本轮不能声称所有机制已经与原版完全一致。

本轮仅源码阅读、资料核对、数据/字体/表格写入，未运行导入校验、Godot导入、对战模拟、UI、回放、性能测试或APK打包。
