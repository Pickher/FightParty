# 沙漠风暴三族基础兵种待办

核对基线为 FightParty `cloud/test` 的 `f27ab5d`（v0.13.11）。本页是[项目待办](PROJECT_BACKLOG.md)中 X01 的缺兵清单和 R04、R05、R11 的机制核对清单。勾选框供排期和验收使用。

| 种族 | 当前可购 | 当前商店中用来对照的单位 |
| --- | ---: | --- |
| 人族 | 13 | 特战队员、恶火、恶蝠、劫掠者、医疗运输机、特工、寡妇雷、坦克、维京、维京机甲、解放者、雷神、大和舰 |
| 虫族 | 11 | 跳虫、毒爆虫、蟑螂、刺蛇、破坏者、穿刺者、虫群宿主、飞龙、感染虫、雷兽、巢虫领主 |
| 神族 | 11 | 先锋、使徒、追猎者、哨兵、不朽者、高阶圣堂武士、执政官、巨像、干扰者、虚空辉光舰、航母 |

原图开局允许玩家只用「基石兵种和技能」。核对时从三族建造按钮和科技条件追到生产建筑，再按普通波次的建筑索引、战术偏移找出实际单位。原图同时收录了指挥官、虚数强化和召唤物，单凭一个单位名或「基石」前缀不足以判断招募资格。例如普通先知和沃拉尊先知是两个不同单位，虚数辉光舰则继承了基石前缀。[阵营选择](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L8587) · [两种先知的归属](../reference/desert-storm/zhCN.SC2Data/LocalizedData/ObjectStrings.txt#L13969) · [普通与虚数的出兵分支](../reference/desert-storm/MapScript.galaxy#L7472) · [普通波次创建单位](../reference/desert-storm/MapScript.galaxy#L7731)

项目侧按商店实际可购条件核对，共 35 种。巢虫、蝗虫、拦截机随母体登记，基地、驻军、防御塔和腐族不计入这张表。普通生产建筑的升级、附加部署和下波战术在下文标明，便于决定它们在 FightParty 里由哪个入口操作。[商店筛选](../scripts/catalog.gd#L39) · [运行时名册](../data/units.json) · [参考包及依赖范围](../reference/desert-storm/README.md)

## 待补兵种

按原图中能单独取得的普通出兵选择计算，共确认 **37 项缺口**。人族 12 项包括两型各有生产入口的铁鸦。虫族 12 项包括 10 个家族及飞蛇的两条付费进化。神族 13 项包括 12 个出兵选择及刚毅不朽者升级。这个数包括主巢加购的王虫。同一生产设施的免费战术切换随本体列出。另有两个神族单位的解锁条件待核。

### 人族待补单位

普通生产建筑对应 12 项缺口。两座建筑分别生产两型铁鸦，同一工厂可选的两种飓风弹舱合为一项。[普通生产建筑索引][T-prod] · [现有兵种][T-units]

- [ ] **赫克** `HERC`。用抓钩切入前线，按原图触发濒死免伤和回满生命。[单位说明][T-herc]
- [ ] **收割者** `Reaper`。高速对地步兵，脱战后快速回血。[单位说明][T-reaper]
- [ ] **监测飞船** `Blimp`。接入空中巡逻、探测与反隐支援。[飞船行为][T-blimp]
- [ ] **女妖** `Banshee`。接入隐形对地攻击，和探测支援一起验收进出探测范围时的索敌结果。[隐形能力][T-banshee]
- [ ] **飓风** `CycloneNormal`。工厂可选通用弹舱（对地、对空，对空射程较远）或速射弹舱（仅对地）。[两种配置][T-cyclone] · [出兵映射][T-cyclone-spawn]
- [ ] **征服者** `SiegeTank2`。作为坦克的另一生产选择，架设后持续造成小范围伤害，并有近距离盲区。[部署与武器][T-conqueror]
- [ ] **自由天使** `Liberator2`。部署后优先轰击能对空的地面敌人，防区清空后等待再收起。[索敌与收放][T-angel]
- [ ] **浮游铁鸦** `Raven`。部署定点靶机，拦截符合条件的敌方弹道。[生产入口][T-ravens-prod] · [单位说明][T-ravens]
- [ ] **磁矩铁鸦** `RavenNew`。用干扰矩阵瘫痪目标，以反护甲导弹削减一片敌人的护甲。[星港附属建筑](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L11081) · [单位说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3919)
- [ ] **矿骡** `MULE`。战场上免费维修友军机械，多台可合修。轨道站另可选择析象扫描。[战地维修与扫描][T-mule]
- [ ] **掠食者** `Predator`。攻击自身周围的地面敌人。[范围攻击][T-predator]
- [ ] **战列镭光妲娔**（原图名，`LaserDrill`）。作为能移动的重型地面战车加入，三连发可分击前方最多三个地面目标。[普通 SCV 建造入口][T-drill-prod] · [武器说明][T-drill]

### 虫族待补单位

普通科技树能部署下列 10 个缺失家族。其中王虫由主巢加购，飞蛇另有两条付费进化。眼虫的两种生产配置、跳虫和爆虫的战术变体各归本体。运行时共有 11 种可购虫族兵种，另有巢虫和蝗虫两种召唤物。[建造条件](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L10164) · [生产索引](../reference/desert-storm/Base.SC2Data/GameData/UpgradeData.xml#L2591) · [Galaxy 单位映射](../reference/desert-storm/MapScript.galaxy#L35436) · [当前名册](../data/units.json#L1537)

- [ ] **幼雷兽** `Pygalisk`。补轻甲近战前排，保留角质层外壳和对重型单位的优势。[部署](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3174) · [生产建筑被动](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L45340)
- [ ] **眼虫** `Overseer / Overseer3`。提供空中探测，并让玩家选择下一波是否带超距视界。开启后固定位置、扩大视野和探测范围。[普通建筑入口](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L10261) · [两种出场配置](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3750)
- [ ] **王虫** `Overlord`。由主巢付费追加部署，提供无武装空中掩护。[主巢说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3233) · [购买能力](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L1079) · [王虫用途](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3825)
- [ ] **虫后** `Queen`。能对地对空、以哺液治疗友方生物，并沿途铺菌毯。与菌毯虫共用菌毯对虫族地面部队的移速效果。[技能](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L28039) · [菌毯规则](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3438)
- [ ] **菌毯虫** `Zergling22`。能向前线铺设菌毯，死亡时孵出巢虫，后者可复用现有召唤物。[普通部署](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3251) · [死亡效果](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4392)
- [ ] **腐化者** `Corruptor`。对空、克制重型单位，以腐化提高目标所受伤害，可付费进化为已有的巢虫领主。[武器和进化](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3158) · [普通部署](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3289)
- [ ] **爆蚊** `Scourge`。成群部署，对单一空中目标自毁，高仇恨。相邻敌机不吃本次爆炸。[部署](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3287) · [普通型和范围型对照](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4032)
- [ ] **飞蛇** `Viper`。攻坚战术使用对空孢子、向友军空中单位释放寄生弹。支援战术使用蔽目毒云和绑架。[原图说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4241)

  - [ ] **瘴化蛇** `Viper_ZW`。付费进化后保留蔽目毒云，可吞噬友军生命回能。[普通进化入口](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L44625)
  - [ ] **猎首蛇** `Viper_CT`。付费进化后保留绑架，可吞噬友军生命回能。[两条进化的出兵映射](../reference/desert-storm/MapScript.galaxy#L35628)
- [ ] **猎手龙** `BrutaliskHunter`。实现地面巨兽的超远程对空支援与对地武器，分别验证两类目标的射程。[普通部署](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3192) · [武器与对空 AI](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L21065)
- [ ] **伽迪恩守护者** `SS_SwarmGuardian`。补远程对地范围伤害、吸收部分技能伤害并回血，以及优先攻击对空火力或靠近友军的敌人两种炮击战术。[普通建造条件](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L10241) · [技能](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4021) · [战术](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4357)

### 神族待补单位

现有 11 个常规可购单位。先锋对应狂热者。使徒已有支援、后撤两种传送战术。航母的拦截机已经是战场实体。下列每一项代表一个缺少的出兵选择，幻象、召唤物与同兵种的战术设置随母单位验收。[现有单位](../data/units.json#L2573) · [普通探机的两页建造卡](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L25921) · [生产建筑与出兵索引](../reference/desert-storm/Base.SC2Data/GameData/UpgradeData.xml#L2651)

- [ ] **侦测器** `Observer` / `Observer2`。接入隐形空中侦测、可架起与保持机动两种方案，实际索敌能受它的侦测覆盖影响。[出兵映射](../reference/desert-storm/MapScript.galaxy#L35886) · [单位说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3809)
- [ ] **黑暗圣堂武士** `DarkTemplar`。实现永久隐形与闪现接敌的近战单位，验证有无反隐支援时的交战区别。[部署入口](../reference/desert-storm/MapScript.galaxy#L35902) · [能力](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3348)
- [ ] **先知** `OracleNormal`。实现天启临时揭露及受击回撤。本体依赖技能提供侦测。地图另有沃拉尊版 `Oracle`。[出兵映射](../reference/desert-storm/MapScript.galaxy#L35910) · [普通版说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3812)
- [ ] **保存者** `PreserverC`。补狂热者、凤凰两种幻象战术，幻象吸引火力并承受双倍伤害。[普通出兵及战术](../reference/desert-storm/MapScript.galaxy#L35846) · [幻象说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3862) · [两种名称](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L12773)
- [ ] **凤凰** `Phoenix`。补对空战机、引力光束抬起中小型地面目标，以及攻击召唤物时后撤的行为。[普通出兵](../reference/desert-storm/MapScript.galaxy#L35990) · [单位说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3838)
- [ ] **折跃棱镜** `WarpPrismPhasing` 系列。遇敌展开，按枢纽选择的方案周期性折跃狂热者、先驱者使徒、追猎者或机械哨兵，四种援军的召唤周期各异，默认狂热者。[出兵映射](../reference/desert-storm/MapScript.galaxy#L35998) · [支援规则](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4284)
- [ ] **歼灭者** `ImmortalShakuras`。接入普通探机可造的黑暗水晶塔产物，分别配置对地与反重甲空军武器。[普通建造槽](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L4640) · [武器定位](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3571)
- [ ] **风暴战舰** `Tempest`。接入普通方尖碑部署，地面攻击后重新搜空中目标，可重置攻击间隔转火。另有加强对地的下波配置。[普通出兵](../reference/desert-storm/MapScript.galaxy#L36028) · [重型与建筑加成](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4174) · [对空转火](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3066) · [对地方案](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L10174)
- [ ] **圣母舰** `Mothership`。接入每方限一艘、隐形力场、时空扭曲、周期制造侦测器，以及亲自出战或由枢纽召回的战术选择。[普通枢纽生产](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L6983) · [单位与上限](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3753)
- [ ] **侦察机** `Scout`。从普通星门升级接入，分别处理对地反轻甲与对空反重甲。与提供侦测的侦测器区分。[星门升级](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L11021) · [双武器](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4225)
- [ ] **军团士兵** `PrisonZealot`。普通暮光议会可升级为净化者议会。只选建筑为攻击目标，沿途推进并推开地面敌军。[建筑升级](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L14884) · [目标规则](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3872)
- [ ] **先驱者使徒** `AdeptFenix`。普通虚空传送门可升级获得。接入对空与共奏阴影协同攻击，保留与普通使徒灵能传送的战术区别。[建筑升级](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L14910) · [武器和阴影](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L2827)
- [ ] **刚毅不朽者** `Immortal4`，属于现有不朽者的普通升级。基础 `Immortal` 已有受击短时加 40 盾甲。补机器人设施升级后的刚毅版，满足护盾条件时将过高的单次非技能伤害封顶为 10，并让两种防御在结算上可区分。[基础能力](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L1260) · [升级入口](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L5256) · [上限及例外](../reference/desert-storm/Base.SC2Data/GameData/BehaviorData.xml#L12502) · [现有单位](../data/units.json#L2978)

**暂待核实普通对局的解锁条件**

- [ ] **净化者仲裁机** `ArbiterMP` / `ArbiterMP2`。属于基石单位，有静滞与召回战术。普通探机的建造槽标为 `Suppressed`，须确认常规对局能否启用，然后决定是否开放招募。[基石标签](../reference/desert-storm/zhCN.SC2Data/LocalizedData/ObjectStrings.txt#L13502) · [入口状态](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L4583)
- [ ] **风暴裁决舰** `TempestArbiter`。属于基石单位，普通风暴战舰的方尖碑挂有升级按钮，但升级命令 `cy3` 标为 `Restricted`，须追查开放条件。[基石标签](../reference/desert-storm/zhCN.SC2Data/LocalizedData/ObjectStrings.txt#L14275) · [方尖碑按钮](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L14410) · [命令状态](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L15250)

## 已有兵种的机制差异

### 人族已有单位

- [ ] **特工。** 当前靠常规弹与精确弹切换，原图的特工常态隐形，需与反隐一起排期。补 EMP 范围削盾、削能及揭隐，以及对生命至少 120 的生物目标消耗能量和一次性充能的狙杀。[现有武器][T-ghost-current] · [原图特工](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L11932) · [EMP][T-emp] · [狙杀条件和充能][T-snipe]
- [ ] **寡妇雷。** 当前导弹对主目标与邻敌同伤，采用重甲加成。原图将直接命中与溅射分开，各有独立护盾加伤，还需核对 6 格潜地、8 格出地的不同阈值。中文说明写地面敌人，实际验证器未限定地面，验收应覆盖纯空军接近。[现有导弹][T-mine-current] · [原图直接命中][T-mine-direct] · [原图溅射][T-mine-splash] · [进入条件][T-mine-in] · [离开条件][T-mine-out]
- [ ] **大和舰。** 已有移动攻击与大和炮，补普通聚变芯体两种出兵战术。后撤型低血跳走并用防御矩阵自保，支援型跳到前线友军并使用大和炮。[现有技能][T-bc-current] · [两套跳跃战术][T-bc]
- [ ] **维京机甲。** 已有通用机甲与独立的维京战机，同一机甲厂另可选择芬里尔战狼（重型，优先高生命目标）或克哈卫士（小型，反轻甲）。把两种生产选择列入现有机甲的扩充。[现有机甲][T-viking-current] · [工厂切换与武器][T-viking]
- [ ] **劫掠者。** 当前震荡弹缺少免疫目标配置。原图的重型（Massive）单位、建筑以及具有指定抗控制被动的单位免疫。用普通重甲目标和雷兽分别验收，前者应能减速。[原图免疫条件](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3151) · [当前技能参数](../data/units.json#L292) · [现有目标过滤](../scripts/skills/on_hit_slow.gd#L10)
- [ ] **维京战机。** 当前对空武器用单段 26 点伤害结算，原图普通鱼雷单次伤害效果为 13。补查基础武器每轮发射数与每发重甲加成，再按每发独立减甲验收。[原图命中效果](../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L18394) · [当前对空武器](../data/units.json#L952)
- [ ] **医疗运输机。** 双束治疗已接入，补受击且 5 格内无符合条件的友军时自动启动后燃，验收孤立与有友军掩护两种情形。[现有治疗][T-medivac-current] · [后燃触发][T-boost] · [友军过滤][T-boost-validator]

地面医疗兵属于雷诺阵营，当前商店已有医疗运输机。[原图归属](../reference/desert-storm/zhCN.SC2Data/LocalizedData/ObjectStrings.txt#L13914) · [医疗兵替换记录][T-medic]

### 虫族已有单位

- [ ] **感染虫（原图名感染者）**。现有真菌减速和持续伤害。补神经寄生的选敌、持续控制与解除，接入“感染孵化／微生物环绕云”二选一。孵出的被感染人类归召唤物。[原图技能](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3591) · [寄生限制](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3788) · [战术开关](../reference/desert-storm/Base.SC2Data/GameData/UpgradeData.xml#L2459) · [当前技能](../data/units.json#L2297)
- [ ] **虫群宿主**。当前在宿主身边直接产生地面蝗虫。补潜地隐形孵化、冷却完成出虫。蝗虫出生时为无法攻击的飞行单位，接近地面敌人后俯冲，落地转为可对地攻击。[宿主潜地](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3036) · [蝗虫生命周期](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4157) · [当前召唤](../data/units.json#L2116) · [当前蝗虫](../data/units.json#L5188)
- [ ] **蟑螂、穿刺者（潜伏者）**。给蟑螂补地下全速移动和潜地快速回血。给已有埋地和地刺的穿刺者补隐形。和眼虫的探测一起验收埋地、可选中、现身三个环节。[蟑螂](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3966) · [普通潜伏者](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3032) · [蟑螂现状](../data/units.json#L1754) · [穿刺者现状](../data/units.json#L2042)
- [ ] **跳虫、毒爆虫**。跳虫现在只在交战时改变移速，补随队接战和出场扣血全速支援两种战术。毒爆虫已有贴边主动引爆和阵亡爆炸，补允许其贴敌等待被击杀的战术，共用现有碰撞半径加 0.5 格的爆炸结算。[原图战术](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4359) · [跳虫配置](../data/units.json#L1609) · [毒爆虫结算](../scripts/skills/suicide.gd#L11)
- [ ] **飞龙（原图名异龙）**。三目标弹射已接通。补重甲优先和三段各自对重甲伤害翻倍、脱战后撤、脱战 5 秒后 10 生命/秒的再生。当前没有重甲加成，回血恒定 1.4/秒。[对重甲翻倍](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3409) · [三段伤害](../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L18969) · [索敌](../reference/desert-storm/Base.SC2Data/GameData/WeaponData.xml#L2668) · [后撤](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3198) · [再生](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3769) · [当前配置](../data/units.json#L2223)
- [ ] **雷兽**。补狂暴对精神控制及指定减速、束缚、禁锢、恐惧和昏迷效果的免疫，并校对跨越矮小友军的行为。验收沿用项目指定的前缘 1 格、90°、主次目标 100%/30% 扫击。[原图被动](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L41183) · [控制免疫边界](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3431) · [当前缺口](../data/units.json#L2425)
- [ ] **破坏者**。现有胆汁按敌群密度选点。原图自动释放挑静止、生命或护盾至少 60 的目标，排除幻象和召唤物，优先重甲。力场接入时还应能摧毁力场。[释放条件](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L4737) · [技能说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3262) · [当前选点](../scripts/skills/delayed_area.gd#L12)
- [ ] **刺蛇**。突击已有持续时间和冷却。补未移动时才可触发的门槛，验证正在行军且身边无敌时不空耗突击。原图同时检查未移动和近处无敌。[能力验证器](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L2555) · [当前触发](../scripts/skills/mobility_burst.gd#L6)
- [ ] **巢虫领主**。现有每段命中在受击者位置生成巢虫。原图普通型从自身孵化后投出，普通虫舱 `BroodLordHangar` 有 2 原图秒的装填字段。接入库存、装填和发射前先核清基础依赖的容量与起始弹量。原图普通武器射程 14，当前为 10。[普通型说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L2925) · [普通虫舱](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L1398) · [普通武器](../reference/desert-storm/Base.SC2Data/GameData/WeaponData.xml#L1202) · [当前配置](../data/units.json#L2499) · [当前生成时机](../scripts/skills/summon.gd#L24)

### 神族已有单位

- [ ] **高阶圣堂武士**。现有灵能风暴。补能量反蚀的目标门槛（非幻象敌人、能量至少 25）、抽空能量与按能量造成伤害，以及两名低能量或垂危圣堂按条件融合为一个执政官。应能处理配对时一方阵亡。[反蚀](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L1975) · [融合触发](../reference/desert-storm/MapScript.galaxy#L30580) · [原图单位说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3495) · [现有技能](../data/units.json#L3080)
- [ ] **航母**。保留常规拦截机掠袭和吸引火力，补每舰一次的集中释放。原图以射程 15、目标周围 3 格内至少 8 个合格敌人为条件，产生临时无敌、优先攻击低生命敌人的拦截机，并保留常规机库数量。[技能次数](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L2617) · [群体判定](../reference/desert-storm/Base.SC2Data/GameData/ValidatorData.xml#L4873) · [特殊机群](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3951) · [现有召唤](../data/units.json#L3609)
- [ ] **干扰者**。原图基础武器在 10 至 13 格触发、周期 3 游戏秒，过滤召唤物作瞄准目标。爆炸搜索过滤友方。当前在 13 格内择密集点，冷却 17 秒、会误伤友方。跟进新星从发射到引爆的移动过程，核对近身死角、游戏时间换算、合法目标、误伤及护盾伤害，以贴身、召唤物与敌我混战三类布阵验收。[单位挂载](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L22592) · [基础武器](../reference/desert-storm/Base.SC2Data/GameData/WeaponData.xml#L1583) · [新星实体](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L6531) · [爆炸搜索](../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L19474) · [现有配置](../data/units.json#L3392) · [落点选择](../scripts/skills/delayed_area.gd#L4)
- [ ] **巨像**。已有横扫和对空武器可锁定的高大机体。补原图面对特定空中威胁时中断射击并后撤，以及跨越小型地面单位、仍受其他巨像等阻挡的移动规则。沿用项目商定的双束扫射表现。[原图后撤触发](../reference/desert-storm/MapScript.galaxy#L30535) · [空中威胁过滤](../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L4590) · [跨越规则](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3109) · [现有碰撞](../scripts/battle_sim.gd#L702) · [现有巨像](../data/units.json#L3286)
- [ ] **虚空辉光舰**。保留项目光束节拍。校准棱镜期间对重甲的额外一击在原图单独结算为技能伤害。当前直接提高普通武器的重甲加成，需补独立结算并校验护甲、防护效果和对建筑的触发过滤。[技能条件](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L13281) · [两个效果](../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L5001) · [伤害口径](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4263) · [当前武器增益](../scripts/skills/weapon_buff.gd#L14)
- [ ] **追猎者**。已有受伤低盾后撤、冷却和短暂无敌。原图描述会规避当前弹道，瞬发攻击仍会命中，并使原攻击者改打其他目标。当前追踪弹会追到闪现后的新位置，短暂无敌也不区分伤害来源。核对脱锁、弹道与瞬发命中的处理。项目已采用的后撤方向单独保留。[原图闪现](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L2924) · [当前闪现](../scripts/skills/blink.gd#L23) · [当前追踪弹](../scripts/skills/services/projectile_service.gd#L29)
- [ ] **哨兵**。已有回盾和守护盾。原图守护盾依据附近友军开火及受保护状态触发，技能说明涵盖非技能伤害。当前以附近敌人触发，只在远程命中时扣减。核对近战普攻是否也应受保护，以及两名哨兵在同区的启动条件。普通锻炉生产的是 `SentryAiur`，说明为单目标充盾，当前导入映射为 `Sentry`，项目可同时回两名友军的盾。先校对源 ID 和束数，再决定保留哪种配置。[自动施放](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L11601) · [守护盾说明](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3457) · [原图充盾](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4052) · [现有导入映射](../tools/desert_storm_units.py#L30) · [当前回盾数](../data/units.json#L2872) · [当前触发](../scripts/skills/aura.gd#L17) · [当前减伤](../scripts/battle_sim.gd#L971)

## 排期与验收

- [ ] **R05 / X04 · 先定隐形与探测的对抗规则。** 特工在原图常态隐形，穿刺者潜地后隐形，普通先知靠天启揭隐。以这三例连同探测器进出范围，明确索敌、丢失锁定、显形持续时间和玩家能看到的反馈，再排女妖、黑暗圣堂武士和三族探测支援。[特工隐形标记](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L11932) · [天启](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3812)
- [ ] **R11 · 复用按波选择战术的入口。** 跳虫随队或全速支援、大和舰支援或后撤、折跃棱镜增援哪种兵，均需记录玩家下波的选择。复用已有使徒战术入口，验收时分别检查场上旧单位与下一波新单位。[现有使徒选择](../scripts/formation_panel.gd#L205) · [普通战术指令](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4347) · [棱镜增援](../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4284)
- [ ] **R04 / R11 · 按能改变交战结果的场景验收。** 优先核对特工对带盾施法者、虫群宿主隔前排放蝗虫、高阶圣堂武士耗能后合体。对每项记录触发条件、作用对象、反制手段和采用的简化。地图导出只包含覆盖值时，先补依赖数据，再填写未知参数。[原图数据继承说明](DESERT_STORM_UNITS.md#明确覆盖与继承边界)

保留项目已确认的设计，包括恶火和恶蝠独立招募、解放者扇形防区、雷神自动切换对空武器、兴奋剂的生命门槛、虫族贴碰撞边缘攻击和雷兽扇扫。文中原图秒数沿用地图数据口径，排期实现时再换算为项目采用的实战时间。

[T-prod]: ../reference/desert-storm/Base.SC2Data/GameData/UpgradeData.xml#L2525
[T-units]: ../data/units.json#L4
[T-herc]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3459
[T-reaper]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3945
[T-blimp]: ../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L392
[T-banshee]: ../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L5763
[T-cyclone]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3172
[T-cyclone-spawn]: ../reference/desert-storm/MapScript.galaxy#L35160
[T-conqueror]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L4063
[T-angel]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3655
[T-ravens-prod]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3307
[T-ravens]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3918
[T-mule]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3692
[T-predator]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3861
[T-drill-prod]: ../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml#L28369
[T-drill]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3642
[T-ghost-current]: ../data/units.json#L562
[T-emp]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3406
[T-snipe]: ../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L8749
[T-mine-current]: ../data/units.json#L742
[T-mine-direct]: ../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L21671
[T-mine-splash]: ../reference/desert-storm/Base.SC2Data/GameData/EffectData.xml#L11851
[T-mine-in]: ../reference/desert-storm/Base.SC2Data/GameData/ValidatorData.xml#L3410
[T-mine-out]: ../reference/desert-storm/Base.SC2Data/GameData/ValidatorData.xml#L4692
[T-bc-current]: ../data/units.json#L1414
[T-bc]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3532
[T-viking-current]: ../data/units.json#L1005
[T-viking]: ../reference/desert-storm/zhCN.SC2Data/LocalizedData/GameStrings.txt#L3044
[T-medivac-current]: ../data/units.json#L466
[T-boost]: ../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml#L3728
[T-boost-validator]: ../reference/desert-storm/Base.SC2Data/GameData/ValidatorData.xml#L695
[T-medic]: MEDIVAC.md#L7
