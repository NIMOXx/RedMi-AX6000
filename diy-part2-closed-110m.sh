#!/bin/bash
# diy-part2-closed-110m.sh: 闭源驱动版 110m 大分区 DIY script part 2
# 与 diy-part2-closed.sh 完全相同，另加一步：把 110m 机型注入编译树
# （rebase 上游只有 stock 与 ubootmod 两个 AX6000 机型，没有 110m 机型；
#  110m 布局 = 单个 110MB ubi 分区，对应 hanwckf uboot 的 immortalwrt-110m 布局）。
# 注入的两样东西都在仓库 devices/ax6000-110m/ 里：
#   mt7986a-xiaomi-redmi-router-ax6000-110m.dts → target/linux/mediatek/dts/
#   filogic-110m-device.mk（机型定义）→ 追加到 target/linux/mediatek/image/filogic.mk 末尾

# ============ 110m 大分区机型注入 ============
DTS_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/mt7986a-xiaomi-redmi-router-ax6000-110m.dts"
MK_SRC="${GITHUB_WORKSPACE:-..}/devices/ax6000-110m/filogic-110m-device.mk"
cp "$DTS_SRC" target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts || { echo "110m DTS 注入失败"; exit 1; }
cat "$MK_SRC" >> target/linux/mediatek/image/filogic.mk || { echo "110m 机型定义注入失败"; exit 1; }
grep -q "xiaomi_redmi-router-ax6000-110m" target/linux/mediatek/image/filogic.mk || { echo "110m 机型定义未写入 filogic.mk"; exit 1; }
[ -f target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-110m.dts ] || { echo "110m DTS 未就位"; exit 1; }
echo "110m 机型注入完成"

# 修改默认 IP、主机名
sed -i 's/192.168.1.1/192.168.8.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/Redmi-AX6000/g' package/base-files/files/bin/config_generate
# 主题：保留默认 Bootstrap 兜底，不再强制替换为 Argon；
# Vantage 首次开机通过自带的 30_luci-theme-vantage 自动设为默认主题。

# firewall4 FullCone 补丁：25.12（master）的 firewall4 已升级到 2026-11-08，
# 上游删掉了 config 里的 disable_ipv6 行，自带旧补丁第一块打不上导致编译失败；
# 只有新版才用仓库里重做过的补丁替换，24.10 保持原样不动
if grep -q "^PKG_SOURCE_DATE:=2026-11-08" package/network/config/firewall4/Makefile 2>/dev/null; then
  cp "${GITHUB_WORKSPACE:-..}/patches/001-firewall4-add-support-for-fullcone-nat.patch" package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch
  echo "已替换 firewall4 FullCone 补丁为适配新版（2026-11-08）的版本"
fi

# ==================== 注入你的私人定制配置 ====================
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

# 3. WiFi：闭源驱动版不走标准 uci wireless（mtwifi 用自家的 wifi-profile 配置），
#    上面那套 uci 设置写了也不生效，所以这里不写；刷完后在 LuCI → MTK WiFi 里改名称和密码。
#    注意：首次开机 WiFi 名称/密码是驱动默认 profile 的值，不是 OpenWrt_2.4G/5G。

# 4. 强制设置中文界面 + 上海时区
uci set luci.main.lang='zh_cn'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit luci
uci commit system

# 7. 重新加载服务使配置生效
/etc/init.d/network restart

echo "99-custom-settings 执行完成：拨号、WiFi分离、中文界面、Tailscale社区源已就绪"
exit 0
EOF

# ==================== 预置 OpenClash 内核与全套规则数据库 ====================
mkdir -p package/base-files/files/etc/openclash/core

# 1. 下载 ARM64 版 mihomo (Meta) 内核（带 3 次重试容错）
curl -fsSL --retry 3 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz | tar -xz -C package/base-files/files/etc/openclash/core/
mv package/base-files/files/etc/openclash/core/clash package/base-files/files/etc/openclash/core/clash_meta
chmod +x package/base-files/files/etc/openclash/core/clash_meta

# 2. 预置 GeoIP 与 GeoSite 数据库（避免刷机后首次启动卡规则下载）
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb -o package/base-files/files/etc/openclash/Country.mmdb
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat -o package/base-files/files/etc/openclash/GeoIP.dat
curl -fsSL --retry 3 https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat -o package/base-files/files/etc/openclash/GeoSite.dat

# 3. 预置 IPv4 与 IPv6 大陆白名单路由表
echo "create china_ip_route hash:net family inet hashsize 1024 maxelem 1000000" > package/base-files/files/etc/openclash/china_ip_route.ipset
curl -fsSL --retry 3 https://ispip.clang.cn/all_cn.txt | awk '{print "add china_ip_route " $1}' >> package/base-files/files/etc/openclash/china_ip_route.ipset
echo "create china_ip6_route hash:net family inet6 hashsize 1024 maxelem 1000000" > package/base-files/files/etc/openclash/china_ip6_route.ipset
curl -fsSL --retry 3 https://ispip.clang.cn/all_cn_ipv6.txt | awk '{print "add china_ip6_route " $1}' >> package/base-files/files/etc/openclash/china_ip6_route.ipset

# 给生成的脚本赋予执行权限
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

# ==================== 修复 Rust CI LLVM 过期 404 报错 ====================
if [ -f feeds/packages/lang/rust/Makefile ]; then
  sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g; s/download-ci-llvm=if-unchanged/download-ci-llvm=false/g' feeds/packages/lang/rust/Makefile
  echo "已修复 Rust download-ci-llvm 配置"
fi

echo "diy-part2-closed-110m.sh 执行完成：110m 机型已注入，最终定制逻辑已注入！"
