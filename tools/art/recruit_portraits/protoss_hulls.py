"""Recruit camera and finishes for the uploaded carrier and stalker meshes."""
import numpy as np


# Blender world is Z-up. Both models point along +X in the source.
VIEWS = {
    "carrier": (.49, -1.05, .88),
    "stalker": (1.4, -.61, .48),
}


def _carrier(tri, islands):
    # Paired wings frame the open hangars. Their lower rails, bridge canopy,
    # transverse bow clasps and long forward shell are all separate parts.
    materials = (
        "gold", "gold", "champagne", "champagne", "champagne",
        "cobalt", "blue", "bronze", "bronze", "champagne",
        "gold", "gold", "blue", "cobalt", "blue",
        "champagne", "champagne", "ivory", "navy", "cobalt",
        "cobalt", "champagne", "cyan", "cyan", "gold", "gold",
        "blue", "cobalt", "cobalt", "navy", "bronze",
        "gold", "gold", "champagne", "champagne", "blue", "blue",
        "champagne", "champagne",
    )
    finish = np.asarray(materials, dtype="<U12")[islands]
    x, _, z = tri[:, :, :3].mean(axis=1).T
    _, up, side = tri[:, :, 3:].mean(axis=1).T
    inward = side * np.sign(z - .003) < -.35
    lateral_armor = np.isin(islands, (0, 1))
    finish[lateral_armor & inward & (up < .08)] = "bronze"
    # Facing surfaces between the long lower rails and the hull form the
    # luminous hangar throat. Keep the outside raised lip in warm metal.
    rails = np.isin(islands, (27, 28))
    finish[rails & (up > .35) & (x < .31)] = "blue"
    finish[rails & (x > .31)] = "gold"
    # The oblong bridge has a bevel and a curved top. Dark glazing on the
    # flanks lets the smaller blue crown catch the studio light.
    canopy = islands == 26
    finish[canopy] = "cobalt"
    finish[canopy & (up < .22)] = "navy"
    finish[canopy & (up > .80)] = "blue"
    return finish


def _stalker(tri, islands):
    # Four opposing blade legs articulate through four independent knee
    # housings. A separate prow lens and the crown sit in front of the body.
    materials = (
        "cobalt", "violet", "violet", "cobalt", "gunmetal", "gunmetal",
        "violet", "navy", "violet", "cyan", "cobalt", "cobalt",
        "steel", "gunmetal", "violet", "gunmetal", "violet", "cyan",
    )
    finish = np.asarray(materials, dtype="<U12")[islands]
    x, y, z = tri[:, :, :3].mean(axis=1).T
    _, up, side = tri[:, :, 3:].mean(axis=1).T

    # Follow the elliptical stepped bezel already sculpted into the +Z
    # shoulder shield. The raised lens axis tips back with the shield.
    dx = x + .186 + .36 * (y - .760)
    bezel = (dx / .078) ** 2 + ((y - .760) / .119) ** 2
    shell = (islands == 3) & (side > .35)
    finish[(islands == 3) & (up > .74) & (y > .76)] = "silver"
    finish[shell & (bezel < 1.)] = "violet"
    finish[shell & (bezel < .66)] = "silver"
    finish[shell & (bezel < .42)] = "navy"
    finish[shell & (bezel < .19)] = "blue"

    # Follow the sculpted knee bosses and leave short polished bevels on
    # the pointed greaves. The greater inner face remains cobalt.
    shin = np.isin(islands, (1, 2, 14, 16))
    outward = side * np.sign(z + .053)
    finish[shin & (outward < .24)] = "cobalt"
    finish[shin & (up > .69)] = "silver"
    for part, cx, cy, lean in ((1, -.306, .47, .35), (2, -.29, .53, .35),
                               (14, .242, .421, .50), (16, .250, .395, .50)):
        knee = (((x - cx) + lean * (y - cy)) / .033) ** 2 + ((y - cy) / .052) ** 2
        facing = (islands == part) & (outward > .32)
        finish[facing & (knee < 1.)] = "silver"
        finish[facing & (knee < .37)] = "steel"
    finish[(islands == 12) & (x > .235)] = "navy"
    finish[(islands == 17) & (x > .318)] = "white_glow"
    return finish


def paint(unit, tri, islands):
    if unit == "carrier":
        return _carrier(tri, islands)
    if unit == "stalker":
        return _stalker(tri, islands)
    raise ValueError(f"Unsupported hull unit {unit!r}")
