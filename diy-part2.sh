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

# 处理 luci-app-airoha-npu (从 ImmortalWrt 官方分支/主库抽取)
rm -rf package/luci-app-airoha-npu package/airoha-tmp
# 从维护 AN7581 / Airoha 最全的 ImmortalWrt 官方 LuCI 仓库中提取
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/airoha-tmp
cd package/airoha-tmp
git sparse-checkout set applications/luci-app-airoha-npu
cd ../..
if [ -d "package/airoha-tmp/applications/luci-app-airoha-npu" ]; then
    mv package/airoha-tmp/applications/luci-app-airoha-npu package/luci-app-airoha-npu
fi
rm -rf package/airoha-tmp

# 拉取 vlmcsd 包
# 1. 彻底清理旧目录
rm -rf package/vlmcsd package/luci-app-vlmcsd package/vlmcsd-tmp

# 2. 从 ImmortalWrt 官方 packages 和 luci 仓库拉取 vlmcsd 及界面包
git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set net/vlmcsd
cd ../..
mv package/vlmcsd-tmp/net/vlmcsd package/vlmcsd
rm -rf package/vlmcsd-tmp

git clone --depth=1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git package/vlmcsd-tmp
cd package/vlmcsd-tmp
git sparse-checkout set applications/luci-app-vlmcsd
cd ../..
mv package/vlmcsd-tmp/applications/luci-app-vlmcsd package/luci-app-vlmcsd
rm -rf package/vlmcsd-tmp
