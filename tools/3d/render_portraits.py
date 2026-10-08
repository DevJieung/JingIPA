#!/usr/bin/env python3
"""Render all 50 live 3D hero rigs at ten grades and all awakened guardians."""
import argparse, subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT,GODOT,ensure_xvfb,xvfb
p=argparse.ArgumentParser();p.add_argument('--ids',default='');args=p.parse_args()
ensure_xvfb()
with xvfb(98,'800x600') as env:
 env['STELLARDEFENSE_NO_SAVE']='1'
 result=subprocess.run([str(GODOT),'--path',str(ROOT),'res://tests/3d/render_portraits.tscn','--','--ids='+args.ids],env=env,capture_output=True,text=True,timeout=1200)
 print(result.stdout);print(result.stderr,file=sys.stderr)
 if result.returncode or 'SCRIPT ERROR' in result.stderr or 'ERROR:' in result.stderr:sys.exit(1)
