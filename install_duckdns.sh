#!/bin/bash

# =========================================================
# Duck DNS Auto-Updater (AWS Lightsail Optimized - 2 Min)
# =========================================================

# 1. 检查输入参数
DOMAIN=$1
TOKEN=$2

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo "错误: 参数缺失"
    echo "用法: bash install_duckdns.sh [你的域名] [你的Token]"
    exit 1
fi

# 获取当前用户的绝对路径，确保 Cron 运行环境稳定
WORK_DIR="$HOME/duckdns"
mkdir -p "$WORK_DIR"

echo "正在安装 Duck DNS 更新脚本到 $WORK_DIR..."

# 2. 写入核心更新脚本 duck.sh
cat <<EOF > "$WORK_DIR/duck.sh"
#!/bin/bash
# ---------------------------------------------------------
# AWS Lightsail 专用 IP 更新逻辑 (支持 IMDSv2)
# ---------------------------------------------------------

# 获取 AWS 内部元数据 Token
METADATA_TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

# 获取公网 IPv4
if [ ! -z "\$METADATA_TOKEN" ]; then
    IPV4=\$(curl -s -H "X-aws-ec2-metadata-token: \$METADATA_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 --connect-timeout 2)
fi

# 如果 AWS 元数据失败，回退到公共 API
if [ -z "\$IPV4" ]; then
    IPV4=\$(curl -4 -s https://ifconfig.me --connect-timeout 5)
fi

# 如果成功获取 IP，则上报 Duck DNS
if [ ! -z "\$IPV4" ]; then
    # 发送请求
    RESPONSE=\$(curl -k -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=\$IPV4")
    
    # 保存状态和详细历史记录
    echo "\$RESPONSE" > "$WORK_DIR/duck.log"
    echo "[\$(date)] IP: \$IPV4 Status: \$RESPONSE" >> "$WORK_DIR/history.log"
    
    # 保持历史记录文件不要过大 (只保留最后 200 行)
    tail -n 200 "$WORK_DIR/history.log" > "$WORK_DIR/history.log.tmp" && mv "$WORK_DIR/history.log.tmp" "$WORK_DIR/history.log"
fi
EOF

# 3. 设置脚本执行权限
chmod +x "$WORK_DIR/duck.sh"

# 4. 配置定时任务 (每 2 分钟运行一次)
# 使用绝对路径运行脚本，防止 Cron 找不到主目录
(crontab -l 2>/dev/null | grep -v "duckdns/duck.sh"; echo "*/2 * * * * $WORK_DIR/duck.sh >/dev/null 2>&1") | crontab -

# 5. 立即运行一次并反馈结果
bash "$WORK_DIR/duck.sh"

echo "------------------------------------------------"
echo "安装完成！"
echo "更新频率: 每 2 分钟"
echo "当前状态: \$(cat $WORK_DIR/duck.log)"
echo "查看历史: cat $WORK_DIR/history.log"
echo "------------------------------------------------"
