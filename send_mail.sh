#!/bin/bash
#########################################################
# Script to send alerts via Email & WeChat Robot        #
# 修复内容：                                            #
# 1. 修复时间戳八进制问题                               #
# 2. 增强日志解析可靠性                                  #
#########################################################

# 企业微信机器人配置
ROBOT_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key={yourkey}"
#默认网址配置修改
SMOKEPING_CHART_BASE="http://www.example.com/smokeping.cgi"

# 解析Smokeping传入变量
alert_type=$1          # 告警类型（如HostDown）
target_ip=$2           # 目标IP（如8.8.8.8）
loss=$3                # 丢包率（如loss: 100%）
delay=$4               # 延迟（如500ms）
node_path=$5           # 节点路径（如IDC/S3026/xxx）
timestamp=$(date "+%Y-%m-%d %H:%M:%S")
src_ip=$(curl -s icanhazip.com || echo "Unknown_IP")

# 自定义路径变量
log_dir="/smokeping/log"
smokeping_mail_content="${log_dir}/smokeping_mail_content.$(date +%s%N)"
invoke_file="${log_dir}/invoke.log"
mail_send_log="${log_dir}/send.log"

# 生成图表链接（不带IP）
encoded_target=$(echo "${node_path}" | sed -e 's/\//./g' -e 's/ /%20/g')
chart_url="${SMOKEPING_CHART_BASE}?target=${encoded_target}&display=last"

# 告警状态样式
if [ "${loss}" = "loss: 0%" ]; then
    status_icon="🟢"
    status_color="info"
    subject_type="恢复通知"
else
    status_icon="🔴"
    status_color="warning"
    subject_type="故障告警"
fi

# 构建节点层级显示
IFS='/' read -ra nodes <<< "${node_path}"
node_hierarchy=""
for ((i=0; i<${#nodes[@]}; i++)); do
    node_hierarchy+="▸ ${nodes[i]} "
done

# 生成邮件内容
{
echo -e "网络质量监控报告\n"
echo "节点路径: ${node_path}"
echo "IP地址: ${target_ip}"
echo "告警类型: ${alert_type}"
echo "丢包率: ${loss}"
echo "网络延迟: ${delay}"
echo "时间: ${timestamp}"
echo -e "\n----- MTR路径追踪 -----"
mtr --no-dns -r -c3 -w -b ${target_ip} | nali | column -t
} > ${smokeping_mail_content}

# 企业微信Markdown内容（手动处理JSON转义）
markdown_content=$(cat <<EOF
<font color="${status_color}">**${status_icon} ${subject_type}**</font>\n
**节点路径**: ${node_hierarchy}\n
**目标地址**: \`${target_ip}\`\n
**发生时间**: ${timestamp}\n
**当前状态**: ${loss} / ${delay}\n
**监控图表**: [点击查看](${chart_url})\n\n
<font color="comment">来自监控服务器: ${src_ip}</font>
EOF
)

# 转义双引号和换行符
markdown_content=${markdown_content//\"/\\\"}
markdown_content=${markdown_content//$'\n'/\\n}

# 构建JSON数据
json_data="{
  \"msgtype\": \"markdown\",
  \"markdown\": {
    \"content\": \"${markdown_content}\"
  }
}"

# 邮件主题（带颜色标识）
subject="${status_icon} ${subject_type} - ${node_path##*/}"

# 告警去重检查（修复八进制问题）
last_alert=$(grep "${target_ip}" ${invoke_file} | tail -1)
if [[ -n "$last_alert" ]]; then
    # 安全提取时间戳字段
    log_timestamp=$(echo "$last_alert" | awk '{print $2}')
    # 过滤非数字字符并转换进制
    log_timestamp=$(echo "$log_timestamp" | tr -cd '0-9')
    if [[ -n "$log_timestamp" ]]; then
        log_timestamp=$((10#$log_timestamp))  # 强制十进制
        current_timestamp=$(date +%s)
        time_diff=$((current_timestamp - log_timestamp))
        
        if [[ "$last_alert" == *"${subject_type}"* ]] && [ $time_diff -lt 3600 ]; then
            echo "$(date +'%F %T') $(date +%s) skip:${target_ip}" >> ${invoke_file}
            rm -f ${smokeping_mail_content}
            exit 0
        fi
    fi
fi

# 记录发送日志（确保时间戳无前导零）
echo "$(date +'%F %T') $(date +%s) sent:${target_ip} ${subject_type}" >> ${invoke_file}

# 发送邮件通知
/bin/bash /smokeping/bin/maily.sh "${subject}" "$(cat ${smokeping_mail_content})" >> ${mail_send_log} 2>&1

# 发送企业微信通知
curl -s -X POST -H "Content-Type: application/json" \
     -d "${json_data}" ${ROBOT_WEBHOOK} >> ${mail_send_log} 2>&1

# 清理临时文件
rm -f ${smokeping_mail_content}

exit 0
