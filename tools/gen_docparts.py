#!/usr/bin/env python3
"""제출 문서에 들어갈 **표와 차트 자료**를 게임 상수에서 찍어 낸다.

    python3 tools/gen_docparts.py        # docs/site/_*.html 을 다시 만든다

★ 왜 자동으로 만드는가: 로스터 쉰 줄과 체력 곡선을 문서에 **손으로** 옮겨 적으면,
  밸런스를 만진 날 게임만 바뀌고 문서는 옛 숫자로 남는다. 그 어긋남은 아무도 못 잡는다
  (`core/roster.gd` 를 `tools/roster.json` 에서 찍어 내는 것과 같은 까닭이다).

내는 것:
  _matrix.html   등급 10 x 속성 5 배치 행렬 (캐릭터 쉰 명 전부)
  _elem.html     속성 x 몸 상성표
  _data.html     차트가 읽는 숫자 (<script> 한 덩이)
"""
from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/site"

TIER_KO = ["하이카드", "원페어", "투페어", "트리플", "스트레이트",
           "플러시", "풀하우스", "포카드", "스트레이트 플러시", "로열 플러시"]
TIER_COLOR = ["#8b8b98", "#79c07a", "#5aa9d8", "#4a7fe0", "#8a6ae8",
              "#c15ce0", "#ff7ac0", "#ff9a3c", "#ffd24a", "#fff0b8"]
ELEM_KO = {"water": "물", "fire": "불", "ice": "얼음", "elec": "전기", "none": "무상성"}
ELEM_ORDER = ["water", "fire", "ice", "elec", "none"]
# ★ deck 을 「광역」으로 적으면 역할 칸의 「광역」과 같은 낱말이 한 칸에 두 번 찍힌다.
#   게임 UI 는 무기 이름을 한 번도 안 보여 주므로(내부 자료다) 문서에서만 「덱」으로 적는다.
WEAPON_KO = {"sword": "검", "gun": "총", "bow": "활", "whip": "채찍", "deck": "덱"}
ROLE_KO = {"single": "일격", "ricochet": "도탄", "rider": "특효", "area": "광역"}
PIP = {"water": "spade", "fire": "heart", "ice": "diamond", "elec": "club", "none": "star"}

# core/balance.gd 의 상수를 그대로 옮긴 것. 여기 값이 바뀌면 verify 가 아니라
# 사람이 봐야 하므로, 바뀔 만한 것만 몇 개 둔다.
HP_BASE, HP_GROW = 9.0, 1.1150
RAMP, RAMP_FADE = 3.2, 0.88
EARLY_TOUGH, EARLY_FADE = 0.45, 0.72
MAX_ON_FIELD, BOSS_EVERY = 72, 10


def wave_hp(w: int) -> float:
    mid = 1.0 + RAMP * (1.0 - RAMP_FADE ** (w - 1))
    early = 1.0 + EARLY_TOUGH * (EARLY_FADE ** (w - 1))
    return HP_BASE * (HP_GROW ** (w - 1)) * mid * early


def wave_count(w: int) -> int:
    if w % BOSS_EVERY == 0:
        return min(40, 4 + w // 2)
    if w <= 2:
        return 3 + w
    return min(MAX_ON_FIELD, 5 + int(w * 1.2))


def esc(s: str) -> str:
    return html.escape(str(s))


# --------------------------------------------------------------------------- #
def matrix(roster: dict) -> str:
    """등급 10 x 속성 5. **가로 한 줄이 한 등급**이고 세로 한 칸이 한 속성이다.

    설계서 §4 의 배치 행렬 그대로다 — 등급마다 속성 다섯이 하나씩, 무기 다섯도
    하나씩. 그래서 무기 칸을 세로로 훑으면 라틴 방진이 눈에 보인다.
    """
    # ★ `tier` 는 숫자가 아니라 이름("high" · "pair" …)이다. 차례가 곧 등급이므로
    #   enumerate 로 센다 — 이름 표를 여기에 또 두면 로스터가 바뀔 때 어긋난다.
    by = {}
    for ti, t in enumerate(roster["tiers"]):
        for u in t["units"]:
            by[(ti, u["elem"])] = u

    rows = []
    for ti in range(10):
        cells = []
        for el in ELEM_ORDER:
            u = by.get((ti, el))
            if u is None:
                cells.append('<td class="mx-cell"></td>')
                continue
            cells.append(
                f'<td class="mx-cell">'
                f'<div class="mx-name">{esc(u["en"])}</div>'
                f'<div class="mx-ko">{esc(u["ko"])}</div>'
                f'<div class="mx-tags"><span class="wp">{WEAPON_KO[u["weapon"]]}</span>'
                f'<span class="rl">{ROLE_KO[u["role"]]}</span></div>'
                f'</td>')
        rows.append(
            f'<tr><th class="mx-tier" scope="row">'
            f'<i class="mx-swatch" style="background:{TIER_COLOR[ti]}"></i>'
            f'<span class="mx-no">{ti}</span>{esc(TIER_KO[ti])}</th>'
            + "".join(cells) + "</tr>")

    head = "".join(
        f'<th scope="col"><svg class="pip" style="color:var(--e-{e})">'
        f'<use href="#pip-{PIP[e]}"/></svg><span>{ELEM_KO[e]}</span></th>'
        for e in ELEM_ORDER)
    return ('<div class="tbl-wrap"><table class="mx">\n'
            f'<thead><tr><th scope="col">등급 · 족보</th>{head}</tr></thead>\n'
            '<tbody>\n' + "\n".join(rows) + '\n</tbody></table></div>')


def elem_table() -> str:
    """속성 x 몸 상성표. 배수는 `Balance.MBODY` 를 그대로 옮긴 것이다."""
    bodies = [("aqua", "물"), ("flame", "불"), ("wood", "나무"),
              ("rock", "바위"), ("frost", "얼음")]
    # [몸][속성] = 배수
    m = {
        "aqua":  {"elec": 2.0, "water": .5, "fire": .5, "ice": .5, "none": 1.0},
        "flame": {"water": 2.0, "fire": .5, "ice": .5, "elec": 1.0, "none": 1.0},
        "wood":  {"fire": 2.0, "ice": 2.0, "water": .5, "elec": 0.0, "none": 1.0},
        "rock":  {"water": 2.0, "ice": 2.0, "fire": .5, "elec": 0.0, "none": 1.0},
        "frost": {"fire": 2.0, "water": .5, "ice": .5, "elec": 1.0, "none": 1.0},
    }
    def cell(v: float) -> str:
        if v == 0.0:
            return '<td class="x0" title="면역 — 한 톨도 안 들어간다">0배</td>'
        if v == 2.0:
            return '<td class="x2" title="약점 — 두 배">2배</td>'
        if v == 0.5:
            return '<td class="xh" title="저항 — 절반">0.5배</td>'
        return '<td class="x1">1배</td>'

    rows = []
    for bid, bko in bodies:
        avg = sum(m[bid][e] for e in ELEM_ORDER) / 5.0
        rows.append(f'<tr><th scope="row">{bko}</th>'
                    + "".join(cell(m[bid][e]) for e in ELEM_ORDER)
                    + f'<td class="n muted">{avg:.2f}</td></tr>')
    # 속성마다의 평균 — 전기가 왜 기본 화력을 되받는지가 이 줄에 있다
    foot = "".join(
        f'<td class="n"><b>{sum(m[b][e] for b, _ in bodies) / 5.0:.2f}</b></td>'
        for e in ELEM_ORDER)
    head = "".join(
        f'<th scope="col"><svg class="pip" style="color:var(--e-{e})">'
        f'<use href="#pip-{PIP[e]}"/></svg> {ELEM_KO[e]}</th>' for e in ELEM_ORDER)
    return ('<div class="tbl-wrap"><table class="af">\n'
            f'<thead><tr><th scope="col">몬스터의 몸</th>{head}'
            '<th scope="col" class="n">몸 평균</th></tr></thead>\n'
            '<tbody>' + "".join(rows) + '</tbody>\n'
            f'<tfoot><tr><th scope="row">속성 평균</th>{foot}<td></td></tr></tfoot>'
            '</table></div>')


def data_block(roster: dict) -> str:
    """차트가 읽는 숫자 한 덩이."""
    curve = [{"w": w, "hp": round(wave_hp(w)), "n": wave_count(w),
              "tot": round(wave_hp(w) * wave_count(w))} for w in range(1, 101)]
    # tools/verify.sh 7단계(자동 플레이 12판)의 실측. 손으로 옮긴 유일한 자리다.
    elems = [
        {"id": "none",  "ko": "무상성", "n": 1786, "pct": 26.5},
        {"id": "fire",  "ko": "불",     "n": 1720, "pct": 25.5},
        {"id": "ice",   "ko": "얼음",   "n": 1408, "pct": 20.9},
        {"id": "water", "ko": "물",     "n": 1099, "pct": 16.3},
        {"id": "elec",  "ko": "전기",   "n":  734, "pct": 10.9},
    ]
    n_units = sum(len(t["units"]) for t in roster["tiers"])
    return ("<script>\nconst DOC = " + json.dumps({
        "curve": curve, "elems": elems,
        "units": n_units,
        "monsters": len(roster["monsters"]),
        "themes": len(roster["themes"]),
    }, ensure_ascii=False, separators=(",", ":")) + ";\n</script>")


def main() -> int:
    roster = json.loads((ROOT / "tools/roster.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    for name, body in (("matrix", matrix(roster)),
                       ("elem", elem_table()),
                       ("data", data_block(roster))):
        p = OUT / f"_{name}.html"
        p.write_text(body, encoding="utf-8")
        print(f"  {p.relative_to(ROOT)}  {len(body):,}자")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
