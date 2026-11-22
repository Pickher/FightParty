# 单位 3D 模型

每个单位使用一个子目录，目录名与 `data/units.json` 中的单位 ID 一致。例如特战队员使用 `assets/models/rifle/`。

当前医疗机使用 [medivac.glb](medivac/medivac.glb)，包含 6,056 个三角面和一张内嵌 JPEG 贴图。

恶火沿用上传的 [原始模型与贴图](hellbat/hellbat.glb)。战场加载[分件模型](hellbat/hellion_rig.glb)，按行驶距离转动车轮，车顶喷火器单独追踪目标，沿已有攻击波喷火。[四组动作预览](../../docs/media/hellion-actions.gif)

收到死亡事件后，后部油罐先爆燃，随后车头、座舱、后舱、炮塔和四个车轮分开抛出。零件落地后停留片刻，再一起淡出。车身的三个断块取自[同一车壳](hellbat/hellion_wreck.glb)，只在解体时使用。[被毁动画特写](../../docs/media/hellion-destruction.gif)

若替换同一造型的源网格，可用 Python 3、NumPy 和 Pillow 运行 `python tools/art/build_hellion_rig.py` 重建分件和断面贴图。车轴、炮塔底座及喷口位置按本次上传的模型标定，造型变化时需重新定位。

优先保存 `.glb` 文件。模型依赖外置贴图时，将贴图放在同一子目录，保留模型引用的相对路径。可用简短的说明记录模型来源、比例、正面方向和动画名称，方便其他开发者接入。

提交并推送到 `cloud/test` 后，云端对话可以同步该分支，再从 `assets/models/<单位 ID>/` 读取模型。

当前大和舰模型为 [battlecruiser.glb](battlecruiser/battlecruiser.glb)，四组实时三维动作及预览见 [美术规范](../../docs/unit-art-spec.md#大和舰实时三维动画)。

雷神的[战场模型](thor/thor_rig.glb)沿用上传的[普通形态机体](thor/thor.glb)和[火箭弹头形态的四根炮管](thor/thor_rocket.glb)。双腿、脚掌、臂炮和背炮各有转轴。两个源文件均为白模，战场模型用钢蓝色装甲、深色机械和金属亮面区分部件。

普通形态对空、对地都由左右臂炮交替开火，四门背炮保持收起。火箭弹头形态对地仍用臂炮，对空则从肩上四个炮孔依次发射火箭。可见飞行用时为原弹道的三分之二，炮口点火与出膛同步，爆炸仍对准实际命中的时刻和位置。命中时火花向外迸开，烟团随火花一起散去，整段爆炸持续约 0.24 秒。[火箭齐射追击移动空军 · 原速预览](../../docs/media/thor-rocket-intercept.gif)

两种形态都按实际行程交替迈步。切换对空武器时，四门炮在同一副机体上展开或收回，历时 0.5 秒。被毁时，武器和腿甲从当时的姿态脱落，落地停留后淡出。[两种形态的战场动作](../../docs/media/thor-actions.gif) · [三视角切换特写](../../docs/media/thor-switch.gif)

在项目根目录运行 `python tools/art/build_thor_rig.py` 可用两份源模型重建雷神分件、转轴和内嵌材质。脚本需要 Python 3、NumPy 和 SciPy，转轴按这两份模型标定。

劫掠者（单位 ID 为 `marauder`）源模型位于 [marauder.glb](marauder/marauder.glb)，由用户提供。该 GLB 未包含纹理图片，无外置文件依赖；供后续战场表现与动画接入使用。

恶蝠机甲源模型位于 [hellbat_mech.glb](hellbat_mech/hellbat_mech.glb)，来自用户提供的 `恶蝠3d模型.glb`，无纹理图片和外置文件依赖。当前项目历史上将 `hellbat` 单位 ID 和模型目录用于恶火车型，因此恶蝠机甲单独存放在 `hellbat_mech/`，供后续新增单位或形态时接入；此目录名目前仅用于区分资产，尚未对应 `data/units.json` 中的单位。
