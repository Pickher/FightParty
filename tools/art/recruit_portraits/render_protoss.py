"""Export the painted Protoss masters as 256 px transparent recruit portraits."""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
MASTERS = HERE / "protoss"
OUT = HERE.parents[2] / "assets/ui/recruits"


def export(unit, output=OUT):
    from PIL import Image

    with Image.open(MASTERS / f"{unit}.webp") as source:
        if source.mode != "RGBA" or source.width != source.height or source.width < 256:
            raise ValueError(f"Expected a square RGBA master of at least 256 px for {unit}")
        output.mkdir(parents=True, exist_ok=True)
        portrait = source.resize((256, 256), Image.Resampling.LANCZOS)
        portrait.save(output / f"{unit}.png", optimize=True)


if __name__ == "__main__":
    for unit in sys.argv[1:] or sorted(path.stem for path in MASTERS.glob("*.webp")):
        export(unit)
