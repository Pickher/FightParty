# 单位 3D 模型

每个单位使用一个子目录，目录名与 `data/units.json` 中的单位 ID 一致。例如特战队员使用 `assets/models/rifle/`。

当前医疗机使用 [medivac.glb](medivac/medivac.glb)，包含 6,056 个三角面和一张内嵌 JPEG 贴图。

优先保存 `.glb` 文件。模型依赖外置贴图时，将贴图放在同一子目录，保留模型引用的相对路径。可用简短的说明记录模型来源、比例、正面方向和动画名称，方便其他开发者接入。

提交并推送到 `cloud/test` 后，云端对话可以同步该分支，再从 `assets/models/<单位 ID>/` 读取模型。

当前大和舰模型为 [battlecruiser.glb](battlecruiser/battlecruiser.glb)，四组实时三维动作及预览见 [美术规范](../../docs/unit-art-spec.md#大和舰实时三维动画)。
