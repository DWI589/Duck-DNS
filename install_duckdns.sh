#!/bin/bash

# ====================================================
# Duck DNS 一键安装脚本 (最终稳健版)
# ====================================================

# 1. 检查输入参数
DOMAIN=$1
TOKEN=$2

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
    echo "错误: 请提供域名和 Token。"
    echo "用法: bash install_duckdns.sh [你的域名] [你的Token]"
    exit 1
fi

# 2. 检查必要软件依赖
for cmd in curl crontab; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 系统未安装 $cmd，请先安装后再运行。"
        exit 1
    fi
done

echo "正在开始安装 Duck DNS 更新脚本..."

# 3. 确定绝对路径
USER_HOME=$HOME
WORK_DIR="$USER_HOME/duckdns"
mkdir -p "$WORK_DIR"

# 4. 编写更新脚本 duck.sh
# 注意：在 EOF 块中，针对生成的脚本内部变量使用 \$，针对当前安装脚本变量则直接使用
cat <<EOF > "$WORK_DIR/duck.sh"
#!/bin/bash

# 设置 PATH 确保 Cron 环境下能找到命令
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

DOMAIN="$DOMAIN"
TOKEN="$TOKEN"
WORK_DIR="$WORK_DIR"

# 获取外网 IPv4 (多接口备份，强制使用 IPv4)
CURRENT_IP=\$(curl -4 -s --connect-timeout 5 http://whatismyip.akamai.com/ || \\
             curl -4 -s --connect-timeout 5 https://ifconfig.me/ || \\
             curl -4 -s --connect-timeout 5 https://api.ipify.org)

# 检查 IP 是否获取成功
if [ -z "\$CURRENT_IP" ]; then
    echo "[\$(date)] 错误: 无法获取公网 IP" >> "\$WORK_DIR/duck_error.log"
    exit 1
fi

# 提交更新到 Duck DNS
# -k 忽略证书校验，-s 静默模式，-S 显示错误，-o 记录结果
curl -k -s -S "https://www.duckdns.org/update?domains=\$DOMAIN&token=\$TOKEN&ip=\$CURRENT_IP" -o "\$WORK_DIR/duck.log"

# 记录历史日志
echo "[\$(date)] IP updated to: \$CURRENT_IP" >> "\$WORK_DIR/duck_history.log"
EOF

# 5. 设置权限
chmod +x "$WORK_DIR/duck.sh"

# 6. 设置 Cron 任务 (每 2 分钟运行一次)
CRON_JOB="*/2 * * * * /bin/bash $WORK_DIR/duck.sh >/dev/null 2>&1"

# 移除旧任务并添加新任务，确保不重复
(crontab -l 2>/dev/null | grep -v "$WORK_DIR/duck.sh"; echo "$CRON_JOB") | crontab -

echo "------------------------------------------------"
echo "安装完成！"
echo "脚本位置: $WORK_DIR/duck.sh"
echo "日志文件: $WORK_DIR/duck.log"
echo "错误记录: $WORK_DIR/duck_error.log"
echo "定时任务: 已设置每 2 分钟执行一次"
echo "------------------------------------------------"

# 7. 立即执行一次并显示结果
bash "$WORK_DIR/duck.sh"
if [ -f "$WORK_DIR/duck.log" ]; then
    RESULT=$(cat "$WORK_DIR/duck.log")
    echo "首次运行结果 (期待 OK): $RESULT"
    if [ "$RESULT" != "OK" ]; then
        echo "提示: 返回结果不是 OK，请检查 Token 和域名是否正确。"
    fi
else
    echo "运行失败，请检查网络连接。"
fi
