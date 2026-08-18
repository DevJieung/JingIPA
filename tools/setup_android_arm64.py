#!/usr/bin/env python3
"""이 PC(우분투 aarch64)에서 테스트 APK 를 만들 수 있게 도구를 깐다. sudo 가 필요 없다.

구글이 배포하는 Android SDK build-tools / platform-tools 는 **x86_64 리눅스 전용**이라
이 머신에서 안 돈다. 하지만 우분투 저장소에는 같은 도구들이 arm64 네이티브로 들어 있다.
그걸 .deb 로 내려받아 풀기만 하면 (설치가 아니라 풀기라서 sudo 가 필요 없다)
Godot 이 찾는 SDK 모양으로 흉내 낼 수 있다.

★ 이걸로 되는 것: **테스트 APK** (`gradle_build/use_gradle_build=false`).
  Godot 이 미리 구운 `android_debug.apk` 템플릿에 프로젝트를 밀어 넣고
  zipalign → apksigner 만 돌리므로 `aapt2` 가 필요 없다.
★ 이걸로 안 되는 것: **AAB / 커스텀 gradle 빌드**. AGP 가 리소스를 컴파일할 때마다
  `aapt2` 를 부르는데 그건 x86_64 바이너리밖에 없다. 스토어용은 여전히 Mac 에서 만든다.

쓰기:
    python3 tools/setup_android_arm64.py          # 설치 (이미 있으면 건너뜀)
    python3 tools/setup_android_arm64.py --check  # 상태만 확인
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# 우분투 noble(24.04) 기준. zipalign/adb 는 arm64 네이티브, apksigner 는 순수 자바.
PACKAGES = [
    "zipalign", "apksigner", "libapksig-java",
    "android-liblog", "android-libutils", "android-libziparchive",
    "android-libbase", "android-libbacktrace", "android-libcutils",
    "android-libboringssl", "libzopfli1", "adb",
]

# 디렉터리 이름이 곧 build-tools 버전이다. Godot 은 여기서 가장 높은 것을 고른다.
BUILD_TOOLS_VERSION = "35.0.0"

DEFAULT_SDK = Path.home() / "Android/Sdk"
DEFAULT_KEYSTORE = Path.home() / ".local/share/godot/keystores/debug.keystore"

ZIPALIGN_SHIM = """#!/bin/bash
# 우분투(noble) android-sdk-build-tools 의 arm64 zipalign.
# 구글 build-tools 는 x86_64 전용이라 이 머신에서 안 돈다.
here="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$here/.runtime/lib:$LD_LIBRARY_PATH"
exec "$here/.runtime/zipalign.bin" "$@"
"""

APKSIGNER_SHIM = """#!/bin/bash
# apksigner 는 순수 자바라 아키텍처와 무관하다.
here="$(cd "$(dirname "$0")" && pwd)"
exec java -Xmx1024M -cp "$here/lib/apksigner.jar:$here/lib/apksig.jar" \\
    com.android.apksigner.ApkSignerTool "$@"
"""

ADB_SHIM = """#!/bin/bash
# 우분투(noble) 의 arm64 adb. 구글 platform-tools 는 x86_64 전용이다.
here="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$here/.runtime/lib:$LD_LIBRARY_PATH"
exec "$here/.runtime/adb.bin" "$@"
"""


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def find_java_home() -> Path | None:
    """`bin/java` 가 있는 JDK/JRE 디렉터리. Godot 편집기 설정에 그대로 넣으면 된다."""
    java = shutil.which("java")
    if java:
        home = Path(java).resolve().parent.parent
        # openjdk-8 은 .../java-8-openjdk-arm64/jre/bin/java 로 풀린다.
        # 한 단계 위(JDK 루트)도 bin/java 를 갖고 있으면 그쪽이 더 일반적인 값이다.
        if home.name == "jre" and (home.parent / "bin/java").exists():
            home = home.parent
        if (home / "bin/java").exists():
            return home
    jvm = Path("/usr/lib/jvm")
    if jvm.is_dir():
        for d in sorted(jvm.iterdir()):
            if (d / "bin/java").exists():
                return d
    return None


def check(sdk: Path) -> bool:
    bt = sdk / "build-tools" / BUILD_TOOLS_VERSION
    items = {
        "zipalign": bt / "zipalign",
        "apksigner": bt / "apksigner",
        "adb": sdk / "platform-tools/adb",
        "debug.keystore": DEFAULT_KEYSTORE,
        "java": Path(shutil.which("java") or "/nonexistent"),
    }
    ok = True
    for name, path in items.items():
        good = path.exists()
        ok &= good
        print(f"  [{'ok' if good else '없음'}] {name:14s} {path}")
    jh = find_java_home()
    print(f"\n  Godot 편집기 설정에 넣을 값:")
    print(f"    export/android/android_sdk_path = \"{sdk}\"")
    print(f"    export/android/java_sdk_path    = \"{jh or '(java 를 못 찾음)'}\"")
    print(f"    export/android/debug_keystore   = \"{DEFAULT_KEYSTORE}\"")
    print(f"    export/android/debug_keystore_pass = \"android\"")
    return ok


def extract_packages(work: Path) -> Path:
    """.deb 들을 내려받아 한 디렉터리로 푼다 (설치가 아니라서 sudo 가 필요 없다)."""
    debs = work / "debs"
    debs.mkdir(parents=True, exist_ok=True)
    print(f"  .deb {len(PACKAGES)}개 내려받는 중...")
    run(["apt-get", "download", *PACKAGES], cwd=debs)
    root = work / "root"
    root.mkdir(exist_ok=True)
    for deb in sorted(debs.glob("*.deb")):
        run(["dpkg-deb", "-x", str(deb), str(root)])
    return root


def install(sdk: Path) -> None:
    if platform.machine() not in ("aarch64", "arm64"):
        print(f"이 스크립트는 aarch64 전용입니다 (여기는 {platform.machine()}).")
        print("x86_64 라면 구글이 배포하는 정식 Android SDK 를 쓰세요.")
        sys.exit(1)

    with tempfile.TemporaryDirectory(prefix="android-arm64-") as tmp:
        root = extract_packages(Path(tmp))
        libs = root / "usr/lib/aarch64-linux-gnu/android"
        bt = sdk / "build-tools" / BUILD_TOOLS_VERSION
        pt = sdk / "platform-tools"
        (bt / "lib").mkdir(parents=True, exist_ok=True)
        (bt / ".runtime/lib").mkdir(parents=True, exist_ok=True)
        (pt / ".runtime/lib").mkdir(parents=True, exist_ok=True)

        shutil.copy2(root / "usr/lib/android-sdk/build-tools/debian/zipalign",
                     bt / ".runtime/zipalign.bin")
        shutil.copy2(root / "usr/lib/android-sdk/platform-tools/adb",
                     pt / ".runtime/adb.bin")
        for so in list(libs.glob("*.so*")) + list((root / "usr/lib").glob("libzopfli*.so*")):
            shutil.copy2(so, bt / ".runtime/lib" / so.name)
            shutil.copy2(so, pt / ".runtime/lib" / so.name)
        for jar in ("apksigner.jar", "apksig.jar"):
            shutil.copy2(root / "usr/share/java" / jar, bt / "lib" / jar)

        for path, body in ((bt / "zipalign", ZIPALIGN_SHIM),
                           (bt / "apksigner", APKSIGNER_SHIM),
                           (pt / "adb", ADB_SHIM)):
            path.write_text(body)
            path.chmod(0o755)
        print(f"  build-tools/{BUILD_TOOLS_VERSION} · platform-tools 준비됨")

    if not DEFAULT_KEYSTORE.exists():
        DEFAULT_KEYSTORE.parent.mkdir(parents=True, exist_ok=True)
        run(["keytool", "-genkeypair", "-keystore", str(DEFAULT_KEYSTORE),
             "-storepass", "android", "-keypass", "android",
             "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US"])
        print(f"  디버그 키스토어 만듦 (비밀번호 android)")
    else:
        print(f"  디버그 키스토어 이미 있음 — 건드리지 않음")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sdk", type=Path, default=DEFAULT_SDK, help="SDK 를 놓을 곳")
    ap.add_argument("--check", action="store_true", help="설치하지 않고 상태만 본다")
    args = ap.parse_args()

    if args.check:
        print("Android 도구 상태:")
        return 0 if check(args.sdk) else 1

    print(f"aarch64 안드로이드 도구 설치 -> {args.sdk}")
    install(args.sdk)
    print("\n확인:")
    check(args.sdk)
    print("\n이제 테스트 APK 를 만들 수 있습니다:")
    print('  godot --headless --path . --export-debug "Android Test APK" \\')
    print('      "$PWD/build/android/frogwarrior-test.apk"')
    return 0


if __name__ == "__main__":
    sys.exit(main())
