# 双端输入

- `desktop/formation_input.gd`：布阵区左键单兵/同类双击/框选，右键散布或长按拖线。
- `desktop/camera_input.gd`：WASD 镜头速度与时间积分，不下达战斗指令。
- `mobile/formation_input.gd`：原生触摸独占手势、点放/长按拖线，多指取消。
- `formation_panel.gd`：两端共享选择、预览和 `arrange_members` 提交；`formation_layout.gd`：共享确定性散布/拖线几何。

详见 [U05 实现与验收](../../docs/DESKTOP_INPUT.md)。本改动只完成静态审查，尚未运行 Godot 或设备验收。
