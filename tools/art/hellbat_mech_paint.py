"""Panel finishes for the untextured mech, sampled from the Hellion's red-and-steel livery."""

import numpy as np

RED, OXBLOOD, FRAME, STEEL, RUBBER, GLASS, IVORY, HOT = range(8)


def _material(name, rgb, metal, rough, emission=None):
    # glTF expects linear baseColorFactor; the reference texture is sRGB.
    srgb = np.asarray(rgb) / 255.0
    linear = np.where(srgb <= .04045, srgb / 12.92, ((srgb + .055) / 1.055) ** 2.4)
    material = {
        "name": name,
        "pbrMetallicRoughness": {"baseColorFactor": [*linear.tolist(), 1.0],
                                "metallicFactor": metal, "roughnessFactor": rough},
    }
    if emission is not None:
        material["emissiveFactor"] = emission
    return material


MATERIALS = [
    _material("Carmine enamel", (176, 54, 66), .32, .40),
    _material("Recessed red steel", (112, 37, 48), .35, .53),
    _material("Blued chassis", (69, 71, 86), .51, .50),
    _material("Cold steel", (127, 129, 150), .62, .41),
    _material("Carbon rubber", (38, 37, 43), .07, .82),
    _material("Golden canopy", (206, 147, 76), .42, .24, [.048, .019, .003]),
    _material("Ivory identifier", (205, 201, 193), .24, .44),
    _material("Burner pilot", (243, 153, 62), .25, .31, [.59, .19, .024]),
]


# The uploaded shields are posed individually; use their respective longitudinal,
# cross-panel and outward axes so the enamel and edge rails follow the castings.
_SHIELDS = {
    10: ((.134, .455, .329), (-.605, -.562, .564), (-.642, .763, .073), (.472, .318, .822)),
    21: ((.153, .439, -.339), (-.393, -.709, -.585), (-.603, .679, -.418), (.694, .188, -.695)),
}


def assign_paint(part, xyz, normal, islands):
    """Return per-face swatches in original, standing-source coordinates."""
    x, y, z = xyz.T
    nx, ny, nz = normal.T
    finish = np.full(len(x), FRAME, dtype=np.uint8)

    body = islands == 4
    finish[body & (y > .366)] = OXBLOOD
    finish[body & (y > .489) & (x < .095)] = RED
    # A blued keel and bright bevel frame the small gold cockpit.
    finish[body & (x > .08) & (np.abs(z) < .10)] = FRAME
    finish[body & (x > .141) & (y > .47) & (ny > .54)] = STEEL
    canopy = islands == 24
    finish[canopy] = GLASS
    finish[canopy & ((y < .599) | (x < .045))] = FRAME

    for tag, (center, longitudinal, across, outward) in _SHIELDS.items():
        choose = islands == tag
        if not np.any(choose):
            continue
        points = xyz[choose] - center
        depth = points @ outward
        length = points @ longitudinal
        edge = points @ across
        shell = np.full(len(points), FRAME, dtype=np.uint8)
        shell[depth > -.012] = OXBLOOD
        panel = (depth > -.012) & (normal[choose] @ outward > .28)
        shell[panel] = RED
        shell[panel & (np.abs(edge) > .087)] = OXBLOOD
        # The light stencil sits on the tip face between the edge rails.
        shell[panel & (length > .169) & (length < .224) & (edge > .026)] = IVORY
        finish[choose] = shell

    # Rear drums retain red-painted bodies, dark gaskets and cold end caps.
    for tag, center, axis in [(7, (-.095, .559, .255), (-.420, .534, .733)),
                              (3, (-.136, .562, -.230), (-.528, .498, -.688))]:
        choose = islands == tag
        if not np.any(choose):
            continue
        points = xyz[choose] - center
        axial = points @ axis
        radial = np.linalg.norm(points - axial[:, None] * axis, axis=1)
        drum = np.full(len(points), RED, dtype=np.uint8)
        drum[np.abs(axial) > .048] = OXBLOOD
        drum[np.abs(axial) > .059] = FRAME
        drum[(axial > .061) & (radial < .076)] = STEEL
        finish[choose] = drum

    feet = np.isin(islands, (12, 15))
    finish[feet & (y > .235)] = OXBLOOD
    finish[feet & (y > .255) & (x > .025)] = RED
    finish[feet & (y < .13) & (x > .131) & (nx > .25)] = STEEL
    finish[feet & (y < .045)] = RUBBER
    # Each fused lower leg carries an actual wheel. Keep its tire and hub
    # distinct from the toe and from the enamel plate over the upper linkage.
    for tag, cx, cy, cz in [(12, .005, .086, .19), (15, .036, .085, .18)]:
        radial = np.hypot(x - cx, y - cy)
        tire = (islands == tag) & (np.abs(z) > cz) & (radial < .114)
        finish[tire] = RUBBER
        finish[tire & (np.abs(nz) > .68) & (radial < .085)] = FRAME
        finish[tire & (np.abs(nz) > .70) & (radial < .057)] = STEEL
    finish[np.isin(islands, (11, 14, 19, 20, 23))] = STEEL
    finish[np.isin(islands, (16, 18, 17, 22))] = FRAME
    finish[np.isin(islands, (25, 26))] = OXBLOOD
    finish[np.isin(islands, (25, 26)) & (ny > .65)] = STEEL

    # Same lengthwise pattern as the buggy's single flame projector: red reservoir
    # behind a silver coupling, then the heat-darkened forward nozzle.
    tube = islands == 2
    finish[tube] = FRAME
    finish[tube & (y > .745) & (x < -.165)] = RED
    finish[tube & (x < -.260)] = OXBLOOD
    finish[tube & (x < -.283)] = STEEL
    finish[tube & (x > -.124) & (x < -.058)] = STEEL
    finish[tube & (x > -.058) & (x < -.035)] = OXBLOOD
    finish[tube & (x > .030) & (nx > .72)] = HOT
    finish[np.isin(islands, (1, 8, 9, 13))] = STEEL
    finish[np.isin(islands, (0, 5, 6))] = RUBBER
    return finish
