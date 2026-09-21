#!/usr/bin/env python3
"""GPU 를 물 모델을 올리기 전에 부르는 문지기 — Krea2 와 MiniMax H3 가 **같은 순간에 못 뜬다.**

사용자가 정한 것(2026-09-07): 「절대로 krea 와 minimax 가 동시에 돌지 않게」.
GB10 은 통합 메모리 119GB 를 CPU 와 GPU 가 나눠 쓴다. H3 서버(`~/pjt/h3/serve.sh` · 8199)는
켜 두면 47~90GB 를 물고, Krea2 는 20~30GB, Wan 은 두 전문가에 50GB 가 넘는다. 둘이 겹치면
전역 OOM 이고 그것이 2026-09-01 의 사고다(tmux 세션이 통째로 날아갔다).

부르는 자리는 **모델을 올리기 직전** 한 곳씩이다:
    Krea2  gen_art · reroll_art · style_test · anim/gen_master · sprite/make_ref  → claim("krea2")
    Wan    sprite/wan_i2v.serve()                                                → claim("wan")
    H3     sprite/h3_i2v (붙기 전)                                                → claim("h3")
  `~/pjt/h3/generate.py` 는 이 파일을 안 부르고 같은 검사를 제 안에 갖고 있다(다른 저장소다).

하는 일 셋:
  1. **gpujob 의 락을 잡는다**(`~/.cache/gpujob/gpu.lock` · flock). gpujob 안에서 돌고 있으면
     이미 잡혀 있으므로 건너뛴다(cgroup 이름에 `gpujob-` 이 있다). 락은 프로세스가 끝날 때 풀린다 —
     모델이 상주하는 동안 다른 모델이 못 올라온다는 뜻이다.
  2. Krea2·Wan 을 올리기 전에는 **H3 서버의 메모리를 비운다**(`POST /free` · unload_models).
     서버는 살려 둔다 — 다음 H3 호출이 30~110초 더 걸릴 뿐이다. 비워질 때까지 **기다렸다가**
     GPU 메모리와 RSS 로 확인한다. H3 가 한창 생성 중이면 그것이 끝난 뒤에 비워진다.
  3. 그러고도 **남이 GPU 를 4GB 넘게 물고 있으면 멈춘다** — pid 와 이름을 찍는다. H3 를 부를
     때는 반대로 Krea2·Wan(그리고 perfectpixel 의 krea2_server)이 물고 있으면 멈춘다.
     ★ 여기서 멈추는 것이 이 파일의 존재 이유다. 경고만 하고 지나가면 사고를 못 막는다.

    python3 tools/gpu_guard.py status          # 지금 누가 무엇을 물고 있나
    python3 tools/gpu_guard.py h3free          # H3 서버 메모리만 비운다 (서버는 살려 둔다)
    python3 tools/gpu_guard.py claim krea2     # 검사만 해 본다 (락은 끝나면 풀린다)
"""

from __future__ import annotations

import fcntl
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

H3 = os.environ.get("POCKER_H3", "127.0.0.1:8199")
LOCK = os.path.join(os.environ.get("GPUJOB_DIR", os.path.expanduser("~/.cache/gpujob")), "gpu.lock")
#: 이보다 크게 물고 있으면 「모델이 올라와 있다」로 본다 (H3 서버가 빈 채로 3GB 남짓 문다)
BIG_MIB = 4096
#: H3 서버의 RSS 가 이 밑으로 내려와야 「비웠다」다. 실측은 아래 h3_release 머리말.
H3_IDLE_RSS_GB = 16.0
#: /free 뒤에 비워지길 기다리는 한도. 생성 중이면 그 클립이 끝나야 비워지므로 넉넉히 둔다.
FREE_WAIT_SEC = 900

_LOCK_FD: int | None = None


# --------------------------------------------------------------------------
# 살피기
# --------------------------------------------------------------------------
def inside_gpujob() -> bool:
    """gpujob 이 만든 유닛(scope/service) 안인가 — 그러면 락은 이미 잡혀 있다."""
    try:
        return "gpujob-" in open("/proc/self/cgroup").read()
    except OSError:
        return False


def gpu_apps() -> list[tuple[int, int, str]]:
    """GPU 를 물고 있는 프로세스 [(pid, MiB, 이름)]. nvidia-smi 가 없으면 빈 목록."""
    try:
        out = subprocess.run(["nvidia-smi", "--query-compute-apps=pid,used_memory,process_name",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True,
                             timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        print("[gpu] nvidia-smi 를 못 불렀다 — GPU 를 누가 쓰는지 모른 채 간다", file=sys.stderr)
        return []
    apps = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 3:
            continue
        try:
            apps.append((int(parts[0]), int(float(parts[1])), parts[2]))
        except ValueError:
            continue
    return apps


def rss_gb(pid: int) -> float:
    try:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1048576.0
    except OSError:
        pass
    return 0.0


def h3_pid() -> int | None:
    """H3 서버(ComfyUI main.py --port <8199>)의 pid. 없으면 None."""
    port = H3.rsplit(":", 1)[-1]
    try:
        out = subprocess.run(["pgrep", "-f", f"main.py .*--port {port}"], capture_output=True,
                             text=True, timeout=10).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return None
    pids = [int(p) for p in out if p.isdigit() and int(p) != os.getpid()]
    return pids[0] if pids else None


def h3_alive() -> bool:
    try:
        with urllib.request.urlopen(f"http://{H3}/system_stats", timeout=10):
            return True
    except Exception:
        return False


def h3_busy() -> int:
    """H3 서버의 큐 — 지금 돌고 있는 것 + 기다리는 것의 수."""
    try:
        with urllib.request.urlopen(f"http://{H3}/queue", timeout=10) as r:
            q = json.loads(r.read())
        return len(q.get("queue_running", [])) + len(q.get("queue_pending", []))
    except Exception:
        return 0


def others(exclude: set[int] = frozenset()) -> list[tuple[int, int, str]]:
    """나와 `exclude` 를 뺀, GPU 를 BIG_MIB 넘게 물고 있는 프로세스."""
    me = {os.getpid(), os.getppid()}
    return [(pid, mib, name) for pid, mib, name in gpu_apps()
            if mib >= BIG_MIB and pid not in me and pid not in exclude]


# --------------------------------------------------------------------------
# 하기
# --------------------------------------------------------------------------
def lock(model: str) -> None:
    """gpujob 의 락을 잡는다. 남이 잡고 있으면 기다린다. 프로세스가 끝나면 풀린다."""
    global _LOCK_FD
    if _LOCK_FD is not None or inside_gpujob():
        return
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(f"[gpu] GPU 락을 다른 작업이 잡고 있다 — 끝나길 기다린다 ({LOCK})", flush=True)
        fcntl.flock(fd, fcntl.LOCK_EX)
    _LOCK_FD = fd
    print(f"[gpu] 락 잡음 ({model}) — gpujob 밖에서 돌고 있다. 무거운 작업은 `gpujob run` 이 안전하다",
          flush=True)


def h3_release() -> bool:
    """H3 서버가 문 모델을 내려놓게 하고, 실제로 내려갈 때까지 기다린다.

    실측(2026-09-07): 아이들 상주 GPU 40.4GB · RSS 46.6GB → `/free` 뒤 **3초** 만에 GPU 0.35GB ·
    RSS 5.1GB. 시스템 가용 메모리 27GB → 108GB. 서버는 살아 있고, 다음 생성이 모델을 다시 읽는다.
    """
    pid = h3_pid()
    if pid is None and not h3_alive():
        return True                                   # 서버가 없다 — 비울 것도 없다
    if pid is not None:
        mib = next((m for p, m, _n in gpu_apps() if p == pid), 0)
        if mib < BIG_MIB and rss_gb(pid) < H3_IDLE_RSS_GB:
            return True                               # 이미 비어 있다
    n = h3_busy()
    if n:
        print(f"[gpu] H3 가 지금 {n}개를 생성 중이다 — 끝나면 비운다 (최대 {FREE_WAIT_SEC}초)", flush=True)
    body = json.dumps({"unload_models": True, "free_memory": True}).encode()
    req = urllib.request.Request(f"http://{H3}/free", data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:                            # noqa: BLE001
        print(f"[gpu] H3 /free 실패: {e}", file=sys.stderr)
        return False
    t0 = time.time()
    last = -1
    while time.time() - t0 < FREE_WAIT_SEC:
        if pid is None:
            return True
        mib = next((m for p, m, _n in gpu_apps() if p == pid), 0)
        rss = rss_gb(pid)
        if mib < BIG_MIB and rss < H3_IDLE_RSS_GB:
            print(f"[gpu] H3 비움 — GPU {mib}MiB · RSS {rss:.1f}GB ({time.time() - t0:.0f}초)", flush=True)
            return True
        if int(time.time() - t0) // 15 != last:
            last = int(time.time() - t0) // 15
            print(f"[gpu] H3 비우는 중 … GPU {mib}MiB · RSS {rss:.1f}GB", flush=True)
            if h3_busy() and time.time() - t0 > 20:
                # 생성 중이면 플래그가 그 뒤에 먹는다 — 한 번 더 걸어 둔다
                try:
                    urllib.request.urlopen(req, timeout=30).read()
                except Exception:
                    pass
        time.sleep(3)
    return False


def claim(model: str) -> None:
    """모델을 올리기 직전에 부른다. 겹칠 것이 있으면 **멈춘다**(SystemExit)."""
    model = model.lower()
    lock(model)
    if model in ("krea2", "wan"):
        if not h3_release():
            pid = h3_pid()
            raise SystemExit(
                f"[gpu] H3 서버(pid {pid})가 메모리를 안 놓는다 — {model} 을 올리면 터진다.\n"
                f"       gpujob gpu 로 보고, 정 안 되면 그 서버를 끄고 다시:  kill {pid}")
        bad = others()
    elif model == "h3":
        bad = others(exclude={p for p in (h3_pid(),) if p})
    else:
        raise ValueError(f"모르는 모델: {model} (krea2 · wan · h3)")
    if bad:
        lines = "\n".join(f"       pid={p:<8} {m / 1024:5.1f}GB  {n}" for p, m, n in bad)
        raise SystemExit(
            f"[gpu] {model} 을 올릴 수 없다 — 다른 모델이 GPU 를 물고 있다:\n{lines}\n"
            "       그 작업이 끝나길 기다리거나 끝난 것이면 kill 해라 (gpujob gpu). "
            "Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 (CLAUDE.md · gpu_guard 머리말)")
    print(f"[gpu] {model} 올려도 된다 — GPU 에 다른 모델 없음", flush=True)


def status() -> None:
    pid = h3_pid()
    print(f"H3 서버: {'있음 pid ' + str(pid) if pid else '없음'} · 응답 {'예' if h3_alive() else '아니오'}"
          f" · 큐 {h3_busy()} · 락 {'gpujob 안' if inside_gpujob() else LOCK}")
    apps = gpu_apps()
    if not apps:
        print("GPU 를 문 프로세스 없음")
    for p, m, n in apps:
        tag = " ← H3 서버" if p == pid else ""
        print(f"  pid={p:<8} GPU {m / 1024:5.1f}GB  RSS {rss_gb(p):5.1f}GB  {n}{tag}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] == "status":
        status()
    elif a[0] == "h3free":
        raise SystemExit(0 if h3_release() else 1)
    elif a[0] == "claim" and len(a) > 1:
        claim(a[1])
    else:
        raise SystemExit(__doc__)
