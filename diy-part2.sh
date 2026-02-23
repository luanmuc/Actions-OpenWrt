#!/bin/bash

# ==============================================================================
# 固件版本：CMCC A10 MT7981 · iStoreOS 完美适配版
# 适配机型：CMCC A10 / MT7981
# 内核：Linux 5.4.x
# 主题：iStoreOS 官方主题 · 默认跟随系统(auto)
# ==============================================================================
# 优化修改日志（便于后续升级迭代）
# 1. 主题更换为 iStoreOS，默认 auto 跟随系统明暗，不强制深色
# 2. 加入全局 CSS 修复，兼容老插件按钮/输入框/深色模式（方案一）
# 3. 自定义 WiFi 功率页面完美适配 iStoreOS 主题
# 4. 已删除 pingcheck 掉线重启插件
# 5. 关闭 mwan3 / EQoS / 定时重启，避免冲突
# 6. 保留：内存自动清理、开机清理、BBR、HWNAT 硬件加速
# 7. 全插件样式统一，无错乱、无黑字、无兼容问题
# 8. 零设置开箱即用：IP/WiFi/密码全部预设
# ==============================================================================

# ==================== 基础配置 ====================
LAN_IP="192.168.123.1"
ROOT_PWD="admin"
WIFI_24G="CMCC-A10"
WIFI_5G="CMCC-A10-5G"
WIFI_KEY="lqlqq123456"

# 1. 后台 IP
sed -i "s/192.168.1.1/$LAN_IP/g" package/base-files/files/bin/config_generate

# 2. 管理密码
password=$(openssl passwd -1 "$ROOT_PWD")
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

uci set wireless.radio0.country='CN'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.bandwidth='20'
uci set wireless.radio0.txpower='20'

uci set wireless.radio1.country='CN'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.bandwidth='80'
uci set wireless.radio1.txpower='23'

uci commit wireless

# 4. 代理默认关闭
uci set passwall.@global[0].enabled=0
uci set passwall.@global[0].route_mode=0
uci commit passwall

# 5. DNS 优化
uci set dhcp.@dnsmasq[0].cachesize='2048'
uci commit dhcp

# 6. 加速优化
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci commit firewall

# 7. 内核优化 BBR
cat > /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq_codel
net.core.netdev_max_backlog=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_forward=1
vm.swappiness=0
vm.vfs_cache_pressure=80
vm.min_free_kbytes=16384
EOF

# ==================== iStoreOS 主题 · 默认跟随系统 ====================
uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/istore'
uci -q get istore.config >/dev/null || uci set istore.config=global
uci set istore.config.theme='auto'
uci commit istore
uci commit luci

# ==================== 方案一：全局CSS样式修复（全插件适配iStoreOS）====================
mkdir -p /www/luci-static/istore/css/
cat > /www/luci-static/istore/css/fix-compat.css <<EOF
/* 全局修复老插件样式 */
input[type="submit"], input[type="button"], button, .cbi-button {
    background-color: var(--color-primary) !important;
    color: #fff !important;
    border: none !important;
    padding: 6px 16px !important;
    border-radius: 4px !important;
    cursor: pointer !important;
    margin:2px !important;
}
input[type="submit"]:hover, button:hover {
    opacity:0.9 !important;
}
input, select, textarea {
    background-color: var(--color-bg) !important;
    color: var(--color-text) !important;
    border: 1px solid var(--color-border) !important;
    border-radius: 4px !important;
    padding:6px !important;
}
.cbi-section {
    padding:15px !important;
}
EOF

sed -i '/<link rel="stylesheet"/a <link rel="stylesheet" href="/luci-static/istore/css/fix-compat.css"/>' /www/luci-static/istore/header.htm 2>/dev/null

# 8. 关闭无用服务
/etc/init.d/telemetry disable 2>/dev/null
/etc/init.d/atd disable 2>/dev/null

# ==================== WiFi 功率一键切换 ====================
cat > /usr/bin/wifi-power-cn <<EOF
#!/bin/sh
uci set wireless.radio0.country=CN
uci set wireless.radio0.txpower=20
uci set wireless.radio1.country=CN
uci set wireless.radio1.txpower=23
uci commit wireless
wifi reload
EOF

cat > /usr/bin/wifi-power-us <<EOF
#!/bin/sh
uci set wireless.radio0.country=US
uci set wireless.radio0.txpower=30
uci set wireless.radio1.country=US
uci set wireless.radio1.txpower=28
uci commit wireless
wifi reload
EOF

chmod +x /usr/bin/wifi-power-cn /usr/bin/wifi-power-us

mkdir -p /usr/lib/lua/luci/controller/
cat > /usr/lib/lua/luci/controller/wifi_power.lua <<EOF
module("luci.controller.wifi_power", package.seeall)
function index()
    entry({"admin","network","wifi_power"},call("action_wifi_power"),"📶 WiFi功率",60)
end
function action_wifi_power()
    local m=luci.http.formvalue("mode")
    if m=="cn" then luci.sys.call("/usr/bin/wifi-power-cn") end
    if m=="us" then luci.sys.call("/usr/bin/wifi-power-us") end
    luci.template.render("wifi_power",{mode=m})
end
EOF

mkdir -p /usr/lib/lua/luci/view/
cat > /usr/lib/lua/luci/view/wifi_power.htm <<EOF
<%+header%>
<div class="cbi-map">
<h2>WiFi 功率模式</h2>
<div class="cbi-section">
<div style="padding:15px;line-height:1.8">
<p>• 中国模式：合规稳定</p>
<p>• 美国模式：增强覆盖</p>
</div>
<div style="display:flex;gap:12px;padding:15px">
<a href="?mode=cn" class="btn" style="padding:6px 16px">中国模式</a>
<a href="?mode=us" class="btn btn-danger" style="padding:6px 16px">美国模式</a>
</div>
</div>
</div>
<%+footer%>
EOF

# ==================== 插件配置 ====================
# NTP
uci set ntp.@ntp[0].enable_server=1
uci set ntp.@ntp[0].server='cn.ntp.org.cn'
uci commit ntp

# 流量统计
/etc/init.d/nlbwmon enable
/etc/init.d/nlbwmon start

# UPnP
uci set upnpd.@upnpd[0].enable=1
uci commit upnpd

# 磁盘管理
/etc/init.d/diskman enable

# EQoS 关闭
uci set eqos.@eqos[0].enabled=0
uci commit eqos

# mwan3 禁用
/etc/init.d/mwan3 disable
uci set mwan3.global.enabled=0
uci commit mwan3

# 定时重启关闭
uci set autoreboot.@autoreboot[0].enable=0
uci commit autoreboot

# ==================== 内存自动清理 ====================
cat > /usr/bin/mem-autoclean <<EOF
#!/bin/sh
FREE_MEM=\$(free | awk '/^Mem:/{print \$4}')
LIMIT=15360
if [ \$FREE_MEM -lt \$LIMIT ]; then
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory
fi
EOF
chmod +x /usr/bin/mem-autoclean
echo "*/1 * * * * /usr/bin/mem-autoclean" >> /etc/crontabs/root
/etc/init.d/cron enable && /etc/init.d/cron start

# ==================== 开机自动清理 ====================
cat > /etc/init.d/autoclean <<EOF
#!/bin/sh /etc/rc.common
START=99
start() {
    rm -rf /tmp/* /var/tmp/* /var/log/* /var/run/*.pid
    find /tmp -type d -empty -delete
    > /root/.bash_history
}
EOF
chmod +x /etc/init.d/autoclean
/etc/init.d/autoclean enable

# ==================== 固件信息 ====================
cat > /etc/banner <<EOF
=================================================
  CMCC A10 MT7981 • iStoreOS 完美适配版
  内核：5.4.x｜全插件样式统一｜零设置开箱即用
=================================================
✅ iStoreOS 主题 · 自动跟随明暗
✅ 全局CSS修复 · 无样式错乱
✅ 硬件加速+BBR · WiFi功率一键切换
✅ 内存自动清理
=================================================
EOF

cat > /www/version_info.txt <<EOF
【固件】CMCC A10 MT7981 iStoreOS完美版
【后台】192.168.123.1
【密码】admin
【WiFi】CMCC-A10 / 5G  密码：lqlqq123456
【主题】iStoreOS（auto自动明暗）
【修复】全局CSS兼容所有插件按钮/输入框/深色模式
【优化】BBR+硬件加速+内存自动回收
EOF

# 安全清理
rm -rf /usr/share/man/* /usr/share/doc/* /tmp/* /var/log/* >/dev/null 2>&1

exit 0
