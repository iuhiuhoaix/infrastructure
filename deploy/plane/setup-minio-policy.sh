#!/bin/bash
# Plane MinIO bucket 公开读 policy（幂等，部署/恢复后执行一次）
# 背景：Plane 图片/附件 URL 是 http://<host>/plane/<key>，浏览器匿名 GET，
#       但 backend 的 create_bucket 只建桶不设 policy，需手动开 public read。
# 用法：在服务器 /opt/devops/plane/ 下执行 bash setup-minio-policy.sh（需 plane-api 容器在运行）
set -e

cat > /tmp/plane_minio_policy.py <<'PYEOF'
import boto3, os, json
c = boto3.client("s3",
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
    endpoint_url="http://minio:9000",
    region_name=os.environ.get("AWS_REGION", "us-east-1"))
bucket = os.environ.get("AWS_S3_BUCKET_NAME", "plane")
policy = {
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": ["*"]},
        "Action": ["s3:GetObject"],
        "Resource": [f"arn:aws:s3:::{bucket}/*"],
    }]
}
c.put_bucket_policy(Bucket=bucket, Policy=json.dumps(policy))
print(f"OK: bucket '{bucket}' policy set (public read)")
PYEOF

docker cp /tmp/plane_minio_policy.py plane-api:/tmp/plane_minio_policy.py
docker exec plane-api python3 /tmp/plane_minio_policy.py
echo "Done."
