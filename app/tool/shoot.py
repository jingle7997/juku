#!/usr/bin/env python3
"""用无头 Chrome 给 web 版逐页截图，做界面回归。

纯标准库实现（自己写了最小 WebSocket 客户端 + CDP 调用），不依赖 puppeteer。
通过 Emulation.setDeviceMetricsOverride 精确控制视口，避免 `--screenshot`
那种窗口尺寸不可控、右边缘被裁的问题。

前置：

    flutter build web          # 先构建，产物在 build/web

用法：

    python app/tool/shoot.py                    # 默认截 connect / home / profile
    python app/tool/shoot.py --only home
    python app/tool/shoot.py --mock             # 顺便拉起 tool/mock_server.py (8999)

产物写到 app/preview/<name>.png，尺寸 390x844 @3x。
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
WEB_DIR = APP_DIR / "build" / "web"
PREVIEW_DIR = APP_DIR / "preview"

VIEWPORT_W, VIEWPORT_H, SCALE = 390, 844, 3

CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
]


# ---------------------------------------------------------------- WebSocket

class WS:
    """够用的最小 WebSocket 客户端：只处理文本帧、分片、ping。"""

    def __init__(self, url: str):
        assert url.startswith("ws://")
        rest = url[5:]
        host_port, _, path = rest.partition("/")
        host, _, port = host_port.partition(":")
        self.sock = socket.create_connection((host, int(port or 80)), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("WebSocket 握手连接被关闭")
            buf += chunk
        head, _, tail = buf.partition(b"\r\n\r\n")
        if b"101" not in head.split(b"\r\n")[0]:
            raise RuntimeError(f"WebSocket 握手失败: {head[:200]!r}")
        self._buf = tail
        self._frag_op = 0
        self._frag = b""

    def _recv_exact(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("WebSocket 连接已关闭")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def send(self, text: str) -> None:
        payload = text.encode()
        n = len(payload)
        header = bytearray([0x81])
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def recv(self) -> str:
        while True:
            b0, b1 = self._recv_exact(2)
            fin = b0 & 0x80
            opcode = b0 & 0x0F
            masked = b1 & 0x80
            length = b1 & 0x7F
            if length == 126:
                (length,) = struct.unpack(">H", self._recv_exact(2))
            elif length == 127:
                (length,) = struct.unpack(">Q", self._recv_exact(8))
            mask = self._recv_exact(4) if masked else b""
            data = self._recv_exact(length) if length else b""
            if masked:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))

            if opcode == 0x9:  # ping
                self.sock.sendall(bytes([0x8A, 0x80]) + os.urandom(4))
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode == 0x8:  # close
                raise RuntimeError("WebSocket 被对端关闭")
            if opcode in (0x1, 0x2):
                self._frag_op = opcode
                self._frag = data
            elif opcode == 0x0:
                self._frag += data
            if fin:
                text = self._frag.decode("utf-8", "replace")
                self._frag = b""
                return text


class CDP:
    def __init__(self, ws_url: str):
        self.ws = WS(ws_url)
        self._id = 0
        self.session_id: str | None = None

    def call(self, method: str, params: dict | None = None, timeout: float = 60) -> dict:
        self._id += 1
        mid = self._id
        msg = {"id": mid, "method": method, "params": params or {}}
        if self.session_id:
            msg["sessionId"] = self.session_id
        self.ws.send(json.dumps(msg))
        deadline = time.time() + timeout
        while time.time() < deadline:
            raw = self.ws.recv()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if data.get("id") == mid:
                if "error" in data:
                    raise RuntimeError(f"{method} 失败: {data['error']}")
                if "sessionId" in data:
                    self.session_id = data["sessionId"]
                return data.get("result", {})
            # 其余是事件，忽略
        raise TimeoutError(f"{method} 超时")


# ---------------------------------------------------------------- 服务与浏览器

def serve_web(port: int) -> ThreadingHTTPServer:
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(WEB_DIR), **kw)

        def log_message(self, *a):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def find_chrome() -> str:
    for p in CHROME_CANDIDATES:
        if Path(p).is_file():
            return p
    raise RuntimeError("找不到 Chrome / Edge")


def launch_chrome(debug_port: int, user_dir: Path) -> subprocess.Popen:
    args = [
        find_chrome(),
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--force-device-scale-factor=1",
        f"--remote-debugging-port={debug_port}",
        f"--user-data-dir={user_dir}",
        "about:blank",
    ]
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def wait_devtools(port: int, timeout: float = 25) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version", timeout=2) as r:
                return json.load(r)["webSocketDebuggerUrl"]
        except Exception:
            time.sleep(0.3)
    raise TimeoutError("DevTools 端口没起来")


# ---------------------------------------------------------------- 截图

SHOTS = {
    "connect": {"seed": {}, "clicks": []},
    "home": {"seed": {"serverUrl": "http://127.0.0.1:8999"}, "clicks": []},
    "discover": {"seed": {"serverUrl": "http://127.0.0.1:8999"}, "clicks": [(146, 806)]},
    "following": {"seed": {"serverUrl": "http://127.0.0.1:8999"}, "clicks": [(243, 806)]},
    # 追剧页的「记录」分段：先进追剧 tab，再点右半段
    "history": {"seed": {"serverUrl": "http://127.0.0.1:8999"}, "clicks": [(243, 806), (284, 78)]},
    "profile": {"seed": {"serverUrl": "http://127.0.0.1:8999"}, "clicks": [(341, 806)]},
}


def shoot(cdp: CDP, base_url: str, name: str, cfg: dict, settle: float) -> Path:
    cdp.call("Page.navigate", {"url": base_url})
    time.sleep(2.0)
    # 用 localStorage 预置偏好，等价于「上次已经连过服务端」。
    # 注意：shared_preferences_web 存值走 json.encode，字符串要带引号
    # （存 "http://x" 而不是 http://x），否则读回来 json.decode 失败返回 null。
    if cfg["seed"]:
        stmts = [
            f"localStorage.setItem({json.dumps('flutter.' + k)}, JSON.stringify({json.dumps(v)}))"
            for k, v in cfg["seed"].items()
        ]
        cdp.call("Runtime.evaluate", {"expression": ";".join(stmts)})
        cdp.call("Page.reload")
        time.sleep(settle)
    else:
        cdp.call("Runtime.evaluate", {"expression": "localStorage.clear()"})
        cdp.call("Page.reload")
        time.sleep(settle)

    for x, y in cfg["clicks"]:
        for kind in ("mousePressed", "mouseReleased"):
            cdp.call(
                "Input.dispatchMouseEvent",
                {"type": kind, "x": x, "y": y, "button": "left", "clickCount": 1},
            )
        time.sleep(0.9)
    time.sleep(1.2)

    res = cdp.call("Page.captureScreenshot", {"format": "png", "captureBeyondViewport": False})
    out = PREVIEW_DIR / f"{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(res["data"]))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="只截某一页，逗号分隔")
    ap.add_argument("--port", type=int, default=8123)
    ap.add_argument("--debug-port", type=int, default=9333)
    ap.add_argument("--settle", type=float, default=7.0, help="Flutter web 启动等待秒数")
    args = ap.parse_args()

    if not (WEB_DIR / "index.html").is_file():
        print(f"没有构建产物，先执行 flutter build web（缺少 {WEB_DIR}）")
        return 1

    names = [n.strip() for n in args.only.split(",") if n.strip()] or list(SHOTS)
    unknown = [n for n in names if n not in SHOTS]
    if unknown:
        print(f"未知页面: {unknown}，可选: {list(SHOTS)}")
        return 1

    serve_web(args.port)
    user_dir = Path(tempfile.mkdtemp(prefix="juku-shot-"))
    proc = launch_chrome(args.debug_port, user_dir)
    try:
        cdp = CDP(wait_devtools(args.debug_port))
        # 新建一个空白页并 attach，后续命令都带 sessionId 发到该页
        created = cdp.call("Target.createTarget", {"url": "about:blank"})
        attached = cdp.call("Target.attachToTarget", {"targetId": created["targetId"], "flatten": True})
        cdp.session_id = attached["sessionId"]
        cdp.call("Page.enable")
        cdp.call(
            "Emulation.setDeviceMetricsOverride",
            {
                "width": VIEWPORT_W,
                "height": VIEWPORT_H,
                "deviceScaleFactor": SCALE,
                "mobile": True,
            },
        )
        base = f"http://127.0.0.1:{args.port}/"
        for name in names:
            out = shoot(cdp, base, name, SHOTS[name], args.settle)
            print(f"  {name:12}→ {out.relative_to(APP_DIR)}  ({out.stat().st_size / 1024:.0f} KB)")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(user_dir, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
