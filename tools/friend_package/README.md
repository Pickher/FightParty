# 朋友调试包启动脚本

这里保存 Windows 调试包的三个启动脚本模板。它们需要放到调试包根目录（与 `project.godot` 同级）才能使用，不要直接在本目录双击。

调试包制作步骤：

1. 在新的空文件夹中复制项目的 `project.godot`、`assets`、`data`、`scenes`、`scripts`，以及 `tools/import_units.py`，保持目录结构。
2. 将这里的三个 CMD 文件复制到包根目录；将 `docs/朋友调试说明.txt` 复制到根目录并命名为 `先读我-运行与兵种调试.txt`。
3. 在包根目录新建 `engine` 文件夹，放入 `Godot_v4.7.2-stable_win64.exe` 和 `Godot_v4.7.2-stable_win64_console.exe`。两个文件必须成对保留。保留 assets 中的 Godot 和字体许可证。
4. 不复制 `.git`、`.godot`、`*.import`、`__pycache__`、`data/backups`、Excel 锁文件、日志、个人存档或密钥。不包含 Python 安装包或 Python 运行时。
5. 压缩整个文件夹后，在新位置完整解压，运行 `开始游戏.cmd` 和 `导入兵种.cmd --check`。首次启动脚本会导入所需资源，再打开游戏。

Godot 引擎与 ZIP 作为下载产物分发，不放入源码历史。修改引擎版本时，需同时更新 CMD 中的文件名及调试说明，并重新验证首次启动。
