# -*- coding: utf-8 -*-
"""一次性脚本：用密码登录目标服务器，推送本地公钥实现免密，并输出服务器摸底信息。

用法：SSH_PASSWORD=<密码> python push_key_135.py
"""
import os
import sys
import paramiko

HOST = "192.168.199.135"
USER = "xhh"
PASSWORD = os.environ.get("SSH_PASSWORD") or sys.exit("缺少 SSH_PASSWORD 环境变量")

PUBKEY_PATH = r"C:\Users\robot\.ssh\id_ed25519.pub"

def main():
    with open(PUBKEY_PATH, "r", encoding="utf-8") as f:
        pubkey = f.read().strip()

    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cli.connect(HOST, port=22, username=USER, password=PASSWORD, timeout=15)

    cmds = [
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh",
        f"grep -qF '{pubkey.split()[1][:40]}' ~/.ssh/authorized_keys 2>/dev/null || echo '{pubkey}' >> ~/.ssh/authorized_keys",
        "chmod 600 ~/.ssh/authorized_keys",
        "echo '=== whoami ==='; whoami; hostname",
        "echo '=== os ==='; cat /etc/os-release | head -3",
        "echo '=== disk ==='; df -h / /opt /var 2>/dev/null | sort -u",
        "echo '=== mem ==='; free -h | head -2",
        "echo '=== docker ==='; docker version --format 'server: {{.Server.Version}}' 2>&1; docker compose version 2>&1 | head -1",
        "echo '=== containers ==='; docker ps -a --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}' 2>&1",
        "echo '=== images ==='; docker images --format '{{.Repository}}:{{.Tag}} ({{.Size}})' 2>&1 | head -30",
        "echo '=== volumes ==='; docker volume ls 2>&1",
        "echo '=== sudo ==='; sudo -n true 2>&1 && echo SUDO_OK || echo SUDO_NEEDS_PASSWORD",
    ]
    for c in cmds:
        stdin, stdout, stderr = cli.exec_command(c, timeout=60)
        out = stdout.read().decode(errors="replace")
        err = stderr.read().decode(errors="replace")
        if out.strip():
            print(out.strip())
        if err.strip() and "sudo" not in c:
            print("STDERR:", err.strip()[:500], file=sys.stderr)
    cli.close()

if __name__ == "__main__":
    main()
