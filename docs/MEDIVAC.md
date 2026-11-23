# 医疗运输机

原 0.12.1 本地医疗机逻辑与旧阵容迁移现整合到 0.12.3：基于 `cloud/test` 的 `82e2313`，保留追猎者/执政官混编行军和 U04 界面待设计事项。版本号统一为 0.12.3 / Android 45，没有运行或打包，当时未接入模型；后续外观接入见下文。

## 可玩位置与保留范围

- `medivac` 替代人族商店/正常布阵/电脑辅助位的 `medic`，850 矿、0 气、0 核，一组 2 架。
- 医疗兵仅增加 `available: false`。原数值、治疗组件、绘制入口和直接生成接口均保留；旧医疗兵技能回归用例仍在。重新开放需恢复 `available: true`，并按需要切换人族 `ai.support`。
- 正常购买和通用阵容校验仍拒绝停用兵种。读取旧人族保存阵容时，先仅移除停用的医疗兵槽位，保留其他兵种、格位与完整单兵位置，再走正常购买和排布校验；不自动换成医疗机，不重新排布，也不立即改写设置文件。仅含医疗兵的旧阵容恢复为空兵营，不回退为默认军队，并显示提示。其他无效兵种、超预算或无效排布仍按现有机制处理。旧战报并非逐帧兼容。
- 医疗机无攻击，不计入终局可战斗部队。以支援位自动排布，跟随可攻击友军，遇可对空敌人后撤，无友军时退向出兵点。
- 每架最多同时治疗两名受伤的友方生物，地面、空中均可。治疗只恢复生命。目标已被医疗运输机治疗期间，其他光束会寻找另一名伤员。

## 双束治疗

医疗运输机可以一边移动一边治疗。它在 9 格内发现伤员，先选生命比例最低者，同等比例取较近者，进入 4 格后开始治疗。治疗期间在机身周围 4.5 格扫描额外伤员，优先选当前生命值最低者，同值取较近者。光束每次实际治疗都要求目标在 4 格内。伤员满血、死亡、失去资格、脱离距离或医疗机能量不足都会断束。正常换目标随下一次搜索进行。

| 项目 | 沙漠风暴目录中的值 | FightParty 按沙漠风暴开局 Faster（1.4 倍）换算 |
|---|---|---|
| 每束治疗 | 每 0.111 游戏秒恢复 1 生命 | 每约 0.0793 秒恢复 1 生命，每秒约 12.6，两名伤员合计每秒约 25.2 |
| 治疗耗能 | 每个治疗脉冲消耗 0.33 能量 | 每束持续工作每秒约消耗 4.16 能量 |
| 启动与维持 | 自动发起治疗指令需至少 2 能量，治疗脉冲前需至少 1 能量 | 两束共用一架医疗机的能量，开始连线时不扣能量，首个脉冲在一个治疗周期后结算 |
| 额外目标扫描 | 治疗期间每 0.0625 游戏秒一次 | 周期约 0.0446 秒 |
| 能量恢复 | 初始 200，每游戏秒恢复 1.125 | 每秒恢复 1.575 |

换算只用于医疗机上述时序与回能。原图单位记录给出护甲 4、初始能量 200、回能 1.125，能力覆盖项给出自动搜索 9 格与 360° 施法，验证器覆盖项把启动能量门槛设为 2。反应堆价格 850，每次部署两架。原图脚本开启 AdvancedHealingAI 并将开局速度设为 Faster。[单位目录](../reference/desert-storm/Base.SC2Data/GameData/UnitData.xml) · [能力目录](../reference/desert-storm/Base.SC2Data/GameData/AbilData.xml) · [验证器](../reference/desert-storm/Base.SC2Data/GameData/ValidatorData.xml) · [地图脚本](../reference/desert-storm/MapScript.galaxy)

治疗周期、扣能、补束搜索与目标占用标记来自地图继承的战役效果，施法距离与主目标排序来自战役能力，维持距离及能量门槛来自验证器。[战役能力](https://github.com/SC2Mapster/SC2GameData/blob/6dd323aae4209a01f110719a00b4e8f7a88389bc/campaigns/liberty.sc2campaign/base.sc2data/GameData/AbilData.xml#L640) · [战役治疗效果](https://github.com/SC2Mapster/SC2GameData/blob/6dd323aae4209a01f110719a00b4e8f7a88389bc/campaigns/liberty.sc2campaign/base.sc2data/GameData/EffectData.xml#L1991-L2133) · [战役验证器](https://github.com/SC2Mapster/SC2GameData/blob/6dd323aae4209a01f110719a00b4e8f7a88389bc/campaigns/liberty.sc2campaign/base.sc2data/GameData/ValidatorData.xml#L259-L301) · [基础验证器](https://github.com/SC2Mapster/SC2GameData/blob/6dd323aae4209a01f110719a00b4e8f7a88389bc/mods/liberty.sc2mod/base.sc2data/GameData/ValidatorData.xml#L978)

## 美术与验证边界

新增本地实时 3D 战场表现方案见 [医疗机实时 3D](MEDIVAC_REALTIME_3D.md)。商店/部队配置继续使用下述精灵；实时表现尚未运行验收。

用户上传的低面数 `assets/models/medivac/medivac.glb` 已通过离线正交渲染生成透明精灵，接入共用 `UnitArt`，用于战场、商店和部队配置；原轮廓保留为资源缺失时的回退。只接入固定视角外观，没有动画或逐单位 3D 场景，不改医疗机逻辑。来源、重现方法和验证边界见 [模型精灵说明](../assets/units/medivac/README.md)。

0.12.3 首次接入时只做了静态代码审阅、JSON/工作簿数据检查与差异检查。当时新增 `_medivacs` 回归覆盖可玩列表/停用校验、价格与退款、双目标/能量、机械排除、空中生物、终局计数与避战；更新 UI 购买用例到医疗机。**未执行 Godot、测试、战斗模拟、导出或安装包生成**。这些是待运行用例，不是通过报告。后续需用户安排运行验证，特别检查治疗范围、实际战斗生存与经济平衡、阵型镜像和存档恢复。

补充静态修复：新增旧阵容迁移回归用例，覆盖保留格位/坐标、仅医疗兵为空、移除单位与保留单位的旧位置重叠、其他种族/重新启用医疗兵不迁移、无自动替换和输入不变。用例未执行。
