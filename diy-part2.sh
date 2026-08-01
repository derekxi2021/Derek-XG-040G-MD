#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# 在 openwrt 根目录下拉取 airoha-npu 包
git clone https://github.com/nethunter88/luci-app-airoha-npu.git package/luci-app-airoha-npu

# 在 openwrt 根目录下拉取 vlmcsd 包
git clone https://github.com/openwrt-develop/luci-app-vlmcsd.gits package/luci-app-vlmcsd
git clone https://github.com/cokebar/openwrt-vlmcsd.git package/vlmcsd
