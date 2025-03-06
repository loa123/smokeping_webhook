# smokeping_webhook

smokeping企业微信机器人推送

1.修改send_mail.sh

2.修改config的部分配置：

其中发送邮件部分

*** Alerts ***

to = |/smokeping/bin/send_mail.sh

+hostdown

type = loss

pattern = ==0%,==0%,==0%, ==U

comment = 主机完全宕机

to = alert@robot  # 关联到邮件管道，推送给机器人

*** Targets ***

+dns-11

menu = 谷歌-8.8.8.8

title = 谷歌-8.8.8.8

host = 8.8.8.8

alerts = hostdown  #添加告警设置

3.重启smokeping

4.验证方法：


# 执行测试
```
docker exec smokeping /smokeping/bin/send_mail.sh
"HostDown" "8.8.8.8" "loss: 100%" "500ms" "dns-11"

```


