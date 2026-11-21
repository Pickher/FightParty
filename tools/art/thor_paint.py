"""Source-space panel assignments for both of the untextured Thor meshes."""

import numpy as np


def _finish(name, color, metallic, roughness, emission=None):
    material = {
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorFactor": [*color, 1.0],
            "metallicFactor": metallic,
            "roughnessFactor": roughness,
        },
    }
    if emission:
        material["emissiveFactor"] = emission
    return material


# glTF color factors are linear. Muted blue steel keeps the light-catching
# edges visible at battlefield scale. Amber is reserved for the optical ports.
ARMOR, SHADE, GUN, STEEL, LENS, MARKING = range(6)
MATERIALS = [
    _finish("Armor", [0.237, 0.312, 0.347], 0.46, 0.45),
    _finish("ArmorShade", [0.105, 0.151, 0.174], 0.44, 0.49),
    _finish("Gunmetal", [0.048, 0.066, 0.076], 0.52, 0.50),
    _finish("Steel", [0.405, 0.440, 0.435], 0.62, 0.36),
    _finish("Lens", [0.93, 0.327, 0.047], 0.15, 0.24, [0.83, 0.221, 0.025]),
    _finish("Marking", [0.58, 0.304, 0.076], 0.29, 0.47),
]


def assign_paint(part, xyz, normal, islands):
    """Return one glTF material index per original triangle, before posing."""
    x, y, z = xyz.T
    nx, ny, nz = normal.T
    side = np.abs(z)
    paint = np.full(len(x), ARMOR, dtype=np.uint8)

    if part == "Trunk":
        paint[(y < 0.57) | (x < -0.145)] = SHADE
        paint[(x < -0.245) | (y < 0.465)] = GUN
        # Both raised cheek rails are separate full panels. Pick out their
        # recessed lamps, leaving the surrounding inset and frame visible.
        rail = np.isin(islands, [25, 26])
        paint[rail] = SHADE
        paint[rail & (ny > 0.72) & (y > 0.657)] = STEEL
        paint[rail & (x > 0.099) & (y > 0.538) & (y < 0.583) & (nx > 0.94)] = LENS
        # Narrow central face plate, immediately under the prow brow.
        visor = (x > 0.20) & (side < 0.029) & (y > 0.626) & (y < 0.669)
        paint[visor] = GUN
        paint[visor & (nx > 0.96) & (y > 0.635)] = LENS
        paint[islands == 29] = MARKING
        # Fixed outboard pack and the removable cheek/back mount hardware.
        paint[np.isin(islands, [9, 10, 24])] = GUN
    elif part == "Pelvis":
        paint[:] = SHADE
        paint[(y < 0.342) | (islands == 24)] = GUN
        paint[(x > 0.081) & (nx > 0.55)] = ARMOR
    elif part.startswith("Hip"):
        paint[:] = GUN
        paint[np.isin(islands, [18, 19]) & (side > 0.128)] = SHADE
        paint[np.isin(islands, [13, 14, 15, 16, 22, 23])] = STEEL
    elif part.startswith("Knee") or part.startswith("Ankle"):
        paint[:] = SHADE
        paint[np.isin(islands, [7, 8, 27, 28, 32, 33])] = ARMOR
        paint[np.isin(islands, [5, 6, 30, 31, 37, 38])] = GUN
        paint[np.isin(islands, [34, 35, 36, 39, 40])] = STEEL
        paint[np.isin(islands, [32, 33]) & (y < 0.025)] = GUN
    elif part.startswith("Shoulder"):
        # Local coordinates along and across the canted double-bore arm.
        # Normal incidence and plane depth select the muzzle face only.
        axial = 0.837 * x + 0.484 * y + 0.253 * side
        cap_normal = 0.837 * nx + 0.484 * ny + 0.253 * nz * np.sign(z)
        paint[:] = SHADE
        paint[(x < 0.071) & (y > 0.575)] = ARMOR
        paint[(x > 0.04) & (y < 0.59)] = GUN
        paint[(x > 0.103) & (axial > 0.496)] = ARMOR
        paint[axial > 0.579] = SHADE
        paint[axial > 0.625] = STEEL
        paint[(axial > 0.639) & (cap_normal > 0.94)] = GUN
        # Inset outer cheek of the shoulder pauldron.
        paint[(x < 0.054) & (y > 0.591) & (side > 0.339) & (np.abs(nz) > 0.86)] = MARKING
        paint[np.isin(islands, [9, 10])] = GUN
    elif part.startswith("Cannon"):
        inner = part.startswith("CannonInner")
        tip = 0.268 if inner else 0.338
        # Read all four tubes from the deployed source. Muzzle-relative
        # sleeve regions follow its modeled collars and receiver shrouds.
        depth = tip - x
        paint[:] = SHADE
        paint[(depth > 0.055) & (depth < 0.157)] = ARMOR
        paint[(depth > 0.238) & (depth < 0.294)] = STEEL
        paint[depth > 0.398] = ARMOR
        paint[depth < 0.055] = STEEL
        paint[(depth < 0.019) & (nx > 0.65)] = GUN
    return paint
