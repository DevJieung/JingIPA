#!/usr/bin/env python3
"""Generate the shipped audio via ElevenLabs. Keys stay in .env; originals are excluded from APK.
Official APIs: https://elevenlabs.io/docs/api-reference/music/compose
https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
Existing successful requests are reused; --only selects IDs; --install promotes validated audio.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import urllib.error
import wave
import numpy as np
from theme_music import THEME_MUSIC

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/audio_sources/elevenlabs_v1'
SCENE_MINOR_SOURCE = ROOT / 'art/audio_sources/elevenlabs_scene_minor_v2'
CARD_PRESENCE_SOURCE = ROOT / 'art/audio_sources/elevenlabs_card_presence_v3'

def source_for(ident, is_music):
    # Keep every previous arrangement intact when publishing a new scene track.
    base = SOURCE
    if is_music and ident == 'camp':
        base = SCENE_MINOR_SOURCE
    elif is_music and ident == 'ritual':
        base = CARD_PRESENCE_SOURCE
    return base / ('music' if is_music else 'sfx')

SFX = {
'shot_none': (.5, 'One tight wooden crossbow twang and dry card projectile snap, tactile fantasy weapon, short tail.'),
'shot_fire': (.5, 'One compact fire projectile launch, fast hot air whoosh with a crisp flame crack, no rumbling tail.'),
'shot_ice': (.5, 'One crisp ice shard launch, brittle crystal tick and tiny icy air swish, clean short tail.'),
'shot_elec': (.5, 'One compact lightning projectile zap, sharp electrical snap with a brief electric fizz, no sustained buzz.'),
'shot_water': (.5, 'One pressurized water bolt launch, rounded liquid plop and a quick fluid swish.'),
'shot_beam': (.7, 'One narrow magical laser beam firing, focused rising shimmer and firm clean energy snap.'),
'shot_zone': (.9, 'One magic area spell landing on stone, soft descending energy sweep then a contained bass thump.'),
'ric': (.5, 'One light metal projectile ricochet, bright quick ting with a directional swish, no long ringing.'),
'hit': (.5, 'One small dry fantasy combat impact, firm leather and wood thwack, immediate transient, brief tail.'),
'hit_weak': (.5, 'One effective magical weak-point hit, firm punch and bright crystalline accent, satisfying and very short.'),
'hit_resist': (.5, 'One muffled armored impact, dull compact wooden knock and light metallic rattle.'),
'hit_immune': (.5, 'One deflected spell off solid stone armor, short dry metallic clink with no damage explosion.'),
'crit': (.6, 'One critical strike impact, sharp bright metal crack layered with a compact deep punch.'),
'splash': (.8, 'One controlled fantasy blast, immediate punchy low impact and tiny debris scattering, fast decay.'),
'chain': (.6, 'A single quick electric arc jumping across three targets, three connected tight zaps, clear brief tail.'),
'die': (.5, 'One small fantasy creature dissolving into magical dust, soft compact puff and fading grains, no voice.'),
'die_big': (1.4, 'One large stone monster collapsing, weighty impact with crumbling rock and a short deep magical release.'),
'leak': (1.1, 'One precious crystal shattering, distinct glass crack, falling bright shards, soft low impact underneath.'),
'block': (.6, 'One magical crystal shield blocking an impact, warm rounded ping and a short protective energy ripple.'),
'stun': (.6, 'One electrical stun activation, tight crackle and short wavering energy ring, no voice.'),
'frost': (.7, 'One freeze effect forming, delicate ice crackle and sharp frost crystals spreading outward.'),
'wave': (1.6, 'A short fantasy battle start signal, one warm frame drum and two restrained low horn notes, confident.'),
'boss': (2.4, 'A short ominous boss arrival sting, deep cinematic drum, bowed metal swell, dark low brass impact.'),
'victory': (2.6, 'A tasteful short victory sting, warm chamber strings and celesta ascending to a resolved chord, mature fantasy.'),
'defeat': (2.6, 'A restrained short defeat sting, soft descending low strings and two dark piano notes, dignified, no voice.'),
'button': (.5, 'One premium game interface click, tiny tactile wood tap with a subtle glass tick, immediate and very short.'),
'buy': (.7, 'One fantasy purchase confirmation, two little gold coin clinks and a restrained warm chime.'),
'deal': (.5, 'One playing card dealt quickly onto felt, crisp paper flick and soft tap, close dry foley.'),
'flip': (.5, 'One playing card flipping between fingers, clean papery swish and a delicate snap, close dry foley.'),
'gain': (1.3, 'One hero joining the party confirmation, restrained warm magical bell chord with a soft grounded impact.'),
'stack': (.7, 'One pair of enchanted cards stacked together, tactile card clap and soft resonant gold chime.'),
'theme': (1.8, 'A short magical chapter transition, airy wind sweep and an elegant warm mystical bell swell.'),
'card_collect': (.8, 'Five playing cards swept together over felt into one stack, quick smooth paper shuffle ending in a neat tap.'),
'summon_charge': (1.3, 'Witch magic charging inside a stack of playing cards, swirling airy energy rising in pitch with tiny crystal sparks, no words.'),
'summon_burst': (1.7, 'One satisfying magical hero summon explosion, strong clean bass punch, wide paper burst and brilliant crystal sparkle tail.'),
'fusion_charge': (1.5, 'Five enchanted hero cards converging into a spinning magic seal, deep gathering energy with five delicate chimes, builds tension.'),
'fusion_burst': (2.0, 'One powerful hero fusion reveal, punchy full-bodied magical impact, radiant ascending crystal sparks and a rich short tail.'),
}
for tier in range(10):
    SFX[f'reveal{tier}'] = (1.0 + tier * .12, f'A single fantasy hero rarity reveal sting, rarity level {tier + 1} of 10. ' +
        ('Subtle warm celesta notes and a small magical shimmer.' if tier < 4 else 'Rich ascending celesta and chamber strings, sparkling magical resolution, increasingly grand but tasteful.') )
MUSIC = {
'camp': (60000, 'Dark medieval fantasy blacksmith forge refuge, a solemn place to prepare weapons before battle. Intimate bowed chamber strings: an expressive acoustic solo cello in the foreground answers a restrained melancholic violin melody over rich low viola and double bass drones. D minor, 64 BPM, slow measured 4/4, grounded weight, patient craftsmanship, glowing embers and weathered iron. Occasional very soft low frame drum and sparse muted metallic pitched percussion suggest distant hammer strokes musically, never literal sound effects. Long legato bow strokes, warm woody resonance, serious minor harmony, quiet dignified resolve. No plucked strings, no pizzicato, no celesta, no jaunty woodwinds, no whimsical or cheerful tune, no waltz, no pop beat, no bright major cadence. Distinct memorable descending violin motif, spacious dynamics for a fantasy strategy lobby. Fully instrumental continuous even-volume gameplay loop, music begins immediately, no silent intro, no fade-out, no final cadence, no speech, no choir, no vocals.'),
'ritual': (60000, 'Original memorable instrumental theme for choosing poker cards in All-in Defense, a high-stakes dark fantasy strategy game. C minor with harmonic-minor tension, steady 96 BPM in 4/4. A clearly audible close-recorded acoustic piano leads a distinctive repeating four-note motif in the middle and upper-middle register, answered by expressive mid-register violins and a subtle hammered dulcimer doubling selected melody notes. Firm articulated viola ostinatos and light dry frame-drum taps keep a confident measured pulse. Warm restrained cello supports the harmony without dominating. Serious elegant suspense, focused anticipation and royal resolve, melodic and engaging without becoming cheerful. The melody is immediately present from the first beat, remains clearly in front throughout, and varies gently across four-bar phrases. Intimate dry production with short room ambience, clear attacks, strong centered midrange that carries on small mobile phone speakers, rounded highs, controlled bass and even musical density. Leave space for short card flick and button sounds. No bass-led melody, no sub-bass drone, no muffled pads, no distant reverb wash, no piercing bells, no harsh cymbals, no trailer impacts, no swing, no jazz lounge, no playful waltz, no triumphant major chorus. Continuous even-volume gameplay loop with no silent intro, no quiet breakdown, no fade-out, no final cadence, no speech, no vocals, no choir.'),
'battle': (60000, 'Fantasy tower defense tactical battle background. 116 BPM steady pulsing strings, low frame drums, warm French horn accents, delicate magical celesta motif. Determined and energetic yet sustainable for repeated gameplay, no harsh cymbals, clear midrange space for combat sound effects. Continuous even-volume instrumental loop with no silent intro, no ending fade, no big final cadence, no vocals, no sound effects.'),
'boss': (48000, 'Fantasy tower defense boss battle background, 128 BPM driving low strings, taiko-like restrained deep drums, dark chamber brass, magical celesta motif. Urgent and formidable, adventurous not horror, controlled dynamics for phone speakers and clear combat sound effects. Continuous even-volume instrumental gameplay loop, no silent intro, no ending fade or final cadence, no vocals, no sound effects.'),
}
MUSIC.update(THEME_MUSIC)

def key_from_env():
    key = os.environ.get('ELEVENLABS_API_KEY', '')
    if not key:
        for line in (ROOT / '.env').read_text().splitlines():
            name, sep, value = line.partition('=')
            if sep and name.strip() == 'ELEVENLABS_API_KEY':
                key = value.strip().strip('"').strip("'")
                break
    if not key:
        raise SystemExit('ELEVENLABS_API_KEY missing')
    return key

def ffmpeg(args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *map(str, args)], check=True, capture_output=True)

def process_audio(src, out, music):
    if music:
        # Tail -> head overlap, then rotate past the overlap: end joins the start continuously.
        # Only the new card arrangement gets a gentle presence lift and bass trim.
        # Other shipped tracks retain their existing mastering and gain.
        card_music = out.stem == 'ritual'
        filters = ['-af', 'highpass=f=70,equalizer=f=1600:t=o:w=1.4:g=1.5'] if card_music else []
        raw = subprocess.run(['ffmpeg','-v','error','-i',str(src),*filters,'-f','f32le','-ac','2','-ar','44100','pipe:1'], check=True, capture_output=True).stdout
        data = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).copy()
        n = min(44100 * 2, len(data) // 10)
        w = np.linspace(0, 1, n, endpoint=True)[:, None]
        blend = data[-n:] * (1 - w) + data[:n] * w
        loop = np.concatenate((data[n:-n], blend))
        # Vorbis starts a new decoder window at the loop head. A 5 ms edge taper
        # keeps that window from creating a click even on bright/percussive themes.
        edge = min(221, len(loop) // 4)
        loop[:edge] *= np.linspace(0, 1, edge)[:, None]
        loop[-edge:] *= np.linspace(1, 0, edge)[:, None]
        # One gain for the entire loop: a dynamic loudness filter can apply
        # different gains to the matching head and tail and break their join.
        rms = float(np.sqrt(np.mean(loop ** 2)))
        peak = float(np.max(np.abs(loop)))
        if rms < .0001 or not np.isfinite(loop).all():
            raise ValueError('silent or invalid music')
        target_rms = .113 if card_music else .08  # Card theme: about +3 dB average level.
        loop *= min(target_rms / rms, .65 / peak)
        pcm = out.with_suffix('.f32')
        pcm.write_bytes(loop.astype('<f4').tobytes())
        ffmpeg(['-f','f32le','-ar','44100','-ac','2','-i',pcm,'-ar','44100','-c:a','libvorbis','-q:a','4',out])
        pcm.unlink()
    else:
        raw = subprocess.run(['ffmpeg','-v','error','-i',str(src),'-f','f32le','-ac','1','-ar','44100','pipe:1'], check=True, capture_output=True).stdout
        data = np.frombuffer(raw, dtype='<f4').copy()
        peak = float(np.max(np.abs(data)))
        if peak < .0001:
            raise ValueError('silent effect')
        active = np.flatnonzero(np.abs(data) > peak * .006)
        data = data[max(0, active[0] - 220):min(len(data), active[-1] + 900)]
        ident = out.stem
        target_peak = .26 if ident.startswith('shot_') or ident in ['ric', 'die', 'chain'] else .48
        if ident in ['hit', 'hit_resist', 'hit_immune', 'deal', 'flip', 'button']:
            target_peak = .23
        data *= target_peak / max(float(np.max(np.abs(data))), .0001)
        n = min(220, len(data)//4)
        data[:n] *= np.linspace(0,1,n)
        data[-n:] *= np.linspace(1,0,n)
        with wave.open(str(out), 'wb') as f:
            f.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
            f.writeframes((data * 32767).astype('<i2').tobytes())

def generate(job, key, install):
    ident, is_music = job
    source = source_for(ident, is_music)
    source.mkdir(parents=True, exist_ok=True)
    raw = source / (ident + '.mp3')
    out = source / (ident + ('.ogg' if is_music else '.wav'))
    meta = source / (ident + '.json')
    duration, prompt = (MUSIC if is_music else SFX)[ident]
    endpoint = 'music' if is_music else 'sound-generation'
    body = {'prompt': prompt, 'music_length_ms': duration, 'force_instrumental': True,
        'model_id': 'music_v2' if ident in THEME_MUSIC or ident in ('camp', 'ritual') else 'music_v1'} if is_music else {
        'text': 'Isolated professional game audio asset. No speech, no background ambience. ' + prompt,
        'duration_seconds': duration, 'prompt_influence': .5, 'model_id': 'eleven_text_to_sound_v2'}
    if not raw.exists():
        req = urllib.request.Request('https://api.elevenlabs.io/v1/' + endpoint + '?output_format=mp3_44100_128',
            data=json.dumps(body).encode(), headers={'xi-api-key': key, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=600) as res:
                content_type = res.headers.get('Content-Type', '')
                content = res.read()
                cost = res.headers.get('character-cost')
                song = res.headers.get('song-id')
        except urllib.error.HTTPError as exc:
            # Body can contain vendor error details, but never request headers/key.
            reason = exc.read().decode(errors='replace').replace(key, '[redacted]')[:600]
            raise RuntimeError(f'{ident}: HTTP {exc.code}: {reason}') from None
        if len(content) < 1000 or 'json' in content_type:
            raise RuntimeError(f'{ident}: invalid audio response')
        raw.write_bytes(content)
        meta.write_text(json.dumps({'id':ident, 'provider':'ElevenLabs', 'endpoint':endpoint, 'request':body,
            'character_cost':cost,'song_id':song,'source_sha256':hashlib.sha256(content).hexdigest()}, indent=2))
    process_audio(raw, out, is_music)
    if install:
        destination = ROOT / ('art/bgm' if is_music else 'art/sfx') / out.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        temp = destination.with_name(destination.name + '.tmp')
        temp.write_bytes(out.read_bytes())
        temp.replace(destination)
    print(f'OK {ident}: {out.stat().st_size} bytes', flush=True)
    return ident

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', default='')
    parser.add_argument('--themes', action='store_true', help='Generate the 50 theme tracks only')
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--workers', type=int, default=2)
    args = parser.parse_args()
    if args.themes and args.only:
        parser.error('Use --themes or --only, not both')
    selected = set(args.only.split(',')) if args.only else None
    if args.themes:
        selected = set(THEME_MUSIC)
    jobs = [(x, True) for x in MUSIC] + [(x, False) for x in SFX]
    if selected:
        jobs = [j for j in jobs if j[0] in selected]
        if {j[0] for j in jobs} != selected:
            raise SystemExit('Unknown audio ID')
    key = key_from_env()
    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(generate, j, key, args.install):j[0] for j in jobs}
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except Exception as exc:
                failures.append(futures[future])
                print('FAILED', str(exc).replace(key, '[redacted]'), flush=True)
    raise SystemExit(1 if failures else 0)

if __name__ == '__main__':
    main()
