#!/usr/bin/env python3
"""并行分段下载器：range 分片 + 断点续传 + 失败重试，用于慢速不稳定连接"""
import os
import sys
import time
import threading
import urllib.request

URL = "https://dotnetcli.azureedge.net/dotnet/Sdk/10.0.302/dotnet-sdk-10.0.302-linux-x64.tar.gz"
OUT = "/opt/dotnet-sdk-10.0.302-linux-x64.tar.gz"
SEG_SIZE = 8 * 1024 * 1024  # 每段 8MB
THREADS = 8
PARTS_DIR = "/opt/dl-parts"

os.makedirs(PARTS_DIR, exist_ok=True)

def get_size():
    req = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as r:
        return int(r.headers["Content-Length"])

def download_seg(idx, start, end):
    part = os.path.join(PARTS_DIR, f"seg-{idx:04d}.part")
    done = os.path.getsize(part) if os.path.exists(part) else 0
    while True:
        try:
            cur = start + done
            if cur >= end:
                return
            req = urllib.request.Request(URL, headers={"Range": f"bytes={cur}-{end - 1}"})
            with urllib.request.urlopen(req, timeout=120) as r, open(part, "ab") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    done += len(chunk)
            print(f"seg{idx} DONE", flush=True)
            return
        except Exception as e:
            print(f"seg{idx} retry: {e}", flush=True)
            time.sleep(2)

def main():
    total = get_size()
    print(f"total={total} bytes", flush=True)
    segs = []
    start = 0
    idx = 0
    while start < total:
        end = min(start + SEG_SIZE, total)
        segs.append((idx, start, end))
        start = end
        idx += 1
    print(f"segs={len(segs)} threads={THREADS}", flush=True)
    # 已有本地文件（之前单线程下的）并入 seg0 起点
    if os.path.exists(OUT):
        have = os.path.getsize(OUT)
        if have > 0 and have < total:
            print(f"复用已有 {have} bytes 作为 seg0 起点", flush=True)
            # 把已有内容移到 seg0.part
            seg0 = os.path.join(PARTS_DIR, "seg-0000.part")
            if not os.path.exists(seg0) or os.path.getsize(seg0) < have:
                with open(OUT, "rb") as src, open(seg0, "wb") as dst:
                    dst.write(src.read())
    threads = []
    for (i, s, e) in segs:
        t = threading.Thread(target=download_seg, args=(i, s, e), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()
    # 合并
    with open(OUT, "wb") as out:
        for (i, s, e) in sorted(segs):
            part = os.path.join(PARTS_DIR, f"seg-{i:04d}.part")
            with open(part, "rb") as f:
                while True:
                    c = f.read(1 << 20)
                    if not c:
                        break
                    out.write(c)
    print(f"MERGED total={os.path.getsize(OUT)}", flush=True)

if __name__ == "__main__":
    main()
