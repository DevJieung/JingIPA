#!/usr/bin/env python3
"""Check shipped UI text and roster coverage without changing game files."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HANGUL = re.compile('[가-힣ㄱ-ㅎㅏ-ㅣ]')
LITERALS = re.compile(r'"(?:\\.|[^"\\])*"|#[^\n]*')


def main():
    catalog = json.loads((ROOT / 'core/locales/ui.json').read_text())
    concepts = json.loads((ROOT / 'core/locales/heroes.json').read_text())
    roster = json.loads((ROOT / 'tools/roster.json').read_text())
    errors = []
    # The roster's old lore is no longer rendered; hero concepts are the display copy.
    ignored = {'roster.gd', 'i18n.gd', 'dbg.gd', 'debug_view.gd', 'dbg_sim.gd'}
    for folder in ['core', 'game']:
        for path in (ROOT / folder).glob('*.gd'):
            if path.name in ignored:
                continue
            for match in LITERALS.finditer(path.read_text()):
                if match[0].startswith('#'):
                    continue
                text = json.loads(match[0])
                if HANGUL.search(text) and text not in catalog['en']:
                    errors.append(f'{path.relative_to(ROOT)}: missing English text: {text}')
    units = [unit for tier in roster['tiers'] for unit in tier['units']]
    if set(concepts) != {unit['id'] for unit in units}:
        errors.append('Hero concepts do not match the roster IDs')
    for unit in units:
        if not unit['ko'] or not unit['en']:
            errors.append(f"Missing hero name: {unit['id']}")
        for language in ['ko', 'en']:
            if not concepts.get(unit['id'], {}).get(language):
                errors.append(f"Missing {language} concept: {unit['id']}")
    for text in [*catalog['en'].values(), *(hero['en'] for hero in concepts.values())]:
        if HANGUL.search(text):
            errors.append(f'Korean text in English catalog: {text}')
    for language, entries in catalog.items():
        for source, target in entries.items():
            placeholders = re.findall(r'%(?:[-+0-9.]*[dfs]|%)', source)
            count = sum(token != '%%' for token in placeholders)
            slots = {int(slot) for slot in re.findall(r'\{(\d+)\}', target)}
            if slots != set(range(count)):
                errors.append(f'{language}: template values lost or added: {source} -> {target}')
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Localization: {len(catalog["en"])} English strings, {len(units)} bilingual heroes; no missing UI literals')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
