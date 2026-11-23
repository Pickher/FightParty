"""Bake the 64 px recruit buttons from the full-size portraits using Pillow."""
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / "assets/ui/recruits"
EDGE = 64
COLUMNS = 8


def build():
    units = json.loads((ROOT / "data/units.json").read_text(encoding="utf-8"))["units"]
    kinds = sorted(kind for kind, stats in units.items()
                   if stats.get("status") == "ready" and stats.get("available", True)
                   and not stats.get("structure", False))
    rows = (len(kinds) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * EDGE, rows * EDGE))
    resources = [
        f'[gd_resource type="SpriteFrames" load_steps={len(kinds) + 2} format=3]',
        '[ext_resource type="Texture2D" path="res://assets/ui/recruits/thumbnails.png" id="1_atlas"]',
    ]
    animations = []
    for index, kind in enumerate(kinds):
        x = (index % COLUMNS) * EDGE
        y = (index // COLUMNS) * EDGE
        with Image.open(DIRECTORY / f"{kind}.png") as original:
            if original.mode != "RGBA" or original.size != (256, 256):
                raise ValueError(f"Expected a transparent 256 × 256 portrait for {kind}")
            tile = original.resize((EDGE, EDGE), Image.Resampling.LANCZOS)
        sheet.paste(tile, (x, y))
        resource = f"Tile_{index}"
        resources.append(
            f'[sub_resource type="AtlasTexture" id="{resource}"]\n'
            f'atlas = ExtResource("1_atlas")\n'
            f'region = Rect2({x}, {y}, {EDGE}, {EDGE})\n'
            'filter_clip = true'
        )
        animations.append(
            '{"frames": [{"duration": 1.0, "texture": SubResource("' + resource + '")}], '
            '"loop": false, "name": &' + json.dumps(kind) + ', "speed": 1.0}'
        )
    resources.append('[resource]\nanimations = [\n' + ',\n'.join(animations) + '\n]')
    sheet.save(DIRECTORY / "thumbnails.png", optimize=True)
    (DIRECTORY / "thumbnails.tres").write_text("\n\n".join(resources) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
