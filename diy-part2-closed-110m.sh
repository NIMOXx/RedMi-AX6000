#!/bin/bash
# diy-part2-closed-110m.sh: 闭源驱动版 110m 大分区 DIY script part 2

# ============ 110m 大分区机型注入 ============
DTS_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/mt7986a-xiaomi-redmi-router-ax6000-110m.dts"
MK_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/filogic-110m-device.mk"
cp "$DTS_SRC" target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts || { echo "110m DTS 注入失败"; exit 1; }
cat "$MK_SRC" >> target/linux/mediatek/image/filogic.mk || { echo "110m 机型定义注入失败"; exit 1; }
grep -q "xiaomi_redmi-router-ax6000-110m" target/linux/mediatek/image/filogic.mk || { echo "110m 机型定义未写入 filogic.mk"; exit 1; }
[ -f target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts ] || { echo "110m DTS 未就位"; exit 1; }
echo "110m 机型注入完成"

# 修改默认 IP 为 192.168.6.1、主机名
sed -i 's/192.168.1.1/192.168.6.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/Redmi-AX6000/g' package/base-files/files/bin/config_generate

# firewall4 FullCone 补丁适配
if grep -q "^PKG_SOURCE_DATE:=2026-11-08" package/network/config/firewall4/Makefile 2>/dev/null; then
  cp "${GITHUB_WORKSPACE:-..}/patches/001-firewall4-add-support-for-fullcone-nat.patch" package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
  echo "已替换 firewall4 FullCone 补丁为适配新版（2026-11-08）的版本"
fi

# ==================== 注入私人定制配置 ====================
mkdir -p package/base-files/files/etc/uci-defaults

cat << "EOF" > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

# 1. 设置后台登录密码 (password)
echo -e "password\npassword" | passwd root

# 2. 设置 WAN 口为 DHCP 客户端
uci set network.wan.proto='dhcp'
uci delete network.wan.username
uci delete network.wan.password
uci commit network

# 3. 强制设置中文界面 + 上海时区
uci set luci.main.lang='zh_cn'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit luci
uci commit system

# 4. 固化官方 apk 软件源（剔除失效的 video 源及第三方延迟镜像）
mkdir -p /etc/apk/repositories.d
cat << "FEEDS" > /etc/apk/repositories.d/distfeeds.list
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/mediatek/filogic/packages/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/packages/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/routing/packages.adb
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_cortex-a53/telephony/packages.adb
FEEDS

# 5. 重新加载服务使配置生效
/etc/init.d/network restart

echo "99-custom-settings 执行完成"
exit 0
EOF

# ==================== 预置 OpenClash 内核与 GeoIP 数据库 ====================
mkdir -p package/base-files/files/etc/openclash/core

# 1. 下载 ARM64 版 mihomo (Meta) 内核
curl -fsSL --retry 3 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz | tar -xz -C package/base-files/files/etc/openclash/core/
mv package/base-files/files/etc/openclash/core/clash package/base-files/files/etc/openclash/core/clash_meta
chmod +x package/base-files/files/etc/openclash/core/clash_meta

# 2. 预置 GeoIP.dat 数据库
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat -o package/base-files/files/etc/openclash/GeoIP.dat

# 给生成的脚本赋予执行权限
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# ==================== 修复 Rust CI LLVM 过期 404 报错 ====================
if [ -f feeds/packages/lang/rust/Makefile ]; then
  sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g; s/download-ci-llvm=if-unchanged/download-ci-llvm=false/g' feeds/packages/lang/rust/Makefile
  echo "已修复 Rust download-ci-llvm 配置"
fi

echo "diy-part2-closed-110m.sh 执行完成：110m 机型与定制配置已注入！"
