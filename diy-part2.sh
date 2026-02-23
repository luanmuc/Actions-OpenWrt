#!/bin/bash

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

# 3. WiFi 配置（中国合规最大功率）
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

# 4. 代理默认关闭（防冲突）
uci set passwall.@global[0].enabled=0
uci set passwall.@global[0].route_mode=0
uci commit passwall

# 5. DNS 优化
uci set dhcp.@dnsmasq[0].cachesize='2048'
uci commit dhcp

# 6. 加速优化（关闭 SFE，避免冲突）
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

# 8. Argon 主题美化
uci set argon.global=global
uci set argon.global.theme='dark'
uci set argon.global.mode='dark'
uci set argon.global.blur='1'
uci set argon.global.transparency='80'
uci set argon.global.accent='blue'
uci commit argon

uci set luci.main.lang='zh_cn'
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci

# 9. 关闭无用服务
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

chmod +x /usr/bin/wifi-power-cn
chmod +x /usr/bin/wifi-power-us

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
<div style="padding:15px">
<p>• 中国模式：合规稳定</p>
<p>• 美国模式：超强覆盖</p>
</div>
<div style="display:flex;gap:15px;padding:15px">
<button onclick="location.href='?mode=cn'" class="btn btn-primary">中国模式</button>
<button onclick="location.href='?mode=us'" class="btn btn-danger">美国模式</button>
</div>
</div>
</div>
<%+footer%>
EOF

# ==================== 插件最优配置（无冲突） ====================
# 断网自动重启 PingCheck
uci set pingcheck.@pingcheck[0].enable=1
uci set pingcheck.@pingcheck[0].ipaddr='114.114.114.114'
uci set pingcheck.@pingcheck[0].count=3
uci set pingcheck.@pingcheck[0].action=1
uci commit pingcheck

# NTP 时间同步
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

# EQoS 默认关闭
uci set eqos.@eqos[0].enabled=0
uci commit eqos

# mwan3 完全禁用（防冲突）
/etc/init.d/mwan3 disable
uci set mwan3.global.enabled=0
uci commit mwan3

# 定时重启默认关闭
uci set autoreboot.@autoreboot[0].enable=0
uci commit autoreboot

# ==================== 内存不足自动清理（CMCC A10 专用） ====================
cat > /usr/bin/mem-autoclean <<EOF
#!/bin/sh
FREE_MEM=\$(free | awk '/^Mem:/{print \$4}')
LIMIT=15360
if [ \$FREE_MEM -lt \$LIMIT ]; then
    sync
    echo 3 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory
    echo "[\$(date)] 内存不足，已自动清理缓存" >> /tmp/mem_autoclean.log
fi
EOF
chmod +x /usr/bin/mem-autoclean

echo "*/1 * * * * /usr/bin/mem-autoclean" >> /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron start

# ==================== 开机自动清理 ====================
cat > /etc/init.d/autoclean <<EOF
#!/bin/sh /etc/rc.common
START=99
start() {
    rm -rf /tmp/* /var/tmp/* /var/log/* /var/run/*.pid
    find /tmp -type d -empty -delete
    > /root/.bash_history
    > /etc/bench.log
}
EOF
chmod +x /etc/init.d/autoclean
/etc/init.d/autoclean enable
/etc/init.d/autoclean start

# ==================== 云编译专用 · 升级信息 + 配置日志 ====================
cat > /etc/banner <<EOF
=================================================
  CMCC A10 (MT7981) 全能定制固件
  内核：5.4.x ｜ 主题：Argon 深色
  编译时间：$(date +%Y-%m-%d %H:%M:%S)
=================================================
✅ WiFi 中美功率一键切换
✅ TurboACC+HWNAT 硬件加速（无SFE）
✅ iStore 插件商店
✅ 内存不足自动清理
✅ 断网自动重启（pingcheck）
✅ 全套日用插件 · 最优无冲突
✅ 开机自动清理 + 固件瘦身
=================================================
EOF

cat > /www/version_info.txt <<EOF
【固件版本】CMCC A10 MT7981 最终全能版
【编译环境】云编译
【内核版本】5.4 稳定版
【后台地址】192.168.123.1
【管理密码】admin
【WiFi信息】CMCC-A10 / 密码：lqlqq123456

【功能清单】
1. Argon 深度美化后台
2. WiFi 中国/美国最大功率切换
3. iStore 插件商店
4. 内存不足自动清理（<15MB触发）
5. 断网自动重启（ping 114.114.114.114）
6. BBR + 硬件加速 + 流控优化
7. 全套代理默认关闭，不冲突
8. 流量统计、设备限速、磁盘管理
9. 开机自动清理缓存
10. 已精简：Samba4、冗余组件

【声明】仅供合法使用，请勿用于非法用途
EOF

cat > /etc/firmware_config.log <<EOF
# ========== 固件完整配置日志 · 下次升级直接发我 ==========
DEVICE: CMCC A10 (MT7981)
KERNEL: 5.4.x
IP: 192.168.123.1
PASSWD: admin
SSID: CMCC-A10
WIFI_KEY: lqlqq123456
THEME: Argon 深色

【已做优化】
1. WiFi 中国模式：2.4G=20dBm 5G=23dBm
2. 美国模式：2.4G=30dBm 5G=28dBm（一键切换）
3. 加速：TurboACC + HWNAT（SFE已关闭）
4. BBR 已启用
5. 内存自动清理：低于15MB自动drop_caches
6. 断网重启：pingcheck 启用
7. 开机自动清理
8. 代理默认关闭
9. mwan3 已禁用
10. EQoS 默认关闭
11. UPnP 默认开启
12. nlbwmon 流量统计默认开启

【已集成插件】
- iStore 商店
- Passwall / Mihomo / HomeProxy
- AdGuard Home
- SmartDNS
- TurboACC
- pingcheck
- diskman、filemanager
- eqos、nlbwmon、wrtbwmon
- ttyd、wol、ddns、upnp、ddnsto
- autoreboot、ntpc、logread

【已移除】
- Samba4
- SFE
- vsftpd
- watchcat

【无冲突保障】
- 加速只留 TurboACC+HWNAT
- 多线、SFE、冲突组件全部关闭
- 缓存自动回收
- 系统资源最低占用
EOF

# ==================== 云编译安全清理 ====================
rm -rf /usr/share/man/* /usr/share/doc/* /tmp/* /var/log/* >/dev/null 2>&1

exit 0
