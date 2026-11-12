# 《沙漠风暴》地图参考资料

资料来自本地 Battle.net 缓存。主地图包与《沙漠风暴 (27)》录像中的地图标识匹配，包内中文标题为「沙漠风暴」。原始条目按归档内路径保存，文件大小和 SHA-256 见 `manifest.json`。

| 文件 | 用途 |
| --- | --- |
| `MapScript.galaxy` | 主地图生成的 Galaxy 脚本，用于研究出兵、战斗和对局逻辑 |
| `ai6F5014E0.galaxy` | 地图包中的另一份 Galaxy 脚本 |
| `MapInfo`、`Objects`、`Regions`、`t3*` | 地图设置、放置对象、区域和地形数据 |
| `Base.SC2Data/GameData/` | 兵种、武器、效果、能力等配置 |
| `zhCN.SC2Data/LocalizedData/` | 中文名称、说明和触发器文本 |
| `DocumentInfo` | 地图元数据和依赖清单 |

主包没有原始 `Triggers` 或 `ComponentList.SC2Components`。本目录供开发时查阅，`.gdignore` 将其排除在 Godot 资源导入之外。美术、音频和独立依赖包仍由原地图引用。

## 地图声明的依赖

- `bnet:沙漠风暴-美术音乐文件/0.0/179136,file:Mods\沙漠风暴-美术音乐文件.SC2Mod`
- `bnet:沙漠风暴-称号/0.0/179137,file:Mods\沙漠风暴-称号.SC2Mod`
- `bnet:沙漠风暴-PVE/0.0/179138,file:Mods\沙漠风暴-PVE.SC2Mod`
