"""Prompts for the brand paintings (key art, app icon). One place, so the record matches.

Motif decisions (PLAN.md O1/O11, D4 brief): the defended object is the **Soul Stone**
(소울 스톤 — a tall faceted cyan crystal with a warm golden star of light inside, the game's
Look.CRYSTAL #5fe6ff family), the heroes are the game's guardians (colour schemes of brasa,
limne, thalassa, jokull from art/models/portraits), the world is the blue night forest with
warm lanterns (docs/DESIGN_SYSTEM.md). No text is painted (wordmark is drawn in code).
"""

_STONE = ("the Soul Stone — a large, tall faceted crystal of luminous cyan and teal shaped like an "
          "elongated diamond, glowing from within with a brilliant warm golden star-shaped light")

_HEROES_SD = (
    "Four young guardian heroes with stylized super-deformed proportions (large heads, big expressive "
    "eyes, small sturdy bodies) stand around the altar in confident defensive poses, facing outward: "
    "a boy knight with dark purple hair in ornate red and gold plate armor holding a sword; a girl with a "
    "navy-blue bob haircut in a teal apron over cobalt-blue work overalls and rubber boots, a metal water "
    "tank with two hoses on her back; a silver-haired mage in a long teal coat with gold trim holding a "
    "glowing staff; and a white-bearded dwarf warrior in icy blue armor gripping a crystal ice sword.")

_HEROES_ANIME = _HEROES_SD.replace(
    "with stylized super-deformed proportions (large heads, big expressive eyes, small sturdy bodies)",
    "drawn in a polished anime style")

_WORLD = (
    "In the dark woods at the far left and far right edges, shadowy rift monsters with glowing orange "
    "eyes emerge from cracked purple rifts. Blue twilight atmosphere with low drifting fog, warm golden "
    "lanterns hanging from wooden posts, fireflies, tall dark pine silhouettes framing the scene, and a "
    "deep blue starry sky with a faint teal nebula filling the whole upper third of the picture, calm and "
    "uncluttered. The bottom edge is dark mossy ground in soft shadow.")

_STYLE = ("Polished premium mobile game key art, painterly digital illustration, soft rim light, rich "
          "contrast between cool blue night and warm lantern gold, cinematic lighting, highly detailed.")

KEYART_SD = ("Wide cinematic key art illustration for a cozy fantasy tower defense game. In the center of "
             "a moonlit forest clearing stands an ancient round stone altar carved with softly glowing golden "
             "runes, and floating above it is " + _STONE + ", casting teal light, light rays and tiny "
             "sparkles across the clearing. " + _HEROES_SD + " " + _WORLD + " " + _STYLE)

KEYART_ANIME = KEYART_SD.replace(_HEROES_SD, _HEROES_ANIME)

# Final key art (loading screen, 2026-10-19): s21 of keyart_sd read well; the stone rose into the
# band the wordmark needs, so the layout is spelled out and the knight's armour is the game's red.
KEYART_FINAL = (
    "Wide cinematic key art illustration for a cozy fantasy tower defense game. The whole scene sits in the "
    "lower two thirds of the picture: in a moonlit forest clearing an ancient round stone altar carved with "
    "softly glowing golden runes stands on the ground at the center, and just above the altar floats " + _STONE +
    ", casting teal light, soft light rays and tiny sparkles across the clearing; the top of the crystal is no "
    "higher than the middle of the picture. Four young guardian heroes with stylized super-deformed "
    "proportions (large heads, big expressive eyes, small sturdy bodies) stand on the ground beside the altar "
    "in confident defensive poses: a cheerful boy knight with dark purple hair in ornate crimson red and gold "
    "plate armor holding a sword; a girl with a navy-blue bob haircut in a teal apron over cobalt-blue work "
    "overalls and rubber boots, a metal water tank with two hoses on her back; a silver-haired young woman "
    "engineer with her hair in a bun, in a long navy and teal coat with gold trim, a large golden ring-shaped "
    "water device on her back, holding a brass staff; and a huge white-bearded explorer in a round "
    "polar-bear hood and quilted silver-blue armor gripping a wide translucent ice greatsword. In the dark woods at the far left and far right edges, shadowy rift monsters with "
    "glowing orange eyes emerge from cracked purple rifts. Warm golden lanterns hang from wooden posts, "
    "fireflies drift, low fog lies on the ground, tall dark pine silhouettes frame the sides. The entire upper "
    "third of the picture is open deep blue night sky with stars and a faint teal nebula and nothing else in "
    "it. The bottom edge is dark mossy ground in soft shadow. " + _STYLE)

KEYART_PLATE = ("Wide cinematic environment painting for a cozy fantasy tower defense game, no characters. "
                "In the center of a moonlit forest clearing stands an ancient round stone altar carved with "
                "softly glowing golden runes, and floating above it is " + _STONE + ", casting teal light, "
                "light rays and tiny sparkles across the clearing. " + _WORLD + " " + _STYLE)

ICON_STONE = (
    "Square emblem illustration for a fantasy tower defense game, with an edge-to-edge background and no "
    "frame or border. In the center, " + _STONE + ", mounted on an ornate golden heraldic shield with small "
    "spread golden wings and tiny star-shaped rivets. Soft teal light rays and sparkles around it. Deep "
    "midnight-blue background fading to dark teal behind the emblem, a few faint stars, warm golden rim "
    "light on the metal. Bold, simple, readable silhouette, centered, polished painterly premium game art, "
    "crisp clean edges, high contrast.")

ICON_HERO = (
    "Square character illustration for a fantasy tower defense game, with an edge-to-edge background and no "
    "frame or border: a close-up bust of a brave young knight hero with spiky dark purple hair, big bright "
    "amber eyes and a confident grin, wearing ornate red and gold armor, holding up a glowing cyan soul stone "
    "crystal beside his face, the crystal casting teal light on his cheek. Deep midnight-blue background with "
    "soft golden sparkles. Centered composition, bold readable silhouette, polished painterly premium mobile "
    "game art, stylized super-deformed proportions with a large head.")

ICON_BOX = (
    "Square emblem illustration for a fantasy tower defense game, with an edge-to-edge background and no "
    "frame or border: an ornate open golden jewel box with sapphire inlays, and rising from it " + _STONE +
    ", surrounded by golden star sparkles. Deep midnight-blue background with a soft teal glow behind the "
    "emblem, warm golden rim light. Bold, simple, readable silhouette, centered, polished painterly premium "
    "game art, crisp clean edges.")

EMBLEM_CUTOUT = (
    "A single game emblem asset isolated on a flat, solid, pure magenta background (#FF00FF) with nothing "
    "else, no shadow and no glow on the background. The emblem: " + _STONE + ", mounted on an ornate polished "
    "golden heraldic shield with a pointed bottom, small spread golden wings on both sides and star-shaped "
    "golden rivets. Bright specular highlights on the gold, clear dark outline around the whole emblem. "
    "Front view, perfectly centered and symmetrical, the emblem fills two thirds of the frame. Polished "
    "painterly premium mobile game art, crisp clean edges.")

ICON_HERO2 = (
    "Square character illustration for a fantasy tower defense game, with an edge-to-edge background and no "
    "frame or border: a close-up bust of a cheerful young guardian knight with spiky dark purple hair, big bright "
    "eyes and a confident smile, in ornate crimson red and gold armor, holding up with one gauntleted hand " +
    _STONE + " — the crystal is as tall as his head and floats just beside his face, lighting his cheek and "
    "armor with teal light. Deep midnight-blue background with soft golden sparkles. Centered composition, his "
    "face and the crystal fill the middle of the picture, bold readable silhouette, polished painterly premium "
    "mobile game art, stylized super-deformed proportions with a large head.")

STONE_CUTOUT = (
    "A single game asset isolated on a flat, solid, pure magenta background (#FF00FF) with nothing else, no "
    "shadow and no glow on the background: " + _STONE + ", floating upright on its own, with a few small "
    "crystal shards hovering around it. Bright facets, crisp light edges, a clear dark outline around the "
    "crystal. Front view, perfectly centered and symmetrical, the crystal fills three quarters of the frame "
    "height. Polished painterly premium mobile game art, crisp clean edges.")

JOBS = {
    "keyart_sd": dict(prompt=KEYART_SD, size=(2688, 1152)),
    "keyart_anime": dict(prompt=KEYART_ANIME, size=(2688, 1152)),
    "keyart_plate": dict(prompt=KEYART_PLATE, size=(2688, 1152)),
    "icon_stone": dict(prompt=ICON_STONE, size=(1536, 1536)),
    "icon_hero": dict(prompt=ICON_HERO, size=(1536, 1536)),
    "icon_box": dict(prompt=ICON_BOX, size=(1536, 1536)),
    "emblem_cutout": dict(prompt=EMBLEM_CUTOUT, size=(1024, 1024)),
    "keyart_final": dict(prompt=KEYART_FINAL, size=(2240, 960)),
    "icon_hero2": dict(prompt=ICON_HERO2, size=(1024, 1024)),
    "stone_cutout": dict(prompt=STONE_CUTOUT, size=(1024, 1024)),
}
