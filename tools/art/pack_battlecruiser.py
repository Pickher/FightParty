"""把大和舰 v4 侧视原画（1280×720，深色底，朝右）打包成游戏精灵图。
python3 tools/art/pack_battlecruiser.py   需要 Pillow、numpy、scipy；不改游戏代码。

输入 assets/units/battlecruiser/source/*.png；输出同目录上一级的 idle/move/fire/yamato/death.png 与 manifest.json。
所有原画共用同一画布坐标，所以每帧整体缩小 4 倍即可保持锚点一致：舰体约 3.1 格长，密度与特战队员相同（80 像素/格）。
"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/units/battlecruiser'
SRC = OUT / 'source'
BG = np.array([7, 13, 27])
SOURCE_FRAME = (1280, 720)
SCALE = 4
FRAME = (SOURCE_FRAME[0] // SCALE, SOURCE_FRAME[1] // SCALE)
# 舰体中心：move 帧舰体包围盒（尾喷口 200～舰首 1187，上下 90～555）的中点，即单位坐标所在点。
ANCHOR_SRC = (694.0, 322.0)
# 在 move-fire 与 move 的差分里量出的光束起点；round_muzzle 是 yamato 第 2 帧白热球中心。
MUZZLES_SRC = {
    'wing_barrel': (707, 528),
    'prow_low': (1160, 524),
    'prow_high': (1182, 492),
    'round_muzzle': (1045, 372),
}
# idle 原画是舰首上抬的姿态；与 move 的舰体轮廓对齐约需顺时针 5.25°。
IDLE_PITCH = 5.25
IDLE_FRAMES = 8
IDLE_PERIOD = 2.4


def load(name):
    return np.array(Image.open(SRC / f'{name}.png').convert('RGB')).astype(np.float32)


def strip(name, count):
    image = load(name)
    return [image[:, i * SOURCE_FRAME[0]:(i + 1) * SOURCE_FRAME[0]] for i in range(count)]


def matte(rgb):
    """去掉纯色底（底色完全均匀）：舰体（含被包围的暗部）不透明；舰体外的尾焰/光束/余烬按“颜色转透明”
    求最小 alpha 并反混合；其余贴近底色的暗边按差值渐隐，不反混合，避免暗灰被放大成白边。"""
    dist = np.abs(rgb - BG).max(2)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # 只有亮橙光核附近的橙色像素算发光；远处的暗红装甲板（含死亡碎片）仍按实体处理。
    seed = (r > 150) & (r > b + 60)
    glow = (r > b + 12) & (r > g + 6) & ndimage.binary_dilation(seed, iterations=48)
    core = ndimage.binary_fill_holes(ndimage.binary_closing((dist > 8) & ~glow, iterations=4))
    up = np.where(rgb > BG, (rgb - BG) / (255.0 - BG), 0.0)
    glow_alpha = np.clip(up.max(2), 0.0, 1.0)
    fringe_alpha = np.clip((dist - 3.0) / 6.0, 0.0, 1.0)
    outside_glow = glow & ~core
    alpha = np.where(core, 1.0, np.where(outside_glow, glow_alpha, fringe_alpha))
    safe = np.maximum(alpha, 1e-4)[..., None]
    color = np.where(outside_glow[..., None], np.clip(BG + (rgb - BG) / safe, 0, 255), rgb)
    return np.dstack([color, alpha * 255.0]).clip(0, 255).astype(np.uint8)


def shrink(rgba):
    image = Image.fromarray(rgba, 'RGBA').convert('RGBa')
    return image.resize(FRAME, Image.LANCZOS).convert('RGBA')


def rotate(rgba, degrees):
    image = Image.fromarray(rgba, 'RGBA').convert('RGBa')
    return np.array(image.rotate(degrees, resample=Image.BICUBIC, center=ANCHOR_SRC).convert('RGBA'))


def dim_exhaust(rgba, amount):
    """move 第 2 帧：尾焰亮核闪烁变暗；只改舰尾（x<300）的橙色像素。"""
    out = rgba.astype(np.float32)
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    flame = (r > b + 40) & (r > g + 20)
    flame[:, 300:] = False
    out[flame, :3] *= amount
    out[flame, 3] *= 0.6 + 0.4 * amount
    return out.clip(0, 255).astype(np.uint8)


def sheet(frames, name):
    image = Image.new('RGBA', (FRAME[0] * len(frames), FRAME[1]))
    for i, frame in enumerate(frames):
        image.paste(frame, (i * FRAME[0], 0))
    image.save(OUT / f'{name}.png', optimize=True)


def main():
    idle = matte(load('idle'))
    idle_frames = []
    for i in range(IDLE_FRAMES):
        # t=0 平飞 → 0.6 秒舰首上抬（原画姿态）→ 1.2 秒平飞 → 1.8 秒舰首下压。
        pitch = IDLE_PITCH * math.sin(math.tau * i / IDLE_FRAMES)
        idle_frames.append(shrink(rotate(idle, pitch - IDLE_PITCH)))
    move = matte(load('move'))
    fire = matte(load('move-fire'))
    sheet(idle_frames, 'idle')
    sheet([shrink(move), shrink(dim_exhaust(move, 0.55))], 'move')
    sheet([shrink(fire), shrink(move)], 'fire')
    sheet([shrink(matte(f)) for f in strip('yamato', 4)], 'yamato')
    sheet([shrink(matte(f)) for f in strip('death', 4)], 'death')
    to_frame = lambda p: [round(p[0] / SCALE, 2), round(p[1] / SCALE, 2)]
    manifest = {
        'version': 1,
        'frame_size': list(FRAME),
        'anchor': to_frame(ANCHOR_SRC),
        'pixels_per_cell': 80,
        'source': 'source/*.png（v4 侧视原画，1280×720，朝右）',
        'view': 'side',
        'directions': ['E'],
        'mirror_for_west': True,
        'muzzles': {k: to_frame(v) for k, v in MUZZLES_SRC.items()},
        'animations': {
            'idle': {'texture': 'idle.png', 'frames': IDLE_FRAMES, 'fps': IDLE_FRAMES / IDLE_PERIOD, 'loop': True},
            'move': {'texture': 'move.png', 'frames': 2, 'fps': 4, 'loop': True},
            'fire': {'texture': 'fire.png', 'frames': 2, 'fps': 10, 'loop': True},
            'yamato': {'texture': 'yamato.png', 'frames': 4, 'starts': [0.0, 1.2, 2.0, 2.45], 'end': 3.2, 'loop': False},
            'death': {'texture': 'death.png', 'frames': 4, 'starts': [0.0, 0.25, 0.56, 0.9], 'end': 1.4, 'loop': False},
        },
    }
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
