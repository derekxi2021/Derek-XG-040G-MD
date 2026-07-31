#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
#echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
#echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default
echo 'src-git helloworld https://github.com/kenzok8/small' >>feeds.conf.default
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages' >>feeds.conf.default
echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2' >>feeds.conf.default
# 2. 判断并进入 openwrt 目录（兼容 Actions 环境与本地环境）
if [ -d "openwrt" ]; then
    cd openwrt
fi

# 3. 在 openwrt/package/ 内部创建 custom 目录并 clone 仓库
mkdir -p package/custom
git clone --depth=1 https://github.com/sbwml/openwrt-vlmcsd.git package/custom/vlmcsd
git clone --depth=1 https://github.com/sbwml/luci-app-vlmcsd.git package/custom/luci-app-vlmcsd
