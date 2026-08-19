#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ntfy-sub.py — ntfy 订阅脚本（Python 标准库，零依赖）

用法:
  python ntfy-sub.py [topic ...]        实时订阅一个或多个 topic（支持通配符，如 *.ci）
  python ntfy-sub.py --test             发一条测试消息并拉回验证链路后退出
  python ntfy-sub.py --once <topic>     一次性拉最近一条消息（不常驻）

环境变量:
  NTFY_SERVER   服务器地址，默认 http://192.168.199.131:8084
  NTFY_TOKEN    访问 token（deny-all 下必填，Bearer 认证）

示例（Windows / Linux 通用）:
  set NTFY_TOKEN=tk_xxx
  python ntfy-sub.py devops-test *.ci
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request

SERVER = os.environ.get("NTFY_SERVER", "http://192.168.199.131:8084").rstrip("/")
TOKEN = os.environ.get("NTFY_TOKEN", "")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def _headers():
    h = {"Accept": "application/json"}
    if TOKEN:
        h["Authorization"] = "Bearer " + TOKEN
    return h


def _add_header_safe(req, name, value):
    """HTTP 头只支持 ASCII；非 ASCII 标题（如中文）丢弃，消息体不受影响"""
    try:
        req.add_header(name, value)
    except UnicodeEncodeError:
        pass


def publish(topic, title=None, message="", priority=None):
    """发消息（POST /topic，用于 --test）"""
    req = urllib.request.Request(
        f"{SERVER}/{topic}", data=message.encode(), method="POST", headers=_headers()
    )
    if title:
        _add_header_safe(req, "Title", title)
    if priority:
        _add_header_safe(req, "Priority", str(priority))
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status


def fetch_latest(topic):
    """一次性拉最近一条（GET /topic/json?poll=1，返回 NDJSON，取最后一条 message）"""
    req = urllib.request.Request(f"{SERVER}/{topic}/json?poll=1", headers=_headers())
    with urllib.request.urlopen(req, timeout=15) as r:
        text = r.read().decode()
    last = None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get("event") == "message":
            last = d
    return last


def stream(topic):
    """实时订阅：长连接 JSON 流，断线自动重连（每个 topic 一个线程）"""
    while True:
        try:
            req = urllib.request.Request(f"{SERVER}/{topic}/json", headers=_headers())
            with urllib.request.urlopen(req, timeout=None) as r:
                for raw in r:
                    line = raw.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if d.get("event") != "message":
                        continue
                    now = time.strftime("%H:%M:%S")
                    t = d.get("topic", "?")
                    title = d.get("title") or t
                    msg = d.get("message", "")
                    print(f"[{now}] [{t}] {title}: {msg}", flush=True)
        except (urllib.error.URLError, ConnectionError, OSError) as e:
            print(f"[!] {topic} 连接断开（{e}），5 秒后重连…", file=sys.stderr, flush=True)
            time.sleep(5)


def main():
    args = sys.argv[1:]

    if "--test" in args:
        code = publish("devops-test", title="ntfy-sub selftest", message="曼波测试：Python 订阅脚本链路 OK")
        print(f"publish -> HTTP {code}")
        time.sleep(1)
        latest = fetch_latest("devops-test")
        print("收到 ->", json.dumps(latest, ensure_ascii=False))
        return

    if "--once" in args:
        topic = args[args.index("--once") + 1] if len(args) > args.index("--once") + 1 else "devops-test"
        latest = fetch_latest(topic)
        print(json.dumps(latest, ensure_ascii=False, indent=2))
        return

    topics = args or ["devops-test"]
    if not TOKEN:
        print("[!] 未设置 NTFY_TOKEN，deny-all 下订阅会被拒", file=sys.stderr)
    print(f"订阅 {SERVER} -> {topics}（Ctrl+C 退出）", flush=True)

    threads = [threading.Thread(target=stream, args=(t,), daemon=True) for t in topics]
    for t in threads:
        t.start()
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
