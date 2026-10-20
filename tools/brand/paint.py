#!/usr/bin/env python3
"""Brand paintings (key art, app icon) with a local diffusion model — D4, 2026-10-19.

    python3 tools/brand/paint.py --model krea2 --job keyart --seeds 11,12 --out build/feedback-2026-10-19/D4/gen
    python3 tools/brand/paint.py --model flux2 --job keyart_ref --refs a.png,b.png ...

GPU rules (PLAN.md, gpu_guard.py): one model at a time under the gpujob lock, and **never**
load while another process holds more than 4 GB of GPU memory — this script then stops
before loading anything (it never frees or kills anyone else's job, never calls h3free).
Every image gets a JSON sidecar: model, prompt, seed, steps, size, seconds.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from brand.prompts import JOBS  # noqa: E402

LOCK = os.path.expanduser("~/.cache/gpujob/gpu.lock")
BIG_MIB = 4096
MODELS = {
    "krea2": "krea/Krea-2-Turbo",
    "flux2": "diffusers/FLUX.2-dev-bnb-4bit",
}


def others_on_gpu() -> list[tuple[int, int]]:
    out = subprocess.run(["nvidia-smi", "--query-compute-apps=pid,used_memory",
                          "--format=csv,noheader,nounits"], capture_output=True, text=True).stdout
    me = {os.getpid(), os.getppid()}
    rows = []
    for line in out.splitlines():
        try:
            pid, mib = (int(float(x)) for x in line.split(","))
        except ValueError:
            continue
        if pid not in me and mib >= BIG_MIB:
            rows.append((pid, mib))
    return rows


def guard() -> int:
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("[paint] gpujob lock is held by another job — not loading anything")
    busy = others_on_gpu()
    if busy:
        raise SystemExit("[paint] other processes hold the GPU (%s) — not loading anything"
                         % ", ".join("pid %d %.1fGB" % (p, m / 1024) for p, m in busy))
    return fd


def load(model: str):
    import torch
    if model == "krea2":
        from diffusers import Krea2Pipeline
        pipe = Krea2Pipeline.from_pretrained(MODELS[model], torch_dtype=torch.bfloat16)
    else:
        from diffusers import Flux2Pipeline
        pipe = Flux2Pipeline.from_pretrained(MODELS[model], torch_dtype=torch.bfloat16)
    pipe.to("cuda")
    return pipe


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=sorted(MODELS), default="krea2")
    ap.add_argument("--job", action="append", default=[], help="job name(s) from prompts.py")
    ap.add_argument("--seeds", default="1")
    ap.add_argument("--out", default=os.path.join(ROOT, "build/feedback-2026-10-19/D4/gen"))
    ap.add_argument("--refs", default="", help="comma separated reference images (flux2)")
    ap.add_argument("--steps", type=int, default=0)
    ap.add_argument("--guidance", type=float, default=-1.0)
    ap.add_argument("--size", default="", help="WxH override for every job (exploration at a lower size)")
    ap.add_argument("--tag", default="", help="suffix for file names")
    ap.add_argument("--dry", action="store_true", help="print jobs, load nothing")
    ap.add_argument("--serve", default="", help="queue dir: load once, run *.job.json files as they appear")
    ap.add_argument("--idle", type=float, default=900.0, help="serve: exit after this many idle seconds")
    args = ap.parse_args()
    seeds = [int(s) for s in args.seeds.split(",") if s]
    jobs = [(name, JOBS[name]) for name in args.job]
    os.makedirs(args.out, exist_ok=True)
    if args.dry:
        for name, job in jobs:
            print(name, job["size"], job["prompt"][:120], "...")
        return
    _fd = guard()
    import torch
    from PIL import Image
    t0 = time.time()
    pipe = load(args.model)
    print("[paint] loaded %s in %.0fs" % (args.model, time.time() - t0), flush=True)
    refs = [Image.open(p).convert("RGB") for p in args.refs.split(",") if p]
    if args.serve:
        serve(pipe, args)
        return
    for name, job in jobs:
        w, h = job["size"]
        if args.size:
            w, h = (int(v) for v in args.size.lower().split("x"))
        for seed in seeds:
            path = os.path.join(args.out, "%s_%s_%dx%d_s%d%s.png" % (name, args.model, w, h, seed, args.tag))
            if os.path.exists(path):
                print("[paint] skip", path)
                continue
            t1 = time.time()
            gen = torch.Generator("cuda").manual_seed(seed)
            kw = dict(prompt=job["prompt"], width=w, height=h, generator=gen)
            if args.model == "krea2":
                kw.update(num_inference_steps=args.steps or 8, guidance_scale=max(args.guidance, 0.0))
            else:
                kw.update(num_inference_steps=args.steps or 40,
                          guidance_scale=args.guidance if args.guidance >= 0 else 4.0)
                if refs:
                    kw["image"] = refs
            image = pipe(**kw).images[0]
            image.save(path)
            meta = dict(model=MODELS[args.model], job=name, seed=seed, size=[w, h],
                        steps=kw["num_inference_steps"], guidance=kw["guidance_scale"],
                        refs=[p for p in args.refs.split(",") if p], prompt=job["prompt"],
                        seconds=round(time.time() - t1, 1), date=time.strftime("%Y-%m-%d %H:%M"))
            with open(path[:-4] + ".json", "w") as f:
                json.dump(meta, f, ensure_ascii=False, indent=1)
            print("[paint] %s %.0fs" % (path, time.time() - t1), flush=True)


def run_one(pipe, model: str, prompt: str, w: int, h: int, seed: int, path: str, steps: int,
            guidance: float, job: str, refs: list) -> None:
    import torch
    t1 = time.time()
    gen = torch.Generator("cuda").manual_seed(seed)
    kw = dict(prompt=prompt, width=w, height=h, generator=gen)
    if model == "krea2":
        kw.update(num_inference_steps=steps or 8, guidance_scale=max(guidance, 0.0))
    else:
        kw.update(num_inference_steps=steps or 40, guidance_scale=guidance if guidance >= 0 else 4.0)
        if refs:
            kw["image"] = refs
    image = pipe(**kw).images[0]
    image.save(path)
    meta = dict(model=MODELS[model], job=job, seed=seed, size=[w, h], steps=kw["num_inference_steps"],
                guidance=kw["guidance_scale"], prompt=prompt, seconds=round(time.time() - t1, 1),
                date=time.strftime("%Y-%m-%d %H:%M"))
    with open(path[:-4] + ".json", "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("[paint] %s %.0fs" % (path, time.time() - t1), flush=True)


def serve(pipe, args) -> None:
    """Queue mode. A job file is JSON: {job | prompt, size [w,h], seeds [..], tag, steps}."""
    import glob
    os.makedirs(args.serve, exist_ok=True)
    last = time.time()
    print("[paint] serving %s (idle exit %.0fs)" % (args.serve, args.idle), flush=True)
    while time.time() - last < args.idle:
        if os.path.exists(os.path.join(args.serve, "quit")):
            break
        files = sorted(glob.glob(os.path.join(args.serve, "*.job.json")))
        if not files:
            time.sleep(2)
            continue
        f = files[0]
        try:
            spec = json.load(open(f))
        except Exception as e:  # noqa: BLE001
            print("[paint] bad job %s: %s" % (f, e), flush=True)
            os.rename(f, f + ".bad")
            continue
        os.rename(f, f[:-9] + ".running")
        name = spec.get("job", "custom")
        prompt = spec.get("prompt") or JOBS[name]["prompt"]
        w, h = spec.get("size") or JOBS[name]["size"]
        for seed in spec.get("seeds", [1]):
            path = os.path.join(args.out, "%s_%s_%dx%d_s%d%s.png" % (name, args.model, w, h, seed, spec.get("tag", "")))
            if os.path.exists(path):
                continue
            try:
                run_one(pipe, args.model, prompt, w, h, seed, path, int(spec.get("steps", 0)),
                        float(spec.get("guidance", -1.0)), name, [])
            except Exception as e:  # noqa: BLE001
                print("[paint] failed %s: %s" % (path, e), flush=True)
        os.rename(f[:-9] + ".running", f[:-9] + ".done")
        last = time.time()
    print("[paint] serve exit", flush=True)


if __name__ == "__main__":
    main()
