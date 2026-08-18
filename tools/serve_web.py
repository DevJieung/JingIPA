#!/usr/bin/env python3
"""웹 빌드를 브라우저로 열어볼 수 있게 띄우는 개발용 서버.

이 개발 머신은 화면이 없는 서버(SSH 전용)라 Godot 창을 띄울 수 없다.
그래서 웹으로 빌드해 다른 기기의 브라우저로 접속해 플레이한다.

★ Godot 웹 빌드는 '보안 컨텍스트'를 요구한다 (오디오 워크릿 때문).
  보안 컨텍스트로 인정되는 것은 딱 두 가지다:
    1) http://localhost 또는 http://127.0.0.1   -> SSH 포트포워딩으로 만들면 된다
    2) https://...                              -> 인증서가 필요하다
  그래서 이 스크립트는 두 모드를 지원한다.

사용법:
    # (1) 내 PC 브라우저로만 볼 때 — 경고 없음, 가장 간단
    python3 tools/serve_web.py --host 127.0.0.1 --port 8060
    #   그리고 내 PC 에서:  ssh -L 8060:localhost:8060 dgxmaruta@spark-006f
    #   브라우저:            http://localhost:8060/

    # (2) 폰 등 다른 기기에서도 볼 때 — 자체 서명 HTTPS (첫 접속 시 경고 1회 통과)
    python3 tools/serve_web.py --https
    #   브라우저:            https://<tailscale-ip>:8443/

먼저 웹 빌드를 만들어야 한다:
    mkdir -p build/web
    godot --headless --path . --export-release "Web" "$PWD/build/web/index.html"
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import socket
import ssl
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(ROOT, "build", "web")
CERT_DIR = os.path.join(ROOT, ".certs")
CERT = os.path.join(CERT_DIR, "dev.crt")
KEY = os.path.join(CERT_DIR, "dev.key")


class Handler(http.server.SimpleHTTPRequestHandler):
    # .wasm 을 application/wasm 으로 줘야 브라우저가 스트리밍 컴파일을 쓴다.
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self):
        # 지금 빌드는 nothreads 라 없어도 되지만, 나중에 스레드를 켜도
        # 그대로 동작하도록 미리 넣어 둔다.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        first = args[0] if args else ""
        if ".wasm" in str(first):
            return
        super().log_message(fmt, *args)


def tailscale_ip() -> str | None:
    """공인 인터넷이 아니라 개인 VPN(tailscale) 주소를 우선 쓴다."""
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr", "show", "tailscale0"],
                             capture_output=True, text=True, timeout=5).stdout
        for tok in out.split():
            if tok.count(".") == 3 and "/" in tok:
                return tok.split("/")[0]
    except Exception:
        pass
    return None


def tailscale_dns() -> str | None:
    try:
        out = subprocess.run(["tailscale", "status", "--json"],
                             capture_output=True, text=True, timeout=8).stdout
        import json
        name = json.loads(out).get("Self", {}).get("DNSName", "")
        return name.rstrip(".") or None
    except Exception:
        return None


def ensure_cert(ip: str | None, dns: str | None) -> None:
    """자체 서명 인증서를 만든다. 접속할 수 있는 모든 이름을 SAN 에 넣는다."""
    if os.path.isfile(CERT) and os.path.isfile(KEY):
        return
    os.makedirs(CERT_DIR, exist_ok=True)
    sans = ["DNS:localhost", "IP:127.0.0.1"]
    if dns:
        sans.append(f"DNS:{dns}")
    if ip:
        sans.append(f"IP:{ip}")
    subj = f"/CN={dns or ip or 'localhost'}"
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", KEY, "-out", CERT, "-days", "825",
        "-subj", subj, "-addext", "subjectAltName=" + ",".join(sans),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("인증서 생성 실패:\n" + r.stderr, file=sys.stderr)
        raise SystemExit(1)
    print(f"자체 서명 인증서를 만들었습니다: {os.path.relpath(CERT, ROOT)}")
    print(f"  대상: {', '.join(sans)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=None)
    ap.add_argument("--host", default=None,
                    help="기본값: tailscale 주소 (없으면 127.0.0.1)")
    ap.add_argument("--https", action="store_true",
                    help="자체 서명 HTTPS 로 띄운다 (폰 등 원격 기기용)")
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(WEB_DIR, "index.html")):
        print(f"웹 빌드가 없습니다: {WEB_DIR}/index.html\n"
              f"먼저 실행하세요:\n"
              f'  mkdir -p build/web && godot --headless --path . '
              f'--export-release "Web" "$PWD/build/web/index.html"', file=sys.stderr)
        return 1

    ts_ip = tailscale_ip()
    ts_dns = tailscale_dns()
    host = args.host or ts_ip or "127.0.0.1"
    port = args.port or (8443 if args.https else 8060)
    scheme = "https" if args.https else "http"

    handler = functools.partial(Handler, directory=WEB_DIR)
    httpd = http.server.ThreadingHTTPServer((host, port), handler)

    if args.https:
        ensure_cert(ts_ip, ts_dns)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(CERT, KEY)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

    print("\n개구리 용사 웹 빌드 서빙 중")
    print(f"  {scheme}://{host}:{port}/")
    if args.https and ts_dns:
        print(f"  {scheme}://{ts_dns}:{port}/")
        print("  ※ 자체 서명이라 첫 접속 시 '안전하지 않음' 경고가 뜹니다.")
        print("     [고급] -> [계속 진행] 을 한 번 누르면 이후로는 안 뜹니다.")
    if not args.https and host in ("127.0.0.1", "localhost"):
        user = os.environ.get("USER", "user")
        print(f"  내 PC 에서 터널 열기:  ssh -L {port}:localhost:{port} "
              f"{user}@{socket.gethostname()}")
        print(f"  그다음 브라우저:       http://localhost:{port}/")
    elif not args.https:
        print("  ⚠ Godot 웹은 보안 컨텍스트가 필요합니다. 이 주소(평문 HTTP + IP)로는")
        print("    'Secure Context' 오류가 납니다. --https 를 쓰거나 SSH 터널을 쓰세요.")
    print("  중지: Ctrl+C\n")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n중지했습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
