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
rm -rf package/luci-app-airoha-npu
git clone https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu

# 在 openwrt 根目录下拉取 vlmcsd 包
rm -rf package/vlmcsd package/luci-app-vlmcsd
# 从 ImmortalWrt 官方 packages 库中精准拉取 net/vlmcsd
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp
# 拉取配套的 LuCI 界面
git clone https://github.com/openwrt-develop/luci-app-vlmcsd.git package/luci-app-vlmcsd
