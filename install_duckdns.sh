#!/bin/bash

# =========================================================
# Duck DNS Auto-Updater for AWS Lightsail (一键安装版)
# =========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. 参数检查
DOMAIN=$1
TOKEN=$2

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo -e "${RED}错误: 参数缺失${NC}"
    echo "用法: bash install_duckdns.sh [你的域名] [你的Token]"
    echo "示例: bash install_duckdns.sh myvps 841f-xxxx-xxxx"
    exit 1
fi

echo -e "${YELLOW}>>> 开始安装 Duck DNS (Lightsail 优化版)...${NC}"

# 2. 检查并安装必要组件 (Cron/Curl)
echo -e "正在检查系统依赖..."
if [ -x "$(command -v apt-get)" ]; then
    # Debian/Ubuntu
    if ! command -v cron &> /dev/null; then
        echo -e "${YELLOW}未检测到 Cron，正在安装...${NC}"
        apt-get update -qq && apt-get install -y cron curl -qq
        systemctl enable cron
        systemctl start cron
    fi
elif [ -x "$(command -v yum)" ]; then
    # CentOS/Amazon Linux
    if ! command -v crond &> /dev/null; then
        echo -e "${YELLOW}未检测到 Cron，正在安装...${NC}"
        yum install -y cronie curl -q
        systemctl enable crond
        systemctl start crond
    fi
fi

# 3. 创建工作目录
WORK_DIR="$HOME/duckdns"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 4. 生成核心更新脚本 (写入 duck.sh)
# 注意：这里使用了 AWS 元数据服务 169.254.169.254
cat <<EOF > duck.sh
#!/bin/bash
DOMAIN="$DOMAIN"
TOKEN="$TOKEN"
LOG_FILE="$WORK_DIR/duck.log"

# [关键步骤] 优先使用 AWS Lightsail 元数据获取公网 IPv4
# 这种方法在 AWS 内部极快且 100% 准确
IPV4=\$(curl -s -4 http://169.254.169.254/latest/meta-data/public-ipv4 --connect-timeout 2)

# 如果 AWS 元数据失败，回退到外部接口
if [ -z "\$IPV4" ]; then
    IPV4=\$(curl -s -4 https://ifconfig.me --connect-timeout 5)
fi

# 如果还是获取不到，退出并报错
if [ -z "\$IPV4" ]; then
    echo "KO" > \$LOG_FILE
    exit 1
fi

# 发送更新请求
# 使用 -k 允许不安全的 SSL (防止老旧系统证书问题)
curl -k -s "https://www.duckdns.org/update?domains=\$DOMAIN&token=\$TOKEN&ip=\$IPV4" > \$LOG_FILE
EOF

# 赋予执行权限
chmod 700 duck.sh

# 5. 设置 Crontab 定时任务
echo -e "正在配置定时任务..."
CRON_CMD="*/2 * * * * $WORK_DIR/duck.sh >/dev/null 2>&1"

# 备份现有 Crontab -> 删除旧的 duckdns 任务 -> 添加新任务
(crontab -l 2>/dev/null | grep -v "duckdns/duck.sh"; echo "$CRON_CMD") | crontab -

# 6. 立即运行测试
echo -e "${YELLOW}>>> 正在执行首次同步测试...${NC}"
$WORK_DIR/duck.sh

# 7. 检查结果
RESULT=$(cat duck.log)
CURRENT_IP=$(curl -s -4 http://169.254.169.254/latest/meta-data/public-ipv4)

if [[ "$RESULT" == *"OK"* ]]; then
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}✅ 安装成功! ${NC}"
    echo -e "当前公网 IP: ${CURRENT_IP}"
    echo -e "更新状态: OK"
    echo -e "脚本路径: $WORK_DIR/duck.sh"
    echo -e "${GREEN}=============================================${NC}"
else
    echo -e "${RED}=============================================${NC}"
    echo -e "${RED}❌ 更新失败!${NC}"
    echo -e "返回内容: $RESULT"
    echo -e "请检查您的 Token 或 域名 是否正确。"
    echo -e "${RED}=============================================${NC}"
fi
