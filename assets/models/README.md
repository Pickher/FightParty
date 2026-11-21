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

移动时按实际行程交替迈步。两种形态对地都使用左右臂炮。普通形态对空时由背炮射击，火箭弹头形态则从肩上四个发射口依次发射。对空武器切换时，四门炮在同一副机体上展开或收回，历时 0.5 秒。被毁时，武器和腿甲从当时的姿态脱落，落地停留后淡出。[两种形态的战场动作](../../docs/media/thor-actions.gif) · [三视角切换特写](../../docs/media/thor-switch.gif)

在项目根目录运行 `python tools/art/build_thor_rig.py` 可用两份源模型重建雷神分件、转轴和内嵌材质。脚本需要 Python 3、NumPy 和 SciPy，转轴按这两份模型标定。
