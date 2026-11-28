"""Rebuild the Protoss recruit portraits from six game models and five painted masters."""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Blender runs -P files without adding their directory to the Python import path.
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
from protoss_finishes import MODEL_UNITS

MASTERS = HERE / "protoss"
OUT = HERE.parents[2] / "assets/ui/recruits"
PAINTED_UNITS = ("adept", "archon", "high_templar", "vanguard", "void_ray")
UNITS = tuple(sorted((*MODEL_UNITS, *PAINTED_UNITS)))


def _export_painted(unit, output):
    from PIL import Image

    with Image.open(MASTERS / f"{unit}.webp") as source:
        if source.mode != "RGBA" or source.width != source.height or source.width < 256:
            raise ValueError(f"Expected a square RGBA master of at least 256 px for {unit}")
        portrait = source.resize((256, 256), Image.Resampling.LANCZOS)
        portrait.save(output / f"{unit}.png", optimize=True)


def export(unit, output=OUT):
    """Rebuild one portrait from its current authoritative source."""
    rebuild([unit], output)


def rebuild(units, output=OUT):
    for unit in units:
        if unit not in UNITS:
            raise ValueError(f"Unknown Protoss portrait: {unit}")

    output = Path(output).resolve()
    models = [unit for unit in units if unit in MODEL_UNITS]
    if models and "bpy" not in sys.modules:
        subprocess.run(
            ["blender", "-b", "-t", "3", "--python-exit-code", "1", "-P",
             str(Path(__file__).resolve()), "--", "--output", str(output), *units],
            check=True,
        )
        return
    output.mkdir(parents=True, exist_ok=True)
    if models:
        sys.path.insert(0, str(HERE.parent))
        from render_recruit_models import render

        with tempfile.TemporaryDirectory() as work:
            for unit in models:
                render(unit, Path(work) / "portrait.png", output)

    for unit in units:
        if unit in PAINTED_UNITS:
            _export_painted(unit, output)


if __name__ == "__main__":
    if "bpy" in sys.modules:
        selection = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    else:
        selection = sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("units", nargs="*", help="Unit IDs; defaults to all eleven")
    parser.add_argument("--output", type=Path, default=OUT, help="Directory for the 256 px PNGs")
    args = parser.parse_args(selection)
    rebuild(args.units or UNITS, args.output)
