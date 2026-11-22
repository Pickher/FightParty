# 单位 3D 模型

每个单位使用一个子目录，目录名与 `data/units.json` 中的单位 ID 一致。例如特战队员使用 `assets/models/rifle/`。

当前医疗机使用 [medivac.glb](medivac/medivac.glb)，包含 6,056 个三角面和一张内嵌 JPEG 贴图。

恶火沿用上传的 [原始模型与贴图](hellbat/hellbat.glb)。战场加载[分件模型](hellbat/hellion_rig.glb)，按行驶距离转动车轮，车顶喷火器单独追踪目标，沿已有攻击波喷火。[四组动作预览](../../docs/media/hellion-actions.gif)

收到死亡事件后，后部油罐先爆燃，随后车头、座舱、后舱、炮塔和四个车轮分开抛出。零件落地后停留片刻，再一起淡出。车身的三个断块取自[同一车壳](hellbat/hellion_wreck.glb)，只在解体时使用。[被毁动画特写](../../docs/media/hellion-destruction.gif)

若替换同一造型的源网格，可用 Python 3、NumPy 和 Pillow 运行 `python tools/art/build_hellion_rig.py` 重建分件和断面贴图。车轴、炮塔底座及喷口位置按本次上传的模型标定，造型变化时需重新定位。

优先保存 `.glb` 文件。模型依赖外置贴图时，将贴图放在同一子目录，保留模型引用的相对路径。可用简短的说明记录模型来源、比例、正面方向和动画名称，方便其他开发者接入。

提交并推送到 `cloud/test` 后，云端对话可以同步该分支，再从 `assets/models/<单位 ID>/` 读取模型。

当前大和舰模型为 [battlecruiser.glb](battlecruiser/battlecruiser.glb)，四组实时三维动作及预览见 [美术规范](../../docs/unit-art-spec.md#大和舰实时三维动画)。

雷神源模型位于 `thor/`：用户提供的[雷神拓扑模型](thor/thor.glb)用于机体，[雷神火箭模型](thor/thor_rocket.glb)用于火箭。两个 GLB 均未包含纹理图片，也未引用外置贴图，可直接供云端开发读取；战场接入与动画制作后续进行。

劫掠者（单位 ID 为 `marauder`）源模型位于 [marauder.glb](marauder/marauder.glb)，由用户提供。该 GLB 未包含纹理图片，无外置文件依赖；供后续战场表现与动画接入使用。

人族恶蝠机甲在战场上使用上传的模型。直接出动时显示双足机甲；选择变形出动时先显示恶火车型，完成变形后切换为机甲。两种单位各有独立的商店入口。[恶蝠机甲模型](hellbat_mech/hellbat_mech.glb)
