"""短剧库 iOS App 的本地模拟服务端，仅用于界面预览与接口联调。"""
import json
import random
import struct
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8999

TITLES = [
    ("闪婚后，大叔每天想官宣", "都市", "hongguo", 86),
    ("病娇大佬的心尖宠", "甜宠", "huangguo", 92),
    ("重生之我在豪门当团宠", "逆袭", "hongguo", 78),
    ("长嫂如母", "古装", "juguo", 64),
    ("末世第一女王", "悬疑", "yeguo", 71),
    ("离婚后她惊艳全球", "都市", "hongguo", 88),
    ("我的九个师姐绝色倾城", "玄幻", "huangdou", 96),
    ("医妃惊华", "古装", "diguo", 60),
    ("开局签到荒古圣体", "玄幻", "huangdou", 100),
    ("偏执老公宠上瘾", "甜宠", "huangguo", 82),
    ("一胎双宝：总裁爹地宠上天", "甜宠", "hongguo", 74),
    ("战神归来", "逆袭", "yeguo", 90),
    ("夜夜笙歌", "悬疑", "juguo", 58),
    ("天降萌宝：妈咪快跑", "甜宠", "hongguo", 80),
    ("重生八零：媳妇有点辣", "年代", "huangguo", 66),
    ("陆少的隐婚新娘", "都市", "diguo", 84),
    ("师尊在上", "古装", "huangdou", 62),
    ("万人迷她只想搞事业", "都市", "hongguo", 76),
    ("总裁的贴身保镖", "都市", "yeguo", 70),
    ("我在仙界送外卖", "玄幻", "juguo", 54),
    ("错嫁良缘", "古装", "huangguo", 68),
    ("暴富从捡漏开始", "逆袭", "hongguo", 87),
    ("娇妻别想逃", "甜宠", "diguo", 79),
    ("隐世高手在都市", "都市", "huangdou", 93),
]

DESC = (
    "一场意外让两个陌生人被绑在一起，她以为自己只是过客，却在一次次交锋中沦陷。"
    "当真相浮出水面，曾经最信任的人成了最大的敌人，而那个一直站在身后的人，"
    "却用最笨拙的方式护她周全。"
)

COLORS = [
    (232, 74, 96), (245, 138, 76), (94, 120, 220), (72, 176, 160),
    (168, 96, 208), (220, 96, 140), (86, 150, 96), (208, 150, 60),
]


def make_drama(index: int):
    title, category, source, episodes = TITLES[index % len(TITLES)]
    return {
        "id": f"d{index:03d}",
        "title": title,
        "name": title,
        "source": source,
        "category": category,
        "categoryName": category,
        "episodeCount": episodes,
        "totalEpisode": episodes,
        "desc": DESC,
        "intro": DESC,
        "cover": f"/api/ui/image?id=d{index:03d}",
        "score": f"{random.uniform(8.0, 9.8):.1f}",
        "heat": f"{random.randint(12, 980)}万",
        "releaseStatus": random.choice(["finished", "ongoing"]),
        "tags": [category, "热播"],
        "vip": index % 7 == 3,
    }


DRAMAS = [make_drama(i) for i in range(30)]


def png(width, height, color):
    raw = b""
    r, g, b = color
    for y in range(height):
        k = 0.55 + 0.45 * (y / height)
        raw += b"\x00" + bytes([min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k))]) * width
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6))
            + chunk(b"IEND", b""))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _send(self, status, payload, content_type="application/json; charset=utf-8"):
        body = payload if isinstance(payload, bytes) else json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send(204, b"")

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path

        if path == "/api/ui/image":
            seed = sum(ord(c) for c in query.get("id", ["x"])[0])
            self._send(200, png(300, 400, COLORS[seed % len(COLORS)]), "image/png")
            return
        if path == "/api/ui/config":
            self._send(403, {"code": "admin_required", "error": "此操作需要管理员账号"})
            return
        if path == "/api/ui/dramas":
            self._send(200, {"revision": 7, "loading": False, "data": DRAMAS, "loadedAt": "2026-10-18T17:00:00Z"})
            return
        if path == "/api/ui/recommendations":
            self._send(200, {"data": DRAMAS[:10]})
            return
        if path == "/api/ui/rankings":
            board = query.get("board", [""])[0]
            if not board:
                self._send(200, {"boards": [
                    {"id": "hot", "name": "热播榜", "source": "hongguo"},
                    {"id": "new", "name": "新剧榜", "source": "huangguo"},
                    {"id": "rise", "name": "飙升榜", "source": "juguo"},
                ]})
                return
            source = {"hot": "hongguo", "new": "huangguo", "rise": "juguo"}.get(board, "")
            pool = [d for d in DRAMAS if not source or d["source"] == source] or DRAMAS
            items = [{"rank": i + 1, "drama": d} for i, d in enumerate(pool[:14])]
            self._send(200, {"boardId": board, "page": 1, "items": items, "updatedText": "刚刚更新"})
            return
        if path == "/api/ui/categories":
            self._send(200, {"items": ["都市", "甜宠", "逆袭", "古装", "悬疑", "玄幻", "年代"]})
            return
        if path == "/api/ui/search":
            keyword = (query.get("q", [""])[0] or query.get("query", [""])[0]).strip()
            hits = [d for d in DRAMAS if keyword and (keyword in d["title"] or keyword in d["category"])]
            self._send(200, {"data": hits})
            return
        if path == "/api/ui/following":
            self._send(200, {"data": [
                {"dramaId": DRAMAS[0]["id"], "drama": DRAMAS[0], "episode": 23, "position": 0, "duration": 0},
                {"dramaId": DRAMAS[1]["id"], "drama": DRAMAS[1], "episode": 8, "position": 0, "duration": 0},
                {"dramaId": DRAMAS[6]["id"], "drama": DRAMAS[6], "episode": 41, "position": 0, "duration": 0},
            ]})
            return
        if path == "/api/ui/playback/history":
            self._send(200, {"data": [
                {"dramaId": DRAMAS[2]["id"], "drama": DRAMAS[2], "episode": 12, "position": 640, "duration": 1500,
                 "updatedAt": "2026-10-18T12:30:00Z"},
                {"dramaId": DRAMAS[4]["id"], "drama": DRAMAS[4], "episode": 3, "position": 120, "duration": 1400,
                 "updatedAt": "2026-10-17T21:10:00Z"},
                {"dramaId": DRAMAS[9]["id"], "drama": DRAMAS[9], "episode": 55, "position": 1400, "duration": 1400,
                 "updatedAt": "2026-10-16T09:00:00Z"},
            ], "limit": 500})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except Exception:
            body = {}

        if parsed.path == "/api/ui/playback/open":
            drama_id = body.get("dramaId", "")
            drama = next((d for d in DRAMAS if d["id"] == drama_id), DRAMAS[0])
            total = drama["episodeCount"]
            episodes = [{"index": i + 1, "episode": f"第{i + 1}集", "title": "", "danmaku": i % 3 == 0, "number": i + 1, "total": total}
                        for i in range(min(total, 60))]
            self._send(200, {
                "session": "mock-session",
                "dramaId": drama["id"],
                "title": drama["title"],
                "episodes": episodes,
                "initialIndex": 1,
                "initialPosition": 0,
                "resumeMessage": "",
                "mimeType": "application/vnd.apple.mpegurl",
                "mode": "",
            })
            return
        if parsed.path == "/api/ui/playback/hls/open":
            self._send(200, {
                "url": "/media/sample.m3u8",
                "run": 1,
                "duration": 1500,
                "qualities": [{"value": 0, "label": "自动"}, {"value": 1, "label": "高清"}],
                "quality": 0,
            })
            return
        if parsed.path == "/api/ui/playback/progress":
            self._send(200, {"ok": True})
            return
        if parsed.path == "/api/ui/playback/control":
            self._send(200, {"ok": True})
            return
        if parsed.path == "/api/ui/following":
            self._send(200, {"entry": {"saved": bool(body.get("saved"))}})
            return
        if parsed.path == "/api/ui/playback/history/remove":
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    random.seed(7)
    print(f"mock server on http://127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
