#!/usr/bin/env python3
"""Link an Android shared library with the linker command the NDK clang driver would run.

On an aarch64 host whose NDK is the x86_64 release run under qemu-user (the wrappers in
toolchains/llvm/prebuilt/linux-x86_64/bin of this machine's SDK), the driver compiles
fine but cannot exec its linker: the emulated process would have to start a bash wrapper
from inside the x86_64 sysroot. So native/SConstruct asks the driver for the command it
would run (clang++ -###) and runs that linker here, through the wrapper next to the
driver, with the same arguments. On a plain x86_64 host (CI) the driver links directly
and this script is not used.

    android_link.py <clang++> <driver arguments...>
"""
import os
import shlex
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: android_link.py <clang++> <arguments...>", file=sys.stderr)
        return 2
    driver = sys.argv[1]
    arguments = sys.argv[2:]
    probe = subprocess.run([driver, "-###", *arguments], capture_output=True, text=True)
    lines = [line for line in probe.stderr.splitlines() if "ld.lld" in line or '"ld"' in line]
    if probe.returncode != 0 or not lines:
        sys.stderr.write(probe.stderr)
        return probe.returncode or 1
    command = shlex.split(lines[-1])
    wrapper = os.path.join(os.path.dirname(driver), os.path.basename(command[0]))
    if os.path.isfile(wrapper):
        command[0] = wrapper
    return subprocess.run(command).returncode


if __name__ == "__main__":
    sys.exit(main())
