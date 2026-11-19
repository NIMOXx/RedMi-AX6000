#!/bin/bash
# diy-part1.sh: OpenWrt DIY script part 1 (Before Update feeds)

# 添加 OpenClash 源码
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/OpenClash

git clone --depth=1 https://github.com/ni-ning/luci-theme-vantage.git package/luci-theme-vantage

echo "diy-part1.sh 执行完成：已添加 OpenClash。"
