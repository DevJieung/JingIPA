#!/usr/bin/env python3
"""Write the exact built-in-imagegen jobs for the remaining 45 heroes."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art/animation/roster_v1"
units = json.loads((WORK / "roster.json").read_text())
specs = json.loads((ROOT / "tools/sprite/roster_sprite_specs.json").read_text())
elements = {"water": "turquoise and cobalt WATER with white foam and curled liquid tails",
            "fire": "orange and gold FIRE with a pale hot core and small ember tails",
            "ice": "cyan and pale-blue ICE with angular crystalline edges",
            "elec": "violet and gold ELECTRICITY with sharp white-yellow zigzag accents",
            "none": "ivory and warm gray NEUTRAL physical energy with small gold highlights"}
jobs = []
for unit in units:
    uid, bullet, weapon = unit["id"], unit["bullet"], unit["weapon"]
    identity, motion = specs[uid]
    if bullet == "zone":
        shot = ("four chronological AREA IMPACT frames only: small charge glyph, expanding elemental crest, "
                "full ground eruption, separated dissipating fragments. Mild overhead view, same ground anchor, "
                "small charge grows into full impact; no drawn circular range border")
    elif bullet in ("beam", "chain"):
        shot = ("four animation phases of a THIN HORIZONTAL " + ("connected lightning bridge" if bullet == "chain" else "coherent laser beam") +
                " segment traveling left-to-right. Bright narrow center, colored jagged edges, flat or softly tapered ends. "
                "At most 20% of each cell height, centered at y=192, spanning x=50..330. "
                "Phases change inner energy patterns only, same length and width. No impact explosion or circular burst")
    else:
        shape = {"bow": "slim arrow with a readable right-pointing head and a short left-side energy tail",
                 "gun": "compact right-pointing bolt with bright nose and a short left-side tail",
                 "sword": "compact rightward blade wave, a slim crescent with the leading curved edge on the right",
                 "whip": "compact rightward cable-tip energy wave, readable hooked leading tip and a short curved trailing arc"}[weapon]
        width = {"shot": "small compact", "pierce": "long narrow piercing", "splash": "broad heavy but compact", "ricochet": "small crisp bouncing"}[bullet]
        shot = (f"four LOOPING in-flight animation frames of a {width} {shape}. "
                "Every frame points RIGHT, nose at same x, body centered on y=192. At most 75% of cell width and 40% height. "
                "Keep the same projectile size through all four frames; subtly alternate tail and glints so frame4 returns to frame1. "
                "NO radial explosion, NO expanding ground ring, NO impact cloud. These frames are MOVING SHOTS, not impact effects")
    prompt = f"""Use case: stylized-concept. Production PIXEL ART sprite atlas for existing hero {unit['en'].upper()}.
The FIRST image is the IDENTITY reference: preserve {identity}. Keep the exact character's face, hair, body type, clothes, equipment and weapon. If the reference has damaged missing pixels in the hair, restore naturally matching hair, not magenta holes. The SECOND image is only the approved STYLE/LAYOUT reference (Thalassa); do not copy her hose, outfit or casting motion.
Create ONE exact 4-column by 3-row atlas, 1536x1152, twelve separate equal 384px square cells, no lines/gutters/labels/text. Genuine transparent alpha if supported; otherwise ONE perfectly flat pure magenta #FF00FF key background, including interior gaps. NEVER a checkerboard, ground shadow, scenery, gradient, or textured background.
Match the approved crisp small-scale fantasy camp pixel style: clean dark native-pixel outlines, consistent square pixel clusters, limited material shades, upper-left lighting, right-facing three-quarter view. All actor cells use the same camera, scale, head size, equipment and planted feet. Top of actor/gear near y=44, feet baseline y=338, boot center x=170. All weapons and raised hands stay INSIDE x=25..355 and y=25..350 with clear empty gaps between cells. No part touches adjacent cells. Do not shrink the character between poses.
ROW1: four distinct subtle IDLE phases, relaxed / slight shoulder rise / relaxed / slight shoulder fall. Feet and lower legs stationary. Small hair/cloth/equipment movements only; same anatomy, weapon and equipment in all frames.
ROW2: four ATTACK key poses: {motion}. This is a {weapon} user's motion. Keep the same weapon in the same hands. Only upper body/arms/weapon move; feet stay fixed. The release frame shows only a tiny muzzle/weapon flash, not a long projectile plume; projectiles belong in row3. Preserve the weapon's original length, keep its whole tip visible, angle it in three-quarter perspective when necessary to fit the cell.
ROW3: {shot}. Use {elements[unit['elem']]}, with enough character-specific equipment flavor to fit the weapon. No person, hand, weapon handle, text or UI in Shot cells. Keep all four effect sprites safely inset within their cells. Crisp nearest-pixel silhouettes, no soft blur.
"""
    jobs.append({"id": uid, "elem": unit["elem"], "weapon": weapon, "bullet": bullet,
                 "prompt": prompt, "references": [f"art/portraits/{uid}.png", "art/animation/element_aoe_v1/source/thalassa.png"],
                 "source": f"art/animation/roster_v1/source/{uid}.png", "status": "planned"})
(WORK / "jobs.json").write_text(json.dumps({"generator": "built-in image_gen", "jobs": jobs}, ensure_ascii=False, indent=2) + "\n")
print(len(jobs), "imagegen jobs recorded")
