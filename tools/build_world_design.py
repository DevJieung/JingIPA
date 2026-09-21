#!/usr/bin/env python3
"""Build the world document, validated Krea input, and a local art gallery."""
from __future__ import annotations

import csv
import html
import json
import os
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art/concepts/last_refuge_v3'
ELEMENTS = {'water': '물 · 수리대', 'fire': '불 · 열기관대', 'ice': '얼음 · 보존대',
            'elec': '전기 · 송전대', 'none': '무속성 · 정비대'}
WEAPONS = {'sword': '검', 'whip': '채찍', 'bow': '활', 'gun': '총', 'deck': '광역'}
HANDS = ['하이카드', '원페어', '투페어', '트리플', '스트레이트', '플러시',
         '풀하우스', '포카드', '스트레이트 플러시', '로열 스트레이트 플러시']


def load_characters():
    roster = json.loads((ROOT / 'tools/roster.json').read_text())
    lookup = {u['id']: (i, u) for i, t in enumerate(roster['tiers'], 1) for u in t['units']}
    with (ROOT / 'docs/world_characters_v3.tsv').open() as f:
        chars = list(csv.DictReader(f, delimiter='\t'))
    assert len(chars) == 50 and len({c['id'] for c in chars}) == 50
    assert {c['id'] for c in chars} == set(lookup)
    for c in chars:
        assert len(c) == 7 and all(c.values()), c
        i, u = lookup[c['id']]
        c.update(name=u['ko'], tier=i, element=u['elem'], weapon=u['weapon'],
                 seed=26090900 + i*10 + list(ELEMENTS).index(u['elem']))
    refinements = ROOT / 'docs/world_v3_art_refinements.json'
    if refinements.exists():
        changes = json.loads(refinements.read_text())
        assert set(changes) <= set(lookup)
        for c in chars:
            if c['id'] in changes:
                change = changes[c['id']]
                assert set(change) <= {'prompt_en', 'pose_en', 'seed', 'init_image', 'strength'}
                c.update(change)
    for e in ELEMENTS:
        group = [c for c in chars if c['element'] == e]
        assert sorted(c['tier'] for c in group) == list(range(1, 11))
        assert Counter(c['weapon'] for c in group) == Counter({w: 2 for w in WEAPONS})
    for i in range(1, 11):
        assert {c['weapon'] for c in chars if c['tier'] == i} == set(WEAPONS)
    return sorted(chars, key=lambda c: (list(ELEMENTS).index(c['element']), c['tier']))


def build_document(chars):
    doc = (ROOT / 'docs/world_v3_setting.md').read_text()
    doc += '\n\n## 8. 전체 배치표\n\n'
    doc += '| 등급·족보 | 물 | 불 | 얼음 | 전기 | 무속성 |\n|---|---|---|---|---|---|\n'
    for tier in range(10, 0, -1):
        row = [f'{tier} · {HANDS[tier-1]}']
        for e in ELEMENTS:
            c = next(c for c in chars if c['tier'] == tier and c['element'] == e)
            row.append(f"{c['name']}({WEAPONS[c['weapon']]})")
        doc += '| ' + ' | '.join(row) + ' |\n'
    doc += '\n각 등급에는 다섯 무기가 한 번씩, 각 타입에는 무기마다 두 번씩 등장한다.\n'
    doc += '\n[50명 원화 갤러리 열기](art/concepts/last_refuge_v3/index.html)\n'
    for idx, (e, name) in enumerate(ELEMENTS.items(), 9):
        doc += f'\n## {idx}. {name} — 10명\n'
        for c in chars:
            if c['element'] != e:
                continue
            doc += f"\n### {c['tier']}등급 · {c['name']} — {c['title']}\n\n"
            doc += f"**{HANDS[c['tier']-1]} / {WEAPONS[c['weapon']]} / ID `{c['id']}`**\n\n"
            for title, field in [('외형과 실루엣', 'appearance'), ('장비가 공격을 만드는 원리', 'mechanism'),
                                 ('공격 모션', 'attack'), ('이 사람이 지키는 이유', 'story')]:
                doc += f"- **{title}:** {c[field]}\n"
            doc += f"\n[개별 T포즈 원화](art/concepts/last_refuge_v3/{c['id']}.png) · "
            doc += f"[실제 생성 프롬프트와 시드](art/concepts/last_refuge_v3/{c['id']}.json)\n"
    (ROOT / 'pokerdefense_world_characters_v2.md').write_text(doc)


def build_gallery(chars):
    cards = []
    for c in chars:
        esc = {k: html.escape(str(v), quote=True) for k, v in c.items()}
        cards.append(f'''<article class="card" data-element="{esc['element']}" data-tier="{esc['tier']}"
            data-search="{esc['name']} {esc['title']} {esc['id']} {WEAPONS[c['weapon']]}">
          <button class="art" data-id="{esc['id']}" aria-label="{esc['name']} 원화 크게 보기">
            <img src="{esc['id']}.png" alt="{esc['name']} 정면 T포즈 원화" loading="lazy" width="1024" height="1024"></button>
          <div class="copy"><div class="eyebrow">{ELEMENTS[c['element']]} · {c['tier']:02}등급 · {WEAPONS[c['weapon']]}</div>
          <h2>{esc['name']} <span>{esc['title']}</span></h2>
          <p class="hand">{HANDS[c['tier']-1]}</p>
          <details><summary>외형과 공격 읽기</summary><p>{esc['appearance']}</p>
          <p><b>장비</b> {esc['mechanism']}</p><p><b>동작</b> {esc['attack']}</p>
          <p class="story">{esc['story']}</p></details>
          <div class="links"><a href="{esc['id']}.png" download>PNG 저장</a><a href="{esc['id']}.json">생성 기록</a></div></div>
        </article>''')
    page = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>마지막 불빛의 카지노 · 50 수호자 원화</title><style>
*{box-sizing:border-box}body{margin:0;background:#f1ede5;color:#242b2b;font-family:system-ui,sans-serif}
header{padding:50px max(24px,5vw) 30px;background:#193b3c;color:#f9f4e8}header small{letter-spacing:.16em;color:#acd3c5}
h1{font-size:clamp(28px,4vw,48px);margin:14px 0}header p{max-width:780px;line-height:1.8;color:#d2dfd7}
header a{color:#f1d69b}nav{position:sticky;top:0;z-index:2;display:flex;flex-wrap:wrap;gap:10px;padding:16px 5vw;background:#f1ede5f5;border-bottom:1px solid #d7d0c2;align-items:center}
select,input{font:inherit;padding:10px;border:1px solid #c8c1b5;border-radius:5px;background:#fffdf8;max-width:100%}
input{min-width:180px}#count{margin-left:auto;color:#576662}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:24px;padding:28px 5vw 60px}
.card{background:#fffdf8;border:1px solid #d8d2c8;border-radius:10px;overflow:hidden;align-self:start}.card[hidden]{display:none}
.art{display:block;width:100%;padding:0;border:0;background:#e8e3da;cursor:zoom-in}.art img{display:block;width:100%;height:auto;aspect-ratio:1;object-fit:contain}
.copy{padding:20px}.eyebrow{font-size:12px;letter-spacing:.05em;color:#52736c}h2{font-size:23px;margin:10px 0 4px}h2 span{display:block;font-size:15px;font-weight:500;margin-top:6px;color:#4d5855}
.hand{font-size:12px;color:#7d7668;margin:12px 0}details{border-top:1px solid #e4ded4;padding-top:14px;font-size:14px;line-height:1.75}summary{cursor:pointer;font-weight:600}.story{color:#716753}
.links{display:flex;gap:18px;margin-top:18px;font-size:12px}a{color:#286758}dialog{border:0;border-radius:8px;padding:14px;max-width:96vw;max-height:96vh;background:#fffdf8}dialog::backdrop{background:#10221fde}
dialog img{display:block;max-width:90vw;max-height:80vh;object-fit:contain}dialog header{padding:8px 0;background:none;color:#242b2b;display:flex;justify-content:space-between;gap:20px;align-items:center}
dialog button{padding:8px 16px;font:inherit;cursor:pointer;border:1px solid #ccc;background:white;border-radius:4px}#empty{padding:40px 5vw;color:#666}
@media(max-width:500px){header{padding:32px 22px}.grid{padding:20px;gap:20px}nav{padding:12px 20px}#count{font-size:12px}}
</style><header><small>ALL-IN DEFENSE · WORLD & CHARACTER ART · REV.3</small>
<h1>마지막 불빛의 카지노</h1><p>좋은 패로 수호자를 불러, 피난소의 불을 지킨다.<br>도시를 유지하던 다섯 직능, 열 등급의 수호자. 캐릭터마다 외형을 설명하는 장비와 공격 동작을 함께 설계했습니다.</p>
<p>50명 · 개별 정면 T포즈 · 1024 × 1024 · Krea 2 Turbo<br><a href="../../../pokerdefense_world_characters_v2.md">세계관 및 전체 설정 문서</a></p></header>
<nav aria-label="캐릭터 필터"><select id="element" aria-label="타입"><option value="">모든 타입</option>__ELEMENT_OPTIONS__</select>
<select id="tier" aria-label="등급"><option value="">모든 등급</option>__TIER_OPTIONS__</select><input id="search" aria-label="이름 또는 무기 검색" placeholder="이름 · 무기 검색"><span id="count" aria-live="polite">50명</span></nav>
<main class="grid">__CARDS__</main><p id="empty" hidden>조건에 맞는 캐릭터가 없습니다.</p>
<dialog id="viewer"><header><b id="viewname"></b><button id="close">닫기</button></header><img id="large" alt=""></dialog>
<script>
const cards=[...document.querySelectorAll('.card')], element=document.querySelector('#element'),tier=document.querySelector('#tier'),search=document.querySelector('#search');
function filter(){let n=0;const q=search.value.trim().toLowerCase();cards.forEach(c=>{c.hidden=!!((element.value&&c.dataset.element!==element.value)||(tier.value&&c.dataset.tier!==tier.value)||(q&&!c.dataset.search.toLowerCase().includes(q)));if(!c.hidden)n++});document.querySelector('#count').textContent=n+'명';document.querySelector('#empty').hidden=n!==0;}
[element,tier,search].forEach(e=>e.addEventListener('input',filter));
const viewer=document.querySelector('#viewer'),large=document.querySelector('#large');
document.querySelectorAll('.art').forEach(b=>b.addEventListener('click',()=>{large.src=b.dataset.id+'.png';large.alt=b.querySelector('img').alt;document.querySelector('#viewname').textContent=b.closest('.card').querySelector('h2').textContent;viewer.showModal()}));
document.querySelector('#close').addEventListener('click',()=>viewer.close());viewer.addEventListener('click',e=>{if(e.target===viewer)viewer.close()});
</script></html>'''
    page = page.replace('__ELEMENT_OPTIONS__', ''.join(f'<option value="{e}">{n}</option>' for e,n in ELEMENTS.items()))
    page = page.replace('__TIER_OPTIONS__', ''.join(f'<option value="{i}">{i}등급 · {h}</option>' for i,h in enumerate(HANDS,1)))
    page = page.replace('__CARDS__', '\n'.join(cards))
    (OUT / 'index.html').write_text(page)


def main():
    chars = load_characters()
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / 'characters.tmp'
    tmp.write_text(json.dumps(chars, ensure_ascii=False, indent=2)+'\n')
    os.replace(tmp, OUT / 'characters.json')
    build_document(chars)
    build_gallery(chars)
    print('Validated 50 unique characters, 5 types x 10 tiers, original IDs and weapon distribution.')
    print('Built world document, generation manifest, and gallery.')


if __name__ == '__main__':
    main()
