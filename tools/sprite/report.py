#!/usr/bin/env python3
"""시범 결과를 한 장짜리 HTML 로 — 시트를 **실제로 12fps 로 돌려** 보여 준다.

    python3 tools/sprite/report.py --route krea --out /tmp/…/sprite_pilot.html

★ 시트를 data URI 로 박아 넣는다. 96x96 짜리 열두 칸이라 한 장이 몇 KB 뿐이고,
  그래야 파일 하나로 끝난다.
★ 애니메이션은 CSS `steps()` 로 `background-position` 을 밀어 준다 — 자바스크립트
  타이머로 돌리면 열 칸이 저마다 어긋난 채로 돈다.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import units as U                                # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")


def b64(path: str) -> str:
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def collect(route: str) -> list[dict]:
    rows = []
    qc = {}
    qp = os.path.join(OUT, route, "sheets", "qc.json")
    if os.path.exists(qp):
        for r in json.load(open(qp)):
            qc[(r["unit"], r["anim"])] = r
    for u in U.load():
        item = {"u": u, "anims": {}}
        mp = os.path.join(OUT, route, "master", u["id"] + ".png")
        if os.path.exists(mp):
            item["master"] = b64(mp)
        for anim in U.ANIMS:
            n = pixels.FRAMES[anim]
            p = os.path.join(OUT, route, "sheets", pixels.sheet_name(u["id"], anim, u["size"], n))
            if os.path.exists(p):
                item["anims"][anim] = {"src": b64(p), "n": n,
                                       "issues": qc.get((u["id"], anim), {}).get("issues", []),
                                       "picked": qc.get((u["id"], anim), {}).get("picked", [])}
        rows.append(item)
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="krea")
    ap.add_argument("--compare", default="sdxl", help="원화 비교용 다른 경로")
    ap.add_argument("--data", default=os.path.join(OUT, "report_data.json"))
    ap.add_argument("--template", default="")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    data = {
        "route": a.route,
        "fps": pixels.FPS,
        "rows": [],
    }
    rows = collect(a.route)
    other = {u["u"]["id"]: u.get("master") for u in collect(a.compare)}
    for it in rows:
        u = it["u"]
        data["rows"].append({
            "id": u["id"], "en": u["en"], "ko": u["ko"], "elem": u["elem"],
            "family": u["family"], "weapon": u["weapon"], "bullet": u["bullet"],
            "role": u["role"], "tier": u["tier"], "tier_ko": u["tier_ko"],
            "size": u["size"], "master": it.get("master"),
            "master_other": other.get(u["id"]),
            "anims": it["anims"],
        })
    json.dump(data, open(a.data, "w"), ensure_ascii=False)
    print(a.data, f"{os.path.getsize(a.data) / 1024:.0f} KB")

    if a.template and a.out:
        html = open(a.template, encoding="utf-8").read()
        blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
        html = html.replace("/*__DATA__*/", blob)
        open(a.out, "w", encoding="utf-8").write(html)
        print(a.out, f"{os.path.getsize(a.out) / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
