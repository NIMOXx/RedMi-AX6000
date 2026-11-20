#!/bin/bash
set -e
# diy-part2-closed-110m.sh: 闭源驱动版 110m 大分区终极完整脚本（含无 Key 版 Bark 推送）

# ============ 110m 大分区机型注入 ============
DTS_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/mt7986a-xiaomi-redmi-router-ax6000-110m.dts"
MK_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/filogic-110m-device.mk"
cp "$DTS_SRC" target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts
cat "$MK_SRC" >> target/linux/mediatek/image/filogic.mk
grep -q "xiaomi_redmi-router-ax6000-110m" target/linux/mediatek/image/filogic.mk
[ -f target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts ]
echo "110m 机型注入完成"

# 修改默认 IP 为 192.168.6.1、修复主机名为 Redmi-AX6000
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/Redmi-AX6000/g; s/OpenWrt/Redmi-AX6000/g' package/base-files/files/bin/config_generate

# firewall4 FullCone 补丁适配
if grep -q "^PKG_SOURCE_DATE:=2026-11-08" package/network/config/firewall4/Makefile 2>/dev/null; then
  cp "${GITHUB_WORKSPACE:-..}/patches/001-firewall4-add-support-for-fullcone-nat.patch" package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
  echo "已替换 firewall4 FullCone 补丁"
fi

# ==================== 注入首次开机定制脚本 ====================
mkdir -p package/base-files/files/etc/uci-defaults

cat << "EOF" > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

# 1. 设置后台登录密码 (password)
echo -e "password\npassword" | passwd root

# 2. 设置 WAN 口为 DHCP 客户端
uci set network.wan.proto='dhcp'
uci delete network.wan.username 2>/dev/null
uci delete network.wan.password 2>/dev/null
uci commit network

# 3. 设置中文界面、上海时区及默认启用 Vantage 主题
uci set luci.main.lang='zh_cn'
if [ -d /www/luci-static/vantage ]; then
  uci set luci.main.mediaurlbase='/luci-static/vantage'
fi
uci commit luci

uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

# 4. 固化 TurboACC 闭源硬件加速防冲突参数，并关闭防火墙默认 FullCone
if [ -f /etc/config/turboacc ]; then
  uci set turboacc.config.sw_flow='0'
  uci set turboacc.config.hw_flow='1'
  uci set turboacc.config.bbr_cca='1'
  uci set turboacc.config.fullcone_nat='0'
  uci set turboacc.config.dns_caching='0'
  uci commit turboacc
fi

uci set firewall.@defaults[0].fullcone='0'
uci set firewall.@defaults[0].fullcone6='0'
uci commit firewall

# 5. 固化官方 apk 软件源（剔除报错的 video 源及第三方延迟镜像）
mkdir -p /etc/apk/repositories.d
cat << "FEEDS" > /etc/apk/repositories.d/distfeeds.list
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/mediatek/filogic/packages/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/packages/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/routing/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/telephony/packages.adb
FEEDS

# 6. 写入每天凌晨 4:00 自动清理内存缓存的计划任务
mkdir -p /etc/crontabs
grep -q "drop_caches" /etc/crontabs/root 2>/dev/null || echo "0 4 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >> /etc/crontabs/root

echo "99-custom-settings 执行完成"
exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# ==================== 固化无 Key 版 Bark 开机/重连推送脚本 ====================
mkdir -p package/base-files/files/etc/hotplug.d/iface
mkdir -p package/base-files/files/lib/upgrade/keep.d

# 1. 预置空 Key 文件并注册到升级永久保留清单
touch package/base-files/files/etc/bark_key
echo "/etc/bark_key" > package/base-files/files/lib/upgrade/keep.d/bark-notify

# 2. 写入 Hotplug 监听脚本（自动读取 /etc/bark_key，兼容纯 Key 或完整 URL）
cat << 'EOF' > package/base-files/files/etc/hotplug.d/iface/99-bark-notify
#!/bin/sh

[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "wan" ] || exit 0

KEY_FILE="/etc/bark_key"
[ -s "$KEY_FILE" ] || exit 0

RAW_KEY=$(tr -d ' \r\n' < "$KEY_FILE")
[ -z "$RAW_KEY" ] && exit 0

RAW_KEY="${RAW_KEY%/}"
if [ "${RAW_KEY#http}" = "$RAW_KEY" ]; then
  BARK_URL="https://api.day.app/${RAW_KEY}"
else
  BARK_URL="$RAW_KEY"
fi

mkdir /tmp/bark_notify.lock 2>/dev/null || exit 0

(
  trap 'rmdir /tmp/bark_notify.lock 2>/dev/null' EXIT
  sleep 10

  WAN_DEV="$DEVICE"
  [ -z "$WAN_DEV" ] && WAN_DEV=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
  WAN_IP=$(ip -4 addr show dev "$WAN_DEV" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
  [ -z "$WAN_IP" ] && WAN_IP="未获取到"
  NOW_TIME=$(date "+%Y-%m-%d %H:%M:%S")

  if [ ! -f /tmp/bark_boot_notified ]; then
    touch /tmp/bark_boot_notified
    TITLE="Redmi-AX6000 已重启联网"
    BODY="时间：${NOW_TIME}\nWAN IP：${WAN_IP}"
  else
    TITLE="Redmi-AX6000 外网已重连"
    BODY="时间：${NOW_TIME}\n新 WAN IP：${WAN_IP}"
  fi

  curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 10 --max-time 20 \
    -X POST "$BARK_URL" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"title\":\"${TITLE}\",\"body\":\"${BODY}\",\"group\":\"Redmi-AX6000\"}" >/dev/null 2>&1

  logger -t bark-notify "已发送推送: ${TITLE} (${WAN_IP})"
) &
EOF

chmod 755 package/base-files/files/etc/hotplug.d/iface/99-bark-notify

# ==================== 预置 OpenClash 内核与规则数据库 ====================
mkdir -p package/base-files/files/etc/openclash/core

# 1. 下载 ARM64 版 mihomo (Meta) 内核
curl -fsSL --retry 3 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz | tar -xz -C package/base-files/files/etc/openclash/core/
mv package/base-files/files/etc/openclash/core/clash package/base-files/files/etc/openclash/core/clash_meta
chmod +x package/base-files/files/etc/openclash/core/clash_meta

# 2. 预置 GeoIP.dat 与 GeoSite.dat 数据库
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat -o package/base-files/files/etc/openclash/GeoIP.dat
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat -o package/base-files/files/etc/openclash/GeoSite.dat

# ==================== 修复 Rust CI LLVM 过期 404 报错（兜底） ====================
if [ -f feeds/packages/lang/rust/Makefile ]; then
  sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g; s/download-ci-llvm=if-unchanged/download-ci-llvm=false/g' feeds/packages/lang/rust/Makefile
fi

echo "diy-part2-closed-110m.sh 执行完成：110m 机型、定制配置与无 Key 版 Bark 推送已注入！"
