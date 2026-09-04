#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
knotify-sub.py — knotify(Company.Notify) 通知网关 · 订阅脚本（Python 标准库，零依赖，轮询式）

用法:
  python knotify-sub.py --recipient user:10021          # 拉一次当前未读并回执
  python knotify-sub.py --recipient user:10021 --listen  # 轮询监听，新消息即打印（自动回执 delivered+read）
  python knotify-sub.py --recipient user:10021 --no-ack  # 只读不回执（不推进状态机）
  python knotify-sub.py --test                          # 自测链路：发一条给自己再拉回验证

流程: ApiKey 签 connect-token(按接收人) → Bearer accessToken → 查未读 → 逐条回执。
实时推送走 SignalR（/hubs/notifications?access_token=...），本脚本用轮询替代，零依赖够用。

环境变量:
  KNOTIFY_SERVER     网关地址，默认 http://192.168.199.131:8084
  KNOTIFY_API_KEY    发布方 ApiKey（签 connect-token 用，必填）
  KNOTIFY_RECIPIENT  默认接收人（如 user:10021）
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

SERVER = os.environ.get("KNOTIFY_SERVER", "http://192.168.199.131:8084").rstrip("/")
API_KEY = os.environ.get("KNOTIFY_API_KEY", "")
RECIPIENT = os.environ.get("KNOTIFY_RECIPIENT", "")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def _call(path, method="GET", body=None, token=None, api_key=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if api_key:
        headers["X-Api-Key"] = api_key
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    if data:
        headers["Content-Type"] = "application/json; charset=utf-8"
    req = urllib.request.Request(f"{SERVER}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def connect_token(recipient):
    """签一个连接令牌（Bearer accessToken，短时效）"""
    code, resp = _call("/api/v1/connect-token", "POST",
                       {"recipient": recipient}, api_key=API_KEY)
    if code != 200:
        sys.exit(f"connect-token 失败 {code}: {resp}")
    return resp["accessToken"]


def fetch_unread(token):
    """拉当前未读列表（响应为分页对象 {items, nextCursor, hasMore}）"""
    code, resp = _call("/api/v1/notifications?status=unread&limit=20", token=token)
    if code != 200:
        sys.exit(f"查询失败 {code}: {resp}")
    if isinstance(resp, dict) and "items" in resp:
        return resp["items"]
    return resp


def ack(token, delivery_id, action):
    """回执：delivered / read"""
    return _call(f"/api/v1/deliveries/{delivery_id}/{action}", "POST", token=token)


def publish_self(title, body, recipient):
    """--test 用：发一条给自己（内联发布，保持单文件零依赖）"""
    payload = {
        "source": "knotify-sub",
        "eventType": "selftest",
        "title": title,
        "body": body,
        "recipients": [recipient],
        "topic": None,
        "priority": "normal",
        "actionUrl": None,
        "deduplicationKey": None,
        "expiresAt": None,
    }
    code, resp = _call("/api/v1/notifications", "POST", payload, api_key=API_KEY)
    return code, resp


def show(item):
    pri = item.get("priority") or ""
    tag = {"low": "🔵", "normal": "⚪", "default": "⚪",
           "high": "🟠", "urgent": "🔴"}.get(str(pri).lower(), "⚪")
    print(f"{tag} [{item.get('id')}] {item.get('title') or '(无标题)'}")
    if item.get("body"):
        print(f"    {item.get('body')}")
    meta = []
    if item.get("source"):
        meta.append(f"source={item.get('source')}")
    if item.get("eventType"):
        meta.append(f"event={item.get('eventType')}")
    if item.get("topic"):
        meta.append(f"topic={item.get('topic')}")
    if item.get("createdAt"):
        meta.append(f"at={item.get('createdAt')}")
    if item.get("actionUrl"):
        meta.append(f"link={item.get('actionUrl')}")
    if meta:
        print(f"    " + " | ".join(meta))


def run_once(recipient, do_ack=True, seen=None):
    token = connect_token(recipient)
    items = fetch_unread(token)
    new_items = [i for i in items if not seen or i.get("id") not in seen]
    for it in new_items:
        show(it)
        did = it.get("userDeliveryId")
        if do_ack and did:
            ack(token, did, "delivered")
            ack(token, did, "read")
    return token, items


def main():
    p = argparse.ArgumentParser(description="knotify 通知订阅（轮询式）")
    p.add_argument("--recipient", help="接收人（默认取 KNOTIFY_RECIPIENT，如 user:10021）")
    p.add_argument("--listen", action="store_true", help="轮询监听模式（默认 5s 间隔）")
    p.add_argument("--interval", type=float, default=5.0, help="监听轮询间隔秒数（默认 5）")
    p.add_argument("--no-ack", action="store_true", help="只读不回执")
    p.add_argument("--test", action="store_true", help="自测链路：发一条给自己再拉回")
    args = p.parse_args()

    if not API_KEY:
        sys.exit("缺少 KNOTIFY_API_KEY（服务器 deploy/knotify/.env 的 Seed__ApiKey）")
    recipient = args.recipient or RECIPIENT
    if not recipient:
        sys.exit("缺少接收人（--recipient 或 KNOTIFY_RECIPIENT，格式 user:10021）")

    if args.test:
        code, resp = publish_self("knotify 自测", "链路通了，冲鸭 🐟", recipient)
        print(f"已发布（{code}）: {resp.get('notificationId')}")
        time.sleep(1.5)  # 等 Outbox 投递
        run_once(recipient, do_ack=not args.no_ack)
        return

    if args.listen:
        print(f"监听中（{recipient}，间隔 {args.interval}s，Ctrl+C 退出）...")
        seen = set()
        while True:
            try:
                _, items = run_once(recipient, do_ack=not args.no_ack, seen=seen)
                seen.update(i.get("id") for i in items)
            except Exception as e:
                print(f"⚠️ {e}", file=sys.stderr)
            time.sleep(args.interval)
    else:
        run_once(recipient, do_ack=not args.no_ack)


if __name__ == "__main__":
    main()
