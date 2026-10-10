#!/usr/bin/env python3
"""Current Limne entry point: accepted shape, game materials and motion rig.

bl -b --factory-startup --python tools/3d/build_limne.py

The rejected primitive prototype is preserved under
build/limne-pro/rejected-v1/build_limne.py. This entry point cannot export it.
"""
import runpy
import sys
from pathlib import Path

if '--input' in sys.argv:
    raise RuntimeError('The current character is built from its accepted .blend by style_animate_limne.py. Raw reconstruction finishing is a separate legacy experiment.')
runpy.run_path(str(Path(__file__).with_name('style_animate_limne.py')),run_name='__main__')
