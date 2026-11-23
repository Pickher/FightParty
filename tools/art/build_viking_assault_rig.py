"""Assemble the uploaded assault Viking's connected armor, legs and Gatlings at their original pivots."""
from pathlib import Path

import numpy as np

from rigid_glb import Rig, face_normals, load_surface, matrix


DIRECTORY = Path(__file__).resolve().parents[2] / "assets/models/viking"
# Part numbers are connected islands in the uploaded mesh, welded by position.
PARTS = [
    ("Hull", (0, 0, 0), [0, 3, 4, 5, 6, 9, 10, 13, 14, 15]),
    ("LegLeft", (-0.14, 0.45, -0.12), [1, 2, 7, 11, 12, 16, 19]),
    ("LegRight", (-0.09, 0.46, 0.12), [8, 17, 18, 20, 21, 22]),
    ("GunLeft", (0.08, 0.53, -0.33), [24, 26, 28, 30, 33, 34, 36, 39, 40]),
    ("GunRight", (0.08, 0.56, 0.33), [23, 25, 27, 29, 31, 32, 35, 37, 38]),
]
# Blue-gray armor, titanium joints, brushed metal and amber canopy glazing.
FINISHES = [
    ("Armor", (.15, .235, .30), .35, .44),
    ("Frame", (.048, .064, .076), .55, .50),
    ("Steel", (.27, .32, .34), .72, .39),
    ("Canopy", (.78, .37, .074), .32, .23),
]


def build():
    triangles, islands = load_surface(DIRECTORY / "viking_assault.glb", 41)
    assert sorted(i for _, _, parts in PARTS for i in parts) == list(range(41))
    materials = [{"name": name, "pbrMetallicRoughness": {"baseColorFactor": [*color, 1.0],
                  "metallicFactor": metal, "roughnessFactor": rough}}
                 for name, color, metal, rough in FINISHES]
    rig = Rig(materials, "VikingAssault")
    rig.node("Viking", None, np.eye(4))
    centers = triangles[:, :, :3].mean(axis=1)
    paint = np.zeros(len(triangles), int)
    paint[np.isin(islands, [5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23, 24])] = 1
    paint[islands >= 25] = 2
    windshield = ((islands == 0) & (centers[:, 0] > .03) & (centers[:, 1] > .71)
                  & (np.abs(centers[:, 2]) < .12) & (face_normals(triangles)[:, 0] > .25))
    paint[windshield] = 3
    for name, pivot, parts in PARTS:
        selected = np.isin(islands, parts)
        frame = matrix(pivot)
        rig.node(name, "Viking", frame)
        rig.mesh(name, triangles[selected], paint[selected], frame)
    rig.write(DIRECTORY / "viking_assault_rig.glb")


if __name__ == "__main__":
    build()
