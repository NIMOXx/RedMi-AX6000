#!/bin/bash
set -e

# 添加 OpenClash 源码
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/OpenClash

# 添加 Vantage 主题及配套插件源码
git clone --depth=1 https://github.com/anothaDev/luci-theme-vantage.git package/vantage

echo "diy-part1.sh 执行完成：已添加 OpenClash 与 Vantage 主题。"
