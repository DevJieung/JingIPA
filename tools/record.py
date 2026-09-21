#!/usr/bin/env python3
"""소개 영상을 굽는다. 이 머신에 화면이 없어도 된다.

    python3 tools/record.py                 # 전부 (약 15분)
    python3 tools/record.py --frames 240    # 앞 8초만 (연기 검사)
    python3 tools/record.py --fps 30 --res 1280x800

가상 프레임버퍼(Xvfb) 위에서 Godot 을 띄우고 `--write-movie` 로 **프레임을 통째로**
받아 낸다. 대본은 `tests/demo.gd` 다.

★ **화면 녹화(x11grab)가 아니다.** 소프트웨어 OpenGL 이라 실시간으로는 5~10fps 밖에
  못 그리는데, 그것을 그대로 녹화하면 영상이 뚝뚝 끊긴다. `--fixed-fps` 를 걸면 Godot 이
  한 프레임을 정확히 1/fps 초로 **치고** 다 그린 뒤 다음으로 넘어가므로, 그리는 데
  아무리 오래 걸려도 나온 영상은 매끈한 30fps 다.

★ 소리도 같이 나온다. `MovieWriterPNGWAV` 가 PNG 낱장 옆에 .wav 를 하나 남기고,
  여기서 ffmpeg 이 둘을 합친다. (`core/sound.gd` 는 헤드리스에서만 소리를 끄는데,
  Xvfb 는 x11 이라 켜진 채로 돈다)

★ PNG 낱장으로 받는 까닭: 도트 그림이라 중간 압축이 한 번만 있어야 한다. MJPEG(.avi)
  로 받으면 손실 압축을 두 번 타서 96px 스프라이트의 테두리가 뭉갠다.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

from godot_env import ROOT, GODOT, xvfb     # 같은 Xvfb 를 촬영·검토 도구와 나눠 쓴다

DISPLAY_NUM = 94          # screenshot.py(93)와 겹치지 않게 — 둘을 같이 돌릴 수 있다


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--res", default="1280x800")
    ap.add_argument("--frames", type=int, default=0, help="이 프레임 수만 찍고 끝낸다")
    ap.add_argument("--work", default=str(ROOT / "build/video"))
    ap.add_argument("--out", default=str(ROOT / "build/all-in-defense-demo.mp4"))
    ap.add_argument("--keep", action="store_true", help="낱장 PNG 를 안 지운다")
    args = ap.parse_args()

    work = Path(args.work)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    w, h = args.res.split("x")
    # ★ `project.godot` 의 `window_width_override`(1000x625)를 잠깐 끈다.
    #   Godot 의 무비 라이터는 **뷰포트가 아니라 창 크기**로 받아 낸다 — 그대로 두면
    #   1280x800 도트 화면이 1000x625 로 줄어 들어와서 96px 스프라이트가 뭉개지고,
    #   높이 625 는 홀수라 x264 가 아예 인코딩을 거절한다(실측).
    #   `override.cfg` 는 Godot 이 프로젝트를 **실행할 때만** 읽는다(에디터는 안 읽는다).
    ovr = ROOT / "override.cfg"
    ovr.write_text("[display]\n\n"
                   f"window/size/window_width_override={w}\n"
                   f"window/size/window_height_override={h}\n", encoding="utf-8")
    t0 = time.time()
    try:
        with xvfb(DISPLAY_NUM, args.res) as env:
            p = _record(args, work, env)
        if p.returncode != 0:
            sys.stderr.write(p.stderr[-4000:])
            print(f"!! Godot 이 {p.returncode} 로 끝났습니다")
            return 1
        # ★ 종료 코드가 0 이어도 스크립트 오류는 따로 봐야 한다(CLAUDE.md verify 3번).
        for bad in ("SCRIPT ERROR", "Parse Error", "triangulation failed"):
            if bad in p.stdout or bad in p.stderr:
                print(f"!! 출력에 '{bad}' 가 있습니다")
                for ln in (p.stdout + p.stderr).splitlines():
                    if bad in ln:
                        print("   " + ln)
                return 1
    finally:
        ovr.unlink(missing_ok=True)     # 저장소에 남기면 게임이 늘 그 크기로 뜬다

    pngs = sorted(work.glob("f*.png"))
    wavs = sorted(work.glob("*.wav"))
    if not pngs:
        print("!! 프레임이 한 장도 안 나왔습니다")
        return 1
    secs = len(pngs) / args.fps
    print(f"\n프레임 {len(pngs)}장 · {secs:.1f}초 · 그리는 데 {time.time() - t0:.0f}초")
    _encode(args, work, pngs, wavs, secs)
    return 0


def _record(args: argparse.Namespace, work: Path, env: dict[str, str]) -> subprocess.CompletedProcess:
    """Xvfb 위에서 데모 씬을 돌려 낱장 PNG 와 wav 를 받아 낸다."""
    cmd = [str(GODOT), "--path", str(ROOT), "--resolution", args.res,
           "--write-movie", str(work / "f.png"),
           "--fixed-fps", str(args.fps), "--disable-vsync"]
    if args.frames > 0:
        cmd += ["--quit-after", str(args.frames)]
    cmd += ["res://tests/demo.tscn", "--", "--fps", str(args.fps)]
    print("$ " + " ".join(cmd))
    p = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=7200)
    sys.stdout.write(p.stdout[-4000:])
    return p


def _encode(args: argparse.Namespace, work: Path, pngs: list[Path], wavs: list[Path],
            secs: float) -> None:
    """낱장 PNG(와 wav)를 ffmpeg 으로 한 편의 mp4 로 합친다."""
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    # 낱장 번호가 몇 자리인지 실제 파일에서 읽는다 — Godot 판마다 다를 수 있다.
    digits = len(pngs[0].stem[1:])
    pat = str(work / f"f%0{digits}d.png")
    start = int(pngs[0].stem[1:])

    ff = ["ffmpeg", "-y", "-framerate", str(args.fps),
          "-start_number", str(start), "-i", pat]
    if wavs:
        ff += ["-i", str(wavs[0])]
    ff += ["-c:v", "libx264", "-preset", "slow",
           # ★ `-tune animation` 은 도트 그림에서 값이 크다. 큰 평면과 또렷한 경계를
           #   가정해 디블로킹을 약하게 걸고 B프레임을 더 쓴다 — 같은 화질에서
           #   파일이 3분의 1쯤 작아진다(실측 37.9MB → 27.4MB, 눈으로 구별 안 됨).
           #   30MB 를 넘으면 메신저·제출 시스템이 통째로 거절하는 곳이 많다.
           "-tune", "animation", "-crf", "20",
           # ★ 도트 그림이라 크로마를 반으로 줄이면 1px 테두리가 번진다. 그래도
           #   yuv420p 를 쓰는 까닭은 이것 말고는 폰·브라우저가 통째로 못 여는 판이
           #   많아서다. 대신 crf 를 낮게(20) 잡아 되받는다.
           "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    if wavs:
        ff += ["-c:a", "aac", "-b:a", "192k", "-shortest"]
    ff += [str(out)]
    print("$ " + " ".join(ff[:9]) + " ...")
    subprocess.run(ff, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not args.keep:
        for f in pngs:
            f.unlink()
    size = out.stat().st_size / 1e6
    print(f"\n영상: {out}  ({size:.1f}MB · {secs:.1f}초 · {args.fps}fps · {args.res})")


if __name__ == "__main__":
    raise SystemExit(main())
