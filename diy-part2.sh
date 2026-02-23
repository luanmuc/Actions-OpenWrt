#!/bin/bash

# ==================== 你的信息 ====================
LAN_IP="192.168.123.1"
ROOT_PWD="admin"
WIFI_24G="CMCC-A10"
WIFI_5G="CMCC-A10-5G"
WIFI_KEY="lplqq123456"
# ==================================================

# 1. 设置后台 IP
sed -i "s/192.168.1.1/$LAN_IP/g" package/base-files/files/bin/config_generate

# 2. 设置管理员密码
password=$(openssl passwd -1 $ROOT_PWD)
sed -i "s|root::|root:$password:|g" package/base-files/files/etc/shadow

# 3. WiFi 配置
uci set wireless.default_radio0.ssid="$WIFI_24G"
uci set wireless.default_radio0.key="$WIFI_KEY"
uci set wireless.default_radio0.encryption='psk2+ccmp'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.disabled='0'

uci set wireless.default_radio1.ssid="$WIFI_5G"
uci set wireless.default_radio1.key="$WIFI_KEY"
uci set wireless.default_radio1.encryption='psk2+ccmp'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.disabled='0'

# WiFi 优化
uci set wireless.radio0.country='CN'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.bandwidth='20'

uci set wireless.radio1.country='CN'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.bandwidth='80'

uci commit wireless

# 4. 旁路由默认关闭
uci set passwall.@global[0].enabled=0
uci set passwall.@global[0].route_mode=0
uci commit passwall

# 5. DNS 优化
uci set dhcp.@dnsmasq[0].cachesize='2048'
uci commit dhcp

# 6. 防火墙加速
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci commit firewall

# 7. 内核网络优化
cat > /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq_codel
net.core.netdev_max_backlog=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_forward=1
EOF

# 8. Argon 主题美化
uci set argon.@global[0].theme='dark'
uci set argon.@global[0].mode='dark'
uci set argon.@global[0].blur='1'
uci set argon.@global[0].transparency='100'
uci set argon.@global[0].system_theme='argon'
uci commit argon

uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 9. 关闭无用服务
/etc/init.d/telemetry disable 2>/dev/null
/etc/init.d/atd disable 2>/dev/null
/etc/init.d/cron disable 2>/dev/null

exit 0
