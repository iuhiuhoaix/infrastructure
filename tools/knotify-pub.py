#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
knotify-pub.py — knotify(Company.Notify) 通知网关 · 发布脚本（Python 标准库，零依赖）

用法:
  python knotify-pub.py --title "构建完成" --body "v1.0 已上线" --recipient user:10021
  python knotify-pub.py --title "告警" --body "磁盘>90%" --recipient role:ops --priority urgent
  python knotify-pub.py --title "广播" --body "下午 4 点周会" --topic ops.alerts --source meeting
  python knotify-pub.py --body "v2 发布" --recipient user:10021,user:10035 --dedup-key deploy-2026-08-29

环境变量:
  KNOTIFY_SERVER    网关地址，默认 http://192.168.199.131:8084
  KNOTIFY_API_KEY   发布方 ApiKey（X-Api-Key 头，必填；在服务器 deploy/knotify/.env 的 Seed__ApiKey）

示例（Windows / Linux 通用）:
  set KNOTIFY_API_KEY=xxx
  python knotify-pub.py --title 部署完成 --body v1.0 --recipient user:10021
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

SERVER = os.environ.get("KNOTIFY_SERVER", "http://192.168.199.131:8084").rstrip("/")
API_KEY = os.environ.get("KNOTIFY_API_KEY", "")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def publish(title, body, recipients=None, topic=None, priority=None,
            source="script", event_type="manual", action_url=None, dedup_key=None):
    """POST /api/v1/notifications — 落库即回 202，投递由 Outbox 异步完成"""
    payload = {
        "source": source,
        "eventType": event_type,
        "title": title or "",
        "body": body or "",
        "recipients": recipients or [],
        "topic": topic,
        "priority": priority,
        "actionUrl": action_url,
        "deduplicationKey": dedup_key,
        "expiresAt": None,
    }
    req = urllib.request.Request(
        f"{SERVER}/api/v1/notifications",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "X-Api-Key": API_KEY,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def main():
    p = argparse.ArgumentParser(description="knotify 通知发布")
    p.add_argument("--title", help="标题")
    p.add_argument("--body", required=True, help="正文（必填）")
    p.add_argument("--recipient", help="接收人，逗号分隔多个（user:10021 / role:ops）")
    p.add_argument("--topic", help="topic 广播（与 recipient 至少其一）")
    p.add_argument("--priority", choices=["low", "normal", "default", "high", "urgent"],
                   help="优先级")
    p.add_argument("--source", default="script", help="来源系统（默认 script）")
    p.add_argument("--event-type", default="manual", help="事件类型（默认 manual）")
    p.add_argument("--action-url", help="点击跳转 URL")
    p.add_argument("--dedup-key", help="幂等键：(source, dedup-key) 相同视为同一条")
    args = p.parse_args()

    if not API_KEY:
        sys.exit("缺少 KNOTIFY_API_KEY（服务器 deploy/knotify/.env 的 Seed__ApiKey）")
    if not args.recipient and not args.topic:
        sys.exit("--recipient 与 --topic 至少提供一个")

    recipients = [r.strip() for r in args.recipient.split(",") if r.strip()] if args.recipient else None
    code, resp = publish(args.title, args.body, recipients, args.topic,
                         args.priority, args.source, args.event_type,
                         args.action_url, args.dedup_key)
    if code == 202:
        print(f"✅ {code} 已受理: notificationId={resp.get('notificationId')} "
              f"deliveryIds={resp.get('deliveryIds')} deduped={resp.get('deduped', False)}")
    else:
        print(f"❌ {code} {resp}")


if __name__ == "__main__":
    main()
