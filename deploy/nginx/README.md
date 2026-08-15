# Nginx 部署说明

## 放置位置
宿主机运行（非容器）。Nginx 是平台入口，与单个应用 Compose 生命周期解耦。

## 安装与证书
```bash
apt install -y nginx certbot python3-certbot-nginx
# 签发证书（需域名 DNS 已指向本机）
certbot --nginx -d git.example.com -d reg.git.example.com -d plane.example.com \
        -d jenkins.example.com -d nexus.example.com -d reg.example.com -d rag.example.com
# 自动续期已由 certbot 注册 systemd timer，无需手动 cron
```

## 引入站点配置
在 `/etc/nginx/nginx.conf` 的 `http{}` 内确保：
```nginx
include /opt/devops/nginx/conf.d/*.conf;
```
然后：
```bash
nginx -t && systemctl reload nginx
```

## 端口映射关系
| 域名 | proxy_pass | 后端容器 |
|---|---|---|
| git.example.com | 127.0.0.1:8080 | gitlab:80 |
| reg.git.example.com | 127.0.0.1:8080 | gitlab 内置 registry |
| plane.example.com | 127.0.0.1:3000 | plane-web:80 |
| jenkins.example.com | 127.0.0.1:8081 | jenkins:8080 |
| nexus.example.com | 127.0.0.1:8082 | nexus:8081 |
| reg.example.com | 127.0.0.1:8083 | nexus:8082 (Docker Registry) |
| rag.example.com | 127.0.0.1:9380 | ragflow:9380 |

## 备份
- 配置：`/opt/devops/nginx/conf.d/` 已在各应用 backup 脚本中纳入
- 证书：`/etc/letsencrypt/` 需单独 tar 备份（灾难恢复时也要恢复，或在新机重新签发）
