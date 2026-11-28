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

劫掠者（`marauder`）使用上传的[原始模型](marauder/marauder.glb)生成[战场分件](marauder/marauder_rig.glb)。两条腿按行程迈步，原地转向时换脚支撑。震荡榴弹每次从另一只手的炮口出膛。被毁时从背部反应堆起爆，随后机身、双臂和腿甲散开。[劫掠者四组动作](../../docs/media/marauder-actions.gif)

恶蝠的[原始机甲](hellbat_mech/hellbat_mech.glb)与恶火的[战车模型](hellbat/hellion_rig.glb)各自保留。机甲用双腿行走、转向，向前喷火时两面盾向胸前收拢，背部喷口横扫扇面。被毁时背部燃料罐先爆燃，机体随后解体。变形时机身压低、腿轮收折，最终拼成游戏中的恶火战车。[恶蝠四组动作](../../docs/media/hellbat-mech-actions.gif) · [机甲变战车的三个视角](../../docs/media/hellbat-to-hellion.gif)

在 Godot 中打开[机甲动作预览](../../scenes/art/mech_actions.tscn)，按 F6 可选择单位、动作和观察角度。劫掠者和恶蝠均已接入战场。动作预览中的恶火（`hellbat`）演示变形时，车轮、车壳和炮塔逐步展开为恶蝠（`hellbat_mech`），直接招募的恶蝠也使用同一套机甲动作。[战车展开为恶蝠的动画](../../docs/media/hellion-to-hellbat.gif) · [恶蝠动画脚本](../../scripts/visuals/hellbat_actor.gd)

可在项目根目录分别运行 `python tools/art/build_marauder_rig.py` 和 `python tools/art/build_hellbat_mech_rig.py`，从上传的模型重建两个单位的分件和材质。两个脚本都使用 Python 3、NumPy 和 SciPy。

坦克（`mortar`）的[机动形态](mortar/mortar.glb)和[架起形态](mortar/mortar_siege.glb)均来自上传的白模。[战场模型](mortar/mortar_rig.glb)统一了两份模型的朝向，沙黄色装甲、深色履带和钢色炮节在两种形态中沿用同一套材质。

行驶时左右履带随车身位移和转向运动，炮塔可以独立瞄准。机动双炮轮流开火，开火的那根炮管后坐。架起后改用中央攻城炮，命中时火星迸出，扬尘向实际溅射范围扩散。两种形态被毁时都从当前姿势解体，残件落地后消失。[坦克移动、开火与被毁](../../docs/media/tank-actions.gif)

架起时，两侧装甲舱门先滑开，滑座从车腹推出折叠撑臂。四组履带的内端随曲柄向内收，外端向四角摆开，支撑脚翻平落地。随后炮口护盖向两边翻开，中央炮架抬升，长炮管从导轨之间伸出。两份上传模型里的零件组成同一副车体，架起和收回时都可以一直追踪同一块装甲。[斜前、顶视和低前视同步预览](../../docs/media/tank-deployment.gif)

动画读取战斗已有的 `siege_state` 及结束时刻。完整架起用时 1.5 秒，收回用时 1 秒。架起中途失去目标时，各个关节从当时的位置沿原路径收回。

在 Godot 中打开[坦克动作预览](../../scenes/art/tank_actions.tscn)，按 F6 可原速或半速播放，也可暂停后切换观察角度。在项目根目录运行 `python tools/art/build_tank_rig.py`，可从两份源模型重建分件、转轴、炮口和履带路径。脚本使用 Python 3、NumPy 和 SciPy。

## 招募肖像

部队配置和格阵商店共用[兵种肖像](../ui/recruits/)。每个可招募单位对应一张以单位 ID 命名的 256 × 256 透明 PNG。已有兵模的肖像由 [Blender 渲染脚本](../../tools/art/render_recruit_models.py) 取景，其余肖像的造型源在[肖像美术目录](../../tools/art/recruit_portraits/)。

更换兵模后，可在项目根目录运行 `blender -b -P tools/art/render_recruit_models.py -- thor` 单独重拍雷神。更新任意肖像后，运行 `python tools/art/pack_recruit_thumbnails.py` 重建列表使用的 64 像素图集。详情直接显示大图。[招募菜单实机截图](../../docs/media/recruit-menu.jpg) · [四族肖像总览](../../docs/media/recruit-roster.jpg)

## 维京机甲和维京战机

地面机甲 `viking_assault` 和空中战机 `viking` 在战场上共用[可变形模型](viking/viking_rig.glb)。[上传的机甲白模](viking/viking_assault.glb)由 41 个网格部件构成。行走时两条腿交替承重。两臂的格林炮按实际开火事件左右交替发射，转管加速、炮组后坐。变形成战机时，双腿折入机腹，后掠翼展开，机鼻向前伸出。地面和空中被毁都会从当时的姿态解体。[行走、开火与被毁](../../docs/media/viking-actions.gif) · [机甲变形特写](../../docs/media/viking-transform.gif)

招募空中战机时，每架新出场的维京先起步 0.30 秒，接着用 1.20 秒展开升空，左右挂架按已有的对空导弹事件开火。招募地面机甲时，单位保持地面形态。可在 Godot 中打开[维京动作预览](../../scenes/art/viking_actions.tscn)，按 F6 查看两个形态的动作、起飞和反向降落。

在项目根目录运行 `python tools/art/build_viking_rig.py` 可从白模重建可动分件、关节、炮口和涂装。招募界面的[机甲肖像](../ui/recruits/viking_assault.png)沿用[招募用分件](viking/viking_assault_rig.glb)，可用 `python tools/art/build_viking_assault_rig.py` 和上节的肖像渲染脚本重建。

## 星灵源模型

以下八份源模型由用户提供，按 `data/units.json` 中的单位 ID 保存，供后续战场模型、动画与特效接入使用。

- 先锋（`vanguard`）：[vanguard.glb](vanguard/vanguard.glb)，来自 `先锋模型.glb`，未包含纹理图片，无外置文件依赖。
- 哨兵（`sentry`）：[sentry.glb](sentry/sentry.glb)，来自 `哨兵模型.glb`，未包含纹理图片，无外置文件依赖。
- 不朽者（`immortal`）：[immortal.glb](immortal/immortal.glb)，来自 `不朽者模型.glb`，未包含纹理图片，无外置文件依赖。
- 巨像（`colossus`）：[colossus.glb](colossus/colossus.glb)，来自 `巨像模型.glb`，未包含纹理图片，无外置文件依赖。
- 航母（`carrier`）：[carrier.glb](carrier/carrier.glb)，来自 `航母模型.glb`，未包含纹理图片，无外置文件依赖。
- 干扰者（`disruptor`）：[disruptor.glb](disruptor/disruptor.glb)，来自 `干扰者模型.glb`，未包含纹理图片，无外置文件依赖。
- 高阶圣堂武士（`high_templar`）：[high_templar.glb](high_templar/high_templar.glb)，来自 `高阶圣堂武士模型.glb`，未包含纹理图片，无外置文件依赖。
- 追猎者（`stalker`）：[stalker.glb](stalker/stalker.glb)，来自 `追猎者模型.glb`，未包含纹理图片，无外置文件依赖。
