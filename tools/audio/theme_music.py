"""Distinct instrumental briefs for all 50 shipped battlefield themes."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PALETTES = {
    'aqua': 'Flowing harp arpeggios, rounded marimba, lyrical flute, fluid string ostinatos and soft rolling frame drums.',
    'flame': 'Rhythmic low strings, hammered dulcimer, warm assertive horns, dry hand drums and restrained metallic accents.',
    'wood': 'Organic plucked strings, breathy wooden flutes, bass clarinet, woody marimba and nimble hand percussion.',
    'rock': 'Grounded cello ostinatos, resonant low drums, bronze bells, sparse dulcimer and broad horn intervals.',
    'frost': 'Clear celesta, glassy bell tones, delicate high string pulses, cool airy woodwinds and muffled low drums.',
}
SCENES = {
    'calm_lake': 'A calm moonlit lake defended by a small refuge. Gentle rippling harp leads a hopeful pentatonic flute melody; calm resolve with a steady tactical pulse.',
    'reed_marsh': 'Reeds sway over a hidden marsh. A syncopated marimba figure and low bass flute answer each other over brushed hand drums, elusive and alert.',
    'aqueduct_ruin': 'An ancient aqueduct above deep blue water. Spacious stone-like bell intervals and stately plucked strings suggest forgotten engineering and resilient defenders.',
    'falls_gorge': 'A tall waterfall cuts through a narrow gorge. Descending harp cascades meet rising string figures and energetic rolling drums, adventurous vertical movement.',
    'tidal_flats': 'Tidal flats beneath a broad silver horizon. A gently swaying compound-meter rhythm, rounded bass and bright interlocking marimba suggest advancing tides.',
    'glacier_lake': 'A clear glacial lake below white mountain peaks. Crystal celesta doubles a spacious harp theme, cool sustained strings and measured drums convey shining depth.',
    'sunken_fleet': 'A graveyard of sunken ships. Low cello and a distant solo bassoon carry a nautical minor-mode melody above muted rolling drums; solemn determination.',
    'geyser_mud': 'A steaming field of geysers and dark mud pools. Playful low marimba ostinatos, short bass clarinet accents and upward string bursts form a restless asymmetric groove.',
    'deep_trench': 'The immense pressure of an abyssal ocean trench. Slow-moving contrabass harmony under a steady urgent drum pulse, sparse low harp and isolated celesta lights.',
    'maelstrom_sea': 'A vast spiraling maelstrom. Circular interlocking harp and strings, sweeping low horn phrases and surging tom patterns sustain an intense nautical battle.',
    'kiln_yard': 'An old pottery kiln glowing in a village yard. Warm dulcimer and small ceramic-like marimba notes above a compact earthy drum groove; intimate and industrious.',
    'burn_field': 'Fields burning at sunset. Nimble plucked strings and a rustic solo fiddle theme, crisp hand percussion and warm bass create determined forward motion.',
    'forge_canyon': 'A canyon sheltering a great forge. Measured bronze percussion, angular cello ostinatos and short horn calls evoke craftsmanship and gathering heat.',
    'burnt_forest': 'Charred tree trunks beneath drifting embers. A haunting oboe melody over dry plucked strings, restrained deep drums and glowing sustained viola chords.',
    'sulfur_springs': 'Sulfur springs among volcanic rocks. Winding bass clarinet figures, tremolo dulcimer and bubbling rhythmic pizzicato over a low, restless drum pulse.',
    'ash_city': 'The ruins of a city buried in ash. A dignified minor-mode horn melody with low strings and hollow bell accents, steady marching rhythm and stubborn hope.',
    'lava_river': 'A bright molten river flowing through black stone. Continuous quick cello figures, rising dulcimer runs and heavy rolling drums create liquid relentless momentum.',
    'obsidian_flats': 'A field of sharp black volcanic glass. Dry staccato strings, clear metallic bell intervals and tightly syncopated low percussion; angular and precise.',
    'volcano_crater': 'Defenders at the rim of an active volcano. Broad powerful horn intervals, forceful low-string ostinatos and deep layered drums; heroic heat and controlled urgency.',
    'ash_blizzard': 'Hot ash whirling through a volcanic storm. Fast circling viola phrases, high shimmering dulcimer and surging low drum rolls, dark windborne intensity.',
    'spring_grove': 'A bright grove in early spring. A buoyant wooden flute melody with warm acoustic plucks and tiny hand drums; fresh growth, welcoming but ready for battle.',
    'mushroom_hollow': 'A secret hollow full of luminous mushrooms. Quirky bass clarinet and hollow marimba exchange little motifs over a lilting pizzicato groove, curious and magical.',
    'bamboo_grove': 'Tall bamboo casts narrow shifting shadows. Airy bamboo-flute-like phrasing and dry wooden percussion, spare pentatonic plucks and agile syncopation.',
    'vine_ruins': 'Vines reclaim an ancient sanctuary. Intertwining lute and flute figures, moss-soft viola chords and a measured ritual hand-drum pattern.',
    'misty_cedar': 'Old cedar trees disappear into silver mist. A breathy low flute melody and slow-moving warm strings over quiet but insistent woody percussion.',
    'thornbrake': 'A dense maze of sharp thorn branches. Short sharp pizzicato figures, angular marimba patterns and tense hand drums, cunning movement and quick tactical turns.',
    'moss_bog': 'Deep green moss floats over a hidden bog. Dark bass clarinet, rounded low marimba and loping hand drums, mysterious earthy harmonic motion.',
    'frost_pines': 'Frost coats a forest of tall pines. Wooden flute and cool celesta trade a restrained motif over crisp plucked strings, organic warmth beneath winter light.',
    'rotroot_hollow': 'A hollow beneath immense decaying roots. Low woody percussion and contrabass clarinet, twisting cello pulses and sparse eerie dulcimer, threatening yet adventurous.',
    'worldtree_roots': 'The vast living roots of the world tree. A noble expansive horn-and-flute melody, deep resonant wooden drums and interwoven flowing strings; ancient living strength.',
    'gravel_hills': 'Rolling gravel hills on the edge of a refuge. A simple sturdy cello theme, light bronze accents and warm steady hand drums, grounded adventurous optimism.',
    'stone_terraces': 'Old stone terraces step down a mountain. Repeating ascending dulcimer figures, plucked cello and small bronze bells, measured geometric rhythms.',
    'quarry_pit': 'A deep quarry with enormous cut stone blocks. Firm low drum patterns, resonant cello plucks and open horn calls, purposeful industrious weight.',
    'red_canyon': 'A sweeping red sandstone canyon at dusk. Spacious low flute phrases and broad horn intervals over dry hand drums and rolling acoustic plucks.',
    'broken_wall': 'Defenders hold a shattered ancient fortress wall. A resolute restrained brass motif, marching low strings and worn bronze bell accents, stubborn courage.',
    'crystal_cavern': 'An underground cavern filled with glowing crystals. Interlocking celesta and dulcimer ostinatos, deep bowed cello and resonant sparse drums, luminous subterranean mystery.',
    'desert_mesa': 'Isolated rock mesas rise from a hot desert. Modal plucked-string melody, dry hand drums, distant low flute and sustained open cello fifths, spacious and watchful.',
    'iron_mine': 'A dark iron mine descending below the mountains. Muted metallic rhythmic ticks, deep cello ostinatos and heavy low drums, determined mechanical momentum.',
    'peak_cliffs': 'Sheer cliffs at a windswept mountain summit. Soaring horn phrases above low steady strings and spacious deep drums, height, endurance and hard-earned resolve.',
    'rift_chasm': 'A vast earthquake fissure opens through ancient stone. Forceful uneven drum accents, grinding low-string rhythmic tension and broad dark horn calls, monumental pressure.',
    'first_snow_hills': 'The first snow settles on gentle hills. Light celesta melody, warm muted strings and a soft steady drum pulse, fresh wonder with quiet courage.',
    'frozen_pond': 'A frozen village pond sparkles beneath pale moonlight. Tiny bell figures and delicate harp notes circle a lyrical flute theme, clear intimate rhythmic motion.',
    'snowed_village': 'Snow covers an abandoned mountain village. A wistful oboe melody and soft felted piano with pizzicato strings, determined footsteps in a quiet winter setting.',
    'frost_gorge': 'A narrow gorge lined with hard blue frost. Crisp descending celesta patterns, agile high-string ostinatos and firm muted drums, sharp and focused.',
    'drift_ice_sea': 'Floating ice crosses a cold northern sea. Swaying low strings and a broad lonely horn melody, sparse crystal bells and rolling restrained drums.',
    'icicle_cave': 'Long icicles hang over a hidden cave. Closely interlocking glass-bell and celesta phrases over a dark bassoon line and hollow muffled percussion.',
    'blizzard_plateau': 'A relentless blizzard sweeps a high plateau. Rapid circling high strings and celesta fragments above driving low drums, urgent endurance and controlled cold intensity.',
    'glacier_crevasse': 'A luminous blue crevasse cuts deep into a glacier. Descending crystal arpeggios, low cello pulses and spacious isolated horn intervals, immense frozen depth.',
    'ice_spire_field': 'Towering ice spires catch the last cold light. Brilliant angular celesta motifs, ascending violins and firm deep drum accents, majestic crystalline geometry.',
    'polar_night': 'A vast polar icefield beneath a star-filled endless night. A slow noble bassoon melody over quick restrained string pulses, distant glistening celesta and deep steady drums.',
}


def theme_music():
    themes = json.loads((ROOT / 'tools/roster.json').read_text())['themes']
    assert set(SCENES) == {theme['id'] for theme in themes}, 'Every theme needs a music brief'
    result = {}
    for theme in themes:
        tempo = 104 + (theme['rank'] - 1) * 5
        prompt = (
            'Original fantasy tactical tower defense game soundtrack, intimate orchestral and acoustic palette, '
            'a memorable motif unique to this location. ' + SCENES[theme['id']] + ' '
            + PALETTES[theme['main_body']] + f' Around {tempo} BPM. '
            'Sustainable energetic gameplay underscore, clear space for combat effects and mobile speakers. '
            'Continuous even-volume instrumental loop, established rhythm from the first beat, '
            'no silent intro, no ending fade, no dramatic final cadence, no abrupt breakdown, '
            'no vocals, no choir, no speech, no environmental sound effects, no harsh cymbals.'
        )
        result['theme_' + theme['id']] = (60000, prompt)
    return result


THEME_MUSIC = theme_music()
