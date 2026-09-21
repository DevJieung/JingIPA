#!/usr/bin/env python3
"""Collect All-in Defense's Android ad logs and summarize SDK load failures."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.devjieung.pokerdefense"
ERROR_MARKER = "AdMob load failed: "


def load_errors(log: str) -> list[dict]:
    errors = []
    for line in log.splitlines():
        if ERROR_MARKER not in line:
            continue
        payload = line.split(ERROR_MARKER, 1)[1]
        try:
            error = json.loads(payload)
        except json.JSONDecodeError:
            # APKs before structured diagnostics used this format.
            match = re.fullmatch(r"kind=(\S+) code=(-?\d+) domain=(\S+) message=(.*)", payload)
            if not match:
                continue
            error = dict(zip(("kind", "code", "domain", "message"), match.groups()))
            error["code"] = int(error["code"])
        if isinstance(error, dict):
            errors.append(error)
    return errors


def explain(error: dict) -> str:
    message = str(error.get("message", ""))
    # Some SDK/plugin responses omit domain; explicit server explanations are
    # still useful. Do not infer Google's numeric-code meaning from an empty one.
    if "Account not approved yet." in message:
        return "AdMob 계정 미승인: 계정 검토가 아직 끝나지 않았습니다. AdMob 계정 상태와 안내 이메일을 확인하세요."
    if "App not approved yet." in message:
        return "AdMob 앱 미승인: 해당 앱의 준비 상태와 검토 안내를 확인하세요."
    if re.search(r"\bresponseCode=403\b", message):
        return "HTTP 403: 서버가 요청을 거절했습니다. 이 기록만으로 거절 사유를 확정할 수 없습니다. 다른 SDK 원문 및 AdMob 상태를 확인하세요."
    if not error.get("domain"):
        return "SDK가 domain을 전달하지 않았습니다. 숫자만으로 분류하지 말고 원문 메시지를 확인하세요."
    if error.get("domain") != "com.google.android.gms.ads":
        return "Google 기본 오류 코드가 아닙니다. domain과 원문 메시지를 확인하세요."
    return {
        0: "SDK 내부 오류: 원문 메시지와 cause를 확인하세요.",
        1: "잘못된 광고 요청: 광고 단위 ID와 보상형 광고 형식을 확인하세요.",
        2: "네트워크 오류: Wi-Fi/모바일 데이터 전환, VPN·광고 차단·사설 DNS 설정을 확인하세요.",
        3: "요청은 처리됐지만 광고가 반환되지 않았습니다. 원문 메시지와 AdMob 계정·앱 준비 상태를 확인하세요.",
        8: "앱 ID 누락: APK의 AdMob APPLICATION_ID 설정을 확인하세요.",
        9: "중개 광고망이 광고를 반환하지 않았습니다. cause와 adapter_errors를 확인하세요.",
    }.get(error.get("code"), "추가 SDK 오류입니다. 원문 메시지를 확인하세요.")


def summarize(log: str) -> str:
    errors = load_errors(log)
    lines = ["올인 디펜스 광고 진단", "수집 구간의 기록입니다. 과거 실패 뒤 성공한 기록도 함께 포함될 수 있습니다."]
    events = [line for line in log.splitlines() if "AdMob " in line or "Rewarded ad show failed:" in line]
    if events:
        lines.extend(["", "최근 광고 이벤트 (최대 15줄):", *events[-15:]])
    else:
        lines.append("광고 서비스 로그가 없습니다. 게임을 열고 광고 버튼을 누른 뒤 다시 수집하세요.")
    for error in errors[-5:]:
        lines.extend(["", f"로드 실패: 종류={error.get('kind')} code={error.get('code')} domain={error.get('domain')}",
                      f"원문: {error.get('message', '')}", explain(error)])
        for key in ("cause", "response_id", "adapter", "adapter_errors"):
            if error.get(key):
                lines.append(f"{key}: {json.dumps(error[key], ensure_ascii=False)}")
    if events and not errors:
        lines.append("\n해석 가능한 로드 실패 코드가 없습니다. 위 이벤트와 원본 로그를 확인하세요.")
    lines.extend(["", "오류 설명: https://developers.google.com/admob/android/ad-load-errors",
                  "계정/앱 승인 안내: https://support.google.com/admob/answer/9905175?hl=ko",
                  "테스트 광고 설정: https://developers.google.com/admob/android/test-ads"])
    return "\n".join(lines) + "\n"


def adb_path(explicit: str | None) -> str:
    if explicit:
        return explicit
    executable = shutil.which("adb")
    if executable:
        return executable
    roots = [os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME"),
             str(Path.home() / "Android/SdkFlutter"), str(Path.home() / "Android/Sdk")]
    for root in roots:
        if root:
            for name in ("adb", "adb.exe"):
                candidate = Path(root) / "platform-tools" / name
                if candidate.is_file():
                    return str(candidate)
    raise RuntimeError("adb를 찾지 못했습니다. Android SDK Platform-Tools를 설치하거나 --adb 경로를 지정하세요.")


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "ADB 명령 실패")
    return result.stdout


def collect(args: argparse.Namespace) -> str:
    adb = adb_path(args.adb)
    devices = {}
    for line in run([adb, "devices"]).splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] in ("device", "unauthorized", "offline"):
            devices[fields[0]] = fields[1]
    serial = args.serial
    if not serial:
        if not devices:
            raise RuntimeError("연결된 기기가 없습니다. 폰의 개발자 옵션 → USB 디버깅을 켜고 USB로 연결한 뒤 허용을 누르세요.")
        if len(devices) != 1:
            raise RuntimeError("기기가 여러 대입니다. adb devices로 확인한 기기를 --serial로 지정하세요.")
        serial = next(iter(devices))
    if devices.get(serial) != "device":
        raise RuntimeError("기기가 연결/허용 상태가 아닙니다. 폰의 USB 디버깅 허용 창과 케이블을 확인하세요.")
    command = [adb, "-s", serial]
    try:
        pids = run([*command, "shell", "pidof", PACKAGE]).split()
    except RuntimeError as error:
        raise RuntimeError("올인 디펜스를 폰에서 실행한 뒤 다시 수집하세요.") from error
    if len(pids) != 1 or not pids[0].isdigit():
        raise RuntimeError("올인 디펜스를 폰에서 실행한 뒤 다시 수집하세요.")
    # Read only this game's process and relevant tags. Preserve device log buffers.
    logcat = [*command, "logcat", "--pid=" + pids[0], "-v", "threadtime",
              "godot:V", "Ads:V", "AndroidRuntime:E", "*:S"]
    history = run([*logcat, "-d"])
    if args.seconds == 0:
        return history
    print(f"{args.seconds}초 동안 수집합니다. 게임을 종료하지 말고 광고 버튼을 누르세요. Ctrl+C로 일찍 마칠 수 있습니다.", flush=True)
    process = subprocess.Popen([*logcat, "-T", "1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace")
    stopped = False
    try:
        live, stderr = process.communicate(timeout=args.seconds)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        stopped = True
        process.terminate()
        try:
            live, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            live, stderr = process.communicate()
    if process.returncode and not stopped:
        raise RuntimeError(stderr.strip() or "로그 수집 연결이 끊겼습니다.")
    return history + live


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", help="adb 실행 파일 경로")
    parser.add_argument("--serial", help="대상 기기 (여러 대일 때)")
    parser.add_argument("--seconds", type=int, default=0, help="추가 실시간 수집 초. 기본값은 이미 남은 로그만 읽기")
    parser.add_argument("--log", type=Path, help="기기 연결 없이 기존 로그 파일 해석")
    parser.add_argument("--out", type=Path, default=ROOT / "build/admob-diagnostics")
    args = parser.parse_args()
    if not 0 <= args.seconds <= 600:
        parser.error("--seconds는 0~600 사이여야 합니다.")
    try:
        log = args.log.read_text(encoding="utf-8", errors="replace") if args.log else collect(args)
        report = summarize(log)
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "admob.log").write_text(log, encoding="utf-8")
        (args.out / "summary.txt").write_text(report, encoding="utf-8")
        print(report)
        print("저장:", args.out)
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print("진단 준비:", error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
