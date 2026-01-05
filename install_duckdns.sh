#!/bin/bash

# =========================================================
# Duck DNS Auto-Updater (AWS Lightsail Optimized)
# =========================================================

DOMAIN=$1
TOKEN=$2

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo "Usage: bash install_duckdns.sh <domain> <token>"
    exit 1
fi

# 获取工作目录（使用绝对路径）
WORK_DIR="$HOME/duckdns"
mkdir -p "$WORK_DIR"

# 1. 写入更新脚本
cat <<EOF > "$WORK_DIR/duck.sh"
#!/bin/bash
# AWS IMDSv2 Token 获取
METADATA_TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

# 获取公网 IP
if [ ! -z "\$METADATA_TOKEN" ]; then
    IPV4=\$(curl -s -H "X-aws-ec2-metadata-token: \$METADATA_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 --connect-timeout 2)
fi

# 回退方案
if [ -z "\$IPV4" ]; then
    IPV4=\$(curl -4 -s https://ifconfig.me --connect-timeout 5)
fi

if [ ! -z "\$IPV4" ]; then
    RESPONSE=\$(curl -k -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=\$IPV4")
    echo "\$RESPONSE" > "$WORK_DIR/duck.log"
    echo "[\$(date)] IP: \$IPV4 Status: \$RESPONSE" >> "$WORK_DIR/history.log"
fi
EOF

# 2. 权限与定时任务
chmod +x "$WORK_DIR/duck.sh"
(crontab -l 2>/dev/null | grep -v "duckdns"; echo "*/2 * * * * $WORK_DIR/duck.sh >/dev/null 2>&1") | crontab -

# 3. 立即执行
bash "$WORK_DIR/duck.sh"
echo "安装完成，状态: \$(cat $WORK_DIR/duck.log)"
